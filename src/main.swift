import Carbon
import Cocoa
import ServiceManagement
import WebKit

struct Station {
    let name: String
    let logo: String
    let url: URL
    let startScript: String
    let nowPlayingURL: URL
    let nowPlaying: ([String: Any]) -> String?
}

private func nonEmpty(_ values: [Any?]) -> [String] {
    values.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

let stations = [
    Station(
        name: "Radio 357",
        logo: "logo-357",
        url: URL(string: "https://radio357.pl")!,
        startScript: "document.querySelector('audio') && document.querySelector('audio').play()",
        nowPlayingURL: URL(string: "https://stream.radio357.pl/now/playing.json")!,
        // Between songs "s" carries the station's slogan, so the show and its host stand in.
        nowPlaying: { json in
            if let song = nonEmpty([json["s"]]).first, !song.hasPrefix("Radio 357") {
                return song.replacingOccurrences(of: " - ", with: " – ")
            }
            let show = json["p"] as? [String: Any]
            let parts = nonEmpty([show?["n"], show?["a"]])
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    ),
    Station(
        name: "Nowy Świat",
        logo: "logo-ns",
        url: URL(string: "https://nowyswiat.online")!,
        startScript: "document.querySelector('#neoplayer-play button') && document.querySelector('#neoplayer-play button').click()",
        nowPlayingURL: URL(string: "https://nowyswiat.online/api/oZeta/stat")!,
        // The API names the fields the other way round: "title" holds the artist, "artist" the song.
        nowPlaying: { json in
            let data = json["data"] as? [String: Any]
            let parts = nonEmpty([data?["title"], data?["artist"]]).filter { $0 != "Radio Nowy Świat" }
            return parts.isEmpty ? nil : parts.joined(separator: " – ")
        }
    ),
]

private let spotifyTag = -1
private let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client")

private let hotKeys: [(id: UInt32, key: Int, action: String)] = [
    (1, kVK_ANSI_M, "mute"),
    (2, kVK_UpArrow, "up"),
    (3, kVK_DownArrow, "down"),
]

// Tracks every media element the page plays, including detached `new Audio()` ones the DOM can't reach.
private func pageScript(initialVolume: Double) -> String {
    """
    (() => {
      const media = new Set();
      let volume = \(initialVolume);
      const track = m => { media.add(m); m.volume = volume; };
      const play = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function () { track(this); return play.apply(this, arguments); };
      document.addEventListener('play', e => { if (e.target instanceof HTMLMediaElement) track(e.target); }, true);
      window.__stationSetVolume = v => {
        volume = v;
        document.querySelectorAll('audio, video').forEach(m => media.add(m));
        media.forEach(m => { m.volume = v; });
      };
      window.__stationIsPlaying = () => [...media].some(m => !m.paused);
    })();
    """
}


final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, NSMenuItemValidation {
    var window: NSWindow!
    var web: WKWebView!
    var statusItem: NSStatusItem!
    var slider: NSSlider!
    var muteButton: NSButton!
    var levelLabel: NSTextField!
    var muteMenuItem: NSMenuItem!
    var stationMenuItems: [NSMenuItem] = []
    var appStationMenuItems: [NSMenuItem] = []
    var hotKeyRefs: [EventHotKeyRef] = []
    var current: Int?
    var spotifyActive = false
    var spotifyTrack: String?
    var stationTrack: String?
    var spotifyMenuItems: [NSMenuItem] = []
    let spotifyQueue = DispatchQueue(label: "spotify")
    var pendingNavigation: WKNavigation?
    var muted = false
    var volume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(
            WKUserScript(source: pageScript(initialVolume: volume), injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        web.navigationDelegate = self

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.contentView = web
        window.center()
        window.setFrameAutosaveName("main")

        #if DEBUGHOOK
        installDebugHook()
        #endif
        NSApp.mainMenu = makeMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "radio"
        if NSApp.activationPolicy() != .regular { statusItem.isVisible = true }
        statusItem.button?.imagePosition = .imageLeft
        statusItem.menu = makeStatusMenu()
        installScrollVolume()
        installHotKeys()
        observeSpotify()
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.fetchNowPlaying() }

        let last = UserDefaults.standard.object(forKey: "station") as? Int ?? 0
        if last == spotifyTag, spotifyURL != nil {
            playSpotify()
        } else {
            play(station: stations.indices.contains(last) ? last : 0)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Closing the window must only hide it — destroying it would kill the web view and stop the stream.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for (index, station) in stations.enumerated() {
            let entry = item(station.name, #selector(stationChosen(_:)), "")
            entry.tag = index
            entry.state = index == current ? .on : .off
            menu.addItem(entry)
        }
        if spotifyURL != nil {
            let entry = item("Spotify", #selector(playSpotify), "")
            entry.state = spotifyActive ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item(muted ? "Włącz dźwięk" : "Wycisz", #selector(toggleMute), ""))
        menu.addItem(item("Wyłącz radio", #selector(turnOff), ""))
        return menu
    }

    // didFinish can't be used: radio357.pl keeps loading resources and never fires it.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard navigation === pendingNavigation else { return }
        autostart(navigation: navigation, attempt: 0)
    }

    // Driven from Swift because WebKit counts evaluateJavaScript as a user gesture but not a page timer, so
    // play() from a setTimeout is refused. Checks before each try because the start button is a play/pause toggle.
    private func autostart(navigation: WKNavigation, attempt: Int) {
        guard navigation === pendingNavigation, attempt < 8, let current else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 2 : 3)) { [weak self] in
            guard let self, navigation === self.pendingNavigation else { return }
            self.web.evaluateJavaScript("window.__stationIsPlaying && window.__stationIsPlaying()") { playing, _ in
                guard (playing as? Bool) != true else { return }
                self.web.evaluateJavaScript(stations[current].startScript) { _, _ in }
                self.autostart(navigation: navigation, attempt: attempt + 1)
            }
        }
    }

    func play(station index: Int) {
        stopSpotify()
        current = index
        stationTrack = nil
        fetchNowPlaying()
        UserDefaults.standard.set(index, forKey: "station")
        pendingNavigation = web.load(URLRequest(url: stations[index].url))
        refreshIndicators()
    }

    @objc func stationChosen(_ sender: NSMenuItem) {
        play(station: sender.tag)
    }

    @objc func turnOff() {
        stopRadio()
        stopSpotify()
        refreshIndicators()
    }

    @objc func playSpotify() {
        stopRadio()
        spotifyActive = true
        UserDefaults.standard.set(spotifyTag, forKey: "station")
        spotify("set sound volume to \(spotifyVolume)\nplay\nreturn artist of current track & \" – \" & name of current track") { [weak self] track in
            self?.spotifyTrack = track
            self?.refreshIndicators()
        }
        refreshIndicators()
    }

    private func stopRadio() {
        guard current != nil else { return }
        current = nil
        pendingNavigation = web.load(URLRequest(url: URL(string: "about:blank")!))
    }

    private func stopSpotify() {
        guard spotifyActive else { return }
        spotifyActive = false
        spotify("pause")
    }

    private func fetchNowPlaying() {
        guard let index = current else { return }
        var request = URLRequest(url: stations[index].nowPlayingURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let track = json.flatMap(stations[index].nowPlaying)
            DispatchQueue.main.async {
                guard let self, self.current == index, track != self.stationTrack else { return }
                self.stationTrack = track
                self.refreshIndicators()
            }
        }.resume()
    }

    private var spotifyVolume: Int { muted ? 0 : Int((volume * 100).rounded()) }

    // Spotify broadcasts every play/pause/track change, so playback started in Spotify itself takes over from the radio.
    private func observeSpotify() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            guard let self, let info = note.userInfo else { return }
            if let name = info["Name"] as? String {
                self.spotifyTrack = [info["Artist"] as? String, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
            }
            if info["Player State"] as? String == "Playing", !self.spotifyActive {
                self.stopRadio()
                self.spotifyActive = true
                UserDefaults.standard.set(spotifyTag, forKey: "station")
                self.spotify("set sound volume to \(self.spotifyVolume)")
            }
            self.refreshIndicators()
        }
    }

    private func spotify(_ commands: String, then: ((String) -> Void)? = nil) {
        let source = "tell application id \"com.spotify.client\"\n\(commands)\nend tell"
        spotifyQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let then, let text = result?.stringValue { DispatchQueue.main.async { then(text) } }
            guard let code = error?[NSAppleScript.errorNumber] as? Int, code == -1743 else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Radio nie ma zgody na sterowanie Spotify"
                alert.informativeText = "Włącz Spotify przy Radio w Ustawieniach systemowych → Prywatność i ochrona → Automatyzacja."
                alert.addButton(withTitle: "Otwórz Ustawienia")
                alert.addButton(withTitle: "Anuluj")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            }
        }
    }

    @objc func toggleMute() {
        muted.toggle()
        // WebKit's page mute silences every audio path, Web Audio included, which per-element `muted` misses.
        let selector = NSSelectorFromString("_setPageMuted:")
        if web.responds(to: selector) {
            typealias SetMuted = @convention(c) (AnyObject, Selector, UInt) -> Void
            unsafeBitCast(web.method(for: selector), to: SetMuted.self)(web, selector, muted ? 1 : 0)
        } else {
            web.evaluateJavaScript("document.querySelectorAll('audio, video').forEach(m => { m.muted = \(muted); })")
        }
        if spotifyActive { spotify("set sound volume to \(spotifyVolume)") }
        refreshIndicators()
    }

    @objc func volumeUp() { setVolume(volume + 0.1) }
    @objc func volumeDown() { setVolume(volume - 0.1) }
    @objc func sliderMoved(_ sender: NSSlider) { setVolume(sender.doubleValue / 100) }

    @objc func showWindow() {
        if spotifyActive, let spotifyURL {
            NSWorkspace.shared.openApplication(at: spotifyURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setVolume(_ value: Double) {
        volume = (min(max(value, 0), 1) * 100).rounded() / 100
        UserDefaults.standard.set(volume, forKey: "volume")
        web.evaluateJavaScript("window.__stationSetVolume && window.__stationSetVolume(\(volume))")
        if muted {
            toggleMute()
        } else {
            if spotifyActive { spotify("set sound volume to \(spotifyVolume)") }
            refreshIndicators()
        }
    }

    private func refreshIndicators() {
        let level = muted ? "wyciszone" : "\(Int((volume * 100).rounded()))%"
        let station = current.map { stations[$0] }
        let sourceName = spotifyActive ? "Spotify" : station?.name
        window.title = sourceName.map { "\($0) — \(level)" } ?? "Radio — wyłączone"
        NSApp.dockTile.badgeLabel = muted ? "🔇" : nil

        if let sourceName {
            let icon = spotifyActive ? spotifyIcon(side: 18) : station.flatMap { logo($0, side: 18) }
            statusItem.button?.image = muted ? icon.map(crossedOut) : icon
            statusItem.button?.title = muted ? "" : " \(level)"
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "radio", accessibilityDescription: "Radio")
            statusItem.button?.title = ""
        }
        let track = spotifyActive ? spotifyTrack : stationTrack
        let nowPlaying = sourceName.map { [$0, track].compactMap { $0 }.joined(separator: ": ") }
        statusItem.button?.toolTip = "\(nowPlaying ?? "Radio wyłączone")\n⌃⌥M wycisz · ⌃⌥↑ / ⌃⌥↓ głośność"

        slider?.doubleValue = volume * 100
        muteButton?.image = NSImage(systemSymbolName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityDescription: "Wycisz")
        levelLabel?.stringValue = muted ? "—" : level
        muteMenuItem?.title = muted ? "Włącz dźwięk" : "Wycisz"
        for (index, entry) in (stationMenuItems + appStationMenuItems).enumerated() {
            entry.state = index % stations.count == current ? .on : .off
        }
        for (index, entry) in stationMenuItems.enumerated() {
            entry.attributedTitle = menuTitle(logo(stations[index], side: 18), stations[index].name, detail: index == current ? stationTrack : nil)
        }
        for entry in spotifyMenuItems {
            entry.state = spotifyActive ? .on : .off
            if entry.menu === statusItem.menu { entry.attributedTitle = menuTitle(spotifyIcon(side: 18), "Spotify", detail: spotifyActive ? spotifyTrack : nil) }
        }
    }

    @objc func toggleMenuBarIcon() {
        statusItem.isVisible.toggle()
    }

    @objc func toggleDockIcon() {
        let shows = NSApp.activationPolicy() != .regular
        UserDefaults.standard.set(shows, forKey: "showsDockIcon")
        NSApp.setActivationPolicy(shows ? .regular : .accessory)
        if shows { showWindow() }
    }

    @objc func toggleKeepInDock() {
        var tiles = dockTiles()
        if let index = tiles.firstIndex(where: isOwnTile) {
            tiles.remove(at: index)
        } else {
            guard isInstalled() else { return }
            tiles.append([
                "tile-type": "file-tile",
                "tile-data": [
                    "bundle-identifier": Bundle.main.bundleIdentifier ?? "",
                    "file-label": "Radio",
                    "file-data": ["_CFURLString": Bundle.main.bundleURL.absoluteString, "_CFURLStringType": 15],
                ],
            ])
        }
        CFPreferencesSetAppValue("persistent-apps" as CFString, tiles as NSArray, "com.apple.dock" as CFString)
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        // The Dock reads persistent-apps only when it starts.
        Process.launchedProcess(launchPath: "/usr/bin/killall", arguments: ["Dock"])
    }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                guard isInstalled() else { return }
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let showsDockIcon = NSApp.activationPolicy() == .regular
        switch menuItem.action {
        case #selector(toggleMenuBarIcon):
            menuItem.state = statusItem.isVisible ? .on : .off
            return showsDockIcon
        case #selector(toggleDockIcon):
            menuItem.state = showsDockIcon ? .on : .off
            return statusItem.isVisible
        case #selector(toggleKeepInDock):
            menuItem.state = dockTiles().contains(where: isOwnTile) ? .on : .off
        case #selector(toggleLaunchAtLogin):
            menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        default:
            break
        }
        return true
    }

    private func dockTiles() -> [[String: Any]] {
        CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] ?? []
    }

    private func isOwnTile(_ tile: [String: Any]) -> Bool {
        let data = tile["tile-data"] as? [String: Any]
        if let id = data?["bundle-identifier"] as? String { return id == Bundle.main.bundleIdentifier }
        let url = ((data?["file-data"] as? [String: Any])?["_CFURLString"] as? String).flatMap(URL.init(string:))
        return url?.standardizedFileURL.path == Bundle.main.bundleURL.standardizedFileURL.path
    }

    // A quarantined app launched from Downloads runs from a random read-only copy that vanishes on quit.
    private func isInstalled() -> Bool {
        guard Bundle.main.bundlePath.contains("/AppTranslocation/") else { return true }
        let alert = NSAlert()
        alert.messageText = "Najpierw przenieś Radio do folderu Aplikacje"
        alert.informativeText = "Dopóki apka leży w Pobranych, macOS uruchamia ją z tymczasowej kopii. Przeciągnij Radio do Aplikacji i otwórz ponownie."
        alert.runModal()
        return false
    }

    private func settingsItem() -> NSMenuItem {
        let menu = NSMenu(title: "Ustawienia")
        menu.addItem(item("Pokazuj w pasku menu", #selector(toggleMenuBarIcon), ""))
        menu.addItem(item("Pokazuj w Docku", #selector(toggleDockIcon), ""))
        menu.addItem(item("Zachowaj w Docku", #selector(toggleKeepInDock), ""))
        menu.addItem(item("Uruchamiaj przy logowaniu", #selector(toggleLaunchAtLogin), ""))
        let entry = NSMenuItem(title: "Ustawienia", action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }

    private func installScrollVolume() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let button = self.statusItem.button, event.window === button.window else { return event }
            let raw = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            let step = event.hasPreciseScrollingDeltas ? raw * 0.004 : raw * 0.05
            if step != 0 { self.setVolume(self.volume + step) }
            return nil
        }
    }

    private func installHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let delegate = NSApp.delegate as? AppDelegate
            switch hotKeys.first(where: { $0.id == id.id })?.action {
            case "mute": delegate?.toggleMute()
            case "up": delegate?.volumeUp()
            case "down": delegate?.volumeDown()
            default: break
            }
            return noErr
        }, 1, &spec, nil, nil)

        for hotKey in hotKeys {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(hotKey.key), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x5244_494F), id: hotKey.id), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { hotKeyRefs.append(ref) }
        }
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        for (index, station) in stations.enumerated() {
            let entry = item(station.name, #selector(stationChosen(_:)), "")
            entry.tag = index
            entry.attributedTitle = menuTitle(logo(station, side: 18), station.name, detail: nil)
            stationMenuItems.append(entry)
            menu.addItem(entry)
        }
        if spotifyURL != nil {
            let entry = item("Spotify", #selector(playSpotify), "")
            entry.attributedTitle = menuTitle(spotifyIcon(side: 18), "Spotify", detail: nil)
            spotifyMenuItems.append(entry)
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        muteButton = NSButton(image: NSImage(), target: self, action: #selector(toggleMute))
        muteButton.isBordered = false
        muteButton.frame = NSRect(x: 14, y: 8, width: 24, height: 24)

        slider = NSSlider(value: volume * 100, minValue: 0, maxValue: 100, target: self, action: #selector(sliderMoved(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 44, y: 9, width: 200, height: 22)

        levelLabel = NSTextField(labelWithString: "")
        levelLabel.alignment = .right
        levelLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        levelLabel.frame = NSRect(x: 248, y: 11, width: 40, height: 18)

        let row = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        [muteButton, slider, levelLabel].forEach { row.addSubview($0!) }
        let rowItem = NSMenuItem()
        rowItem.view = row
        menu.addItem(rowItem)

        muteMenuItem = item("Wycisz", #selector(toggleMute), "")
        menu.addItem(muteMenuItem)
        menu.addItem(.separator())
        menu.addItem(item("Wyłącz radio", #selector(turnOff), ""))
        menu.addItem(item("Pokaż okno", #selector(showWindow), ""))
        menu.addItem(settingsItem())
        menu.addItem(withTitle: "Zakończ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    // macOS 26 menus drop NSMenuItem.image here, so the logo rides in the title as a text attachment.
    private func menuTitle(_ image: NSImage?, _ name: String, detail: String?) -> NSAttributedString {
        let title = NSMutableAttributedString()
        if let image {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -4, width: 18, height: 18)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: "  "))
        }
        title.append(NSAttributedString(string: name, attributes: [.font: NSFont.menuFont(ofSize: 0)]))
        if let detail, !detail.isEmpty {
            let text = detail.count > 40 ? detail.prefix(39) + "…" : detail
            title.append(NSAttributedString(string: "  \(text)", attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return title
    }

    private func crossedOut(_ icon: NSImage) -> NSImage {
        NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.45)
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 1, y: rect.maxY - 1))
            slash.line(to: NSPoint(x: rect.maxX - 1, y: rect.minY + 1))
            slash.lineCapStyle = .round
            NSGraphicsContext.current?.compositingOperation = .clear
            slash.lineWidth = 4
            slash.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.labelColor.setStroke()
            slash.lineWidth = 1.75
            slash.stroke()
            return true
        }
    }

    private func spotifyIcon(side: CGFloat) -> NSImage? {
        guard let spotifyURL else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: spotifyURL.path)
        icon.size = NSSize(width: side, height: side)
        return icon
    }

    private func logo(_ station: Station, side: CGFloat) -> NSImage? {
        guard let source = NSImage(named: station.logo) else { return nil }
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: side * 0.22, yRadius: side * 0.22).addClip()
            source.draw(in: rect)
            return true
        }
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(settingsItem())
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ukryj Radio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Zakończ Radio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edycja")
        editMenu.addItem(withTitle: "Kopiuj", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Wklej", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Zaznacz wszystko", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let stationItem = NSMenuItem(title: "Stacja", action: nil, keyEquivalent: "")
        let stationMenu = NSMenu(title: "Stacja")
        for (index, station) in stations.enumerated() {
            let entry = item(station.name, #selector(stationChosen(_:)), "\(index + 1)")
            entry.tag = index
            appStationMenuItems.append(entry)
            stationMenu.addItem(entry)
        }
        if spotifyURL != nil {
            let entry = item("Spotify", #selector(playSpotify), "\(stations.count + 1)")
            spotifyMenuItems.append(entry)
            stationMenu.addItem(entry)
        }
        stationMenu.addItem(.separator())
        stationMenu.addItem(item("Wyłącz radio", #selector(turnOff), "0"))
        stationItem.submenu = stationMenu
        main.addItem(stationItem)

        let soundItem = NSMenuItem(title: "Dźwięk", action: nil, keyEquivalent: "")
        let soundMenu = NSMenu(title: "Dźwięk")
        soundMenu.addItem(item("Wycisz / włącz dźwięk", #selector(toggleMute), "m"))
        soundMenu.addItem(item("Głośniej", #selector(volumeUp), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))))
        soundMenu.addItem(item("Ciszej", #selector(volumeDown), String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))))
        soundItem.submenu = soundMenu
        main.addItem(soundItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Okno")
        windowMenu.addItem(withTitle: "Zamknij", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(UserDefaults.standard.object(forKey: "showsDockIcon") as? Bool == false ? .accessory : .regular)
app.run()
