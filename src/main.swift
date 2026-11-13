import AVFoundation
import Carbon
import Cocoa
import ServiceManagement

struct Station {
    let name: String
    let logo: String
    let site: URL
    let stream: URL
    let songURL: URL
    let song: (Data) -> String?
    let showURL: URL
    let show: (Data) -> String?
}

private func nonEmpty(_ values: [Any?]) -> [String] {
    values.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

private func json(_ data: Data) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func text(matching pattern: String, in html: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
          let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
          let range = Range(match.range(at: 1), in: html) else { return nil }
    var text = html[range].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    for (entity, char) in ["&amp;": "&", "&quot;": "\"", "&#039;": "'", "&nbsp;": " "] {
        text = text.replacingOccurrences(of: entity, with: char)
    }
    return nonEmpty([text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)]).first
}

let stations = [
    Station(
        name: "Radio 357",
        logo: "logo-357",
        site: URL(string: "https://radio357.pl")!,
        stream: URL(string: "https://stream.radio357.pl")!,
        songURL: URL(string: "https://stream.radio357.pl/now/playing.json")!,
        // Between songs "s" carries the station's slogan instead of a song.
        song: { data in
            guard let song = nonEmpty([json(data)?["s"]]).first, !song.hasPrefix("Radio 357") else { return nil }
            return song.replacingOccurrences(of: " - ", with: " – ")
        },
        showURL: URL(string: "https://stream.radio357.pl/now/playing.json")!,
        show: { data in
            let show = json(data)?["p"] as? [String: Any]
            let parts = nonEmpty([show?["n"], show?["a"]])
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    ),
    Station(
        name: "Nowy Świat",
        logo: "logo-ns",
        site: URL(string: "https://nowyswiat.online")!,
        stream: URL(string: "https://stream.nowyswiat.online/mp3")!,
        songURL: URL(string: "https://nowyswiat.online/api/oZeta/stat")!,
        // The API names the fields the other way round: "title" holds the artist, "artist" the song; between
        // songs "title" is the station's name.
        song: { data in
            let fields = json(data)?["data"] as? [String: Any]
            let parts = nonEmpty([fields?["title"], fields?["artist"]])
            guard parts.count == 2, parts[0] != "Radio Nowy Świat" else { return nil }
            return parts.joined(separator: " – ")
        },
        // No API names the current show; the homepage's „Teraz na antenie" slide does.
        showURL: URL(string: "https://nowyswiat.online/")!,
        show: { data in
            guard let html = String(data: data, encoding: .utf8),
                  let slide = html.range(of: "rns-slide-schedule-now").map({ String(html[$0.upperBound...].prefix(4000)) }) else { return nil }
            let parts = nonEmpty([
                text(matching: #"rns-slider-text-large"><span>(.*?)</span>"#, in: slide),
                text(matching: #"Zaprasza\S*(.*?)</p>"#, in: slide),
            ])
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    ),
]

private let spotifyTag = -1
private let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client")

private let hotKeys: [(id: UInt32, key: Int, action: String)] = [
    (1, kVK_ANSI_M, "mute"),
    (2, kVK_UpArrow, "up"),
    (3, kVK_DownArrow, "down"),
    (4, kVK_ANSI_L, "find"),
]

// Spotify's volume bar: a thin rounded track, filled up to the value, with no knob.
final class ThinSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        NSColor.labelColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        var filled = bar
        filled.size.width = bar.width * (doubleValue - minValue) / (maxValue - minValue)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate, AVPlayerItemMetadataOutputPushDelegate {
    let player = AVPlayer()
    var streamSong: String?
    var statusItem: NSStatusItem!
    var slider: NSSlider!
    var volumeRow: NSView!
    var openSourceItem: NSMenuItem!
    var buttonImageKey: String?
    var muteButton: NSButton!
    var levelLabel: NSTextField!
    var stationMenuItems: [NSMenuItem] = []
    var appStationMenuItems: [NSMenuItem] = []
    var hotKeyRefs: [EventHotKeyRef] = []
    var current: Int?
    var spotifyActive = false
    var spotifyTrack: String?
    var spotifyAlbum: String?
    var spotifyTrackID: String?
    var stationSongs = [String?](repeating: nil, count: stations.count)
    var stationShows = [String?](repeating: nil, count: stations.count)
    var nowPlayingTicks = 0
    var spotifyMenuItems: [NSMenuItem] = []
    let spotifyQueue = DispatchQueue(label: "spotify")
    var muted = false
    var volume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        player.volume = Float(volume)
        observeStream()

        #if DEBUGHOOK
        installDebugHook()
        #endif
        NSApp.mainMenu = makeMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "radio"
        if NSApp.activationPolicy() != .regular { statusItem.isVisible = true }
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.imageHugsTitle = true
        statusItem.menu = makeStatusMenu()
        statusItem.menu?.delegate = self
        installScrollVolume()
        installHotKeys()
        observeSpotify()
        // A song lasts minutes and a show an hour or more; the Nowy Świat show comes from its 160 KB homepage.
        let timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.nowPlayingTicks += 1
            self.fetchNowPlaying(shows: self.nowPlayingTicks % 20 == 0)
        }
        timer.tolerance = 3
        fetchNowPlaying(shows: true)

        let last = UserDefaults.standard.object(forKey: "station") as? Int ?? 0
        if last == spotifyTag, spotifyURL != nil {
            playSpotify()
        } else {
            play(station: stations.indices.contains(last) ? last : 0)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSource()
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
        return menu
    }

    func play(station index: Int) {
        stopSpotify()
        current = index
        UserDefaults.standard.set(index, forKey: "station")
        startStream()
        refreshIndicators()
    }

    private func streamURL(_ index: Int) -> URL {
        UserDefaults.standard.string(forKey: "streamURL.\(index)").flatMap(URL.init(string:)) ?? stations[index].stream
    }

    private func startStream() {
        guard let current else { return }
        let item = AVPlayerItem(url: streamURL(current))
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        streamSong = nil
        player.replaceCurrentItem(with: item)
        player.play()
    }

    // The stream's own ICY title is live, where the Nowy Świat API can lag by hours; it reads "Artist - Title",
    // "AD" during the Radio 357 start message, and the station's name between songs.
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard current != nil, let title = groups.flatMap(\.items).first(where: { $0.identifier?.rawValue == "icy/StreamTitle" })?.stringValue else { return }
        let plain = { (text: String) in text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
        let filler = title == "AD" || ["Radio 357", "Nowy Swiat"].contains { plain(title).contains(plain($0)) }
        let song = filler ? nil : nonEmpty([title.replacingOccurrences(of: " - ", with: " – ")]).first
        guard song != streamSong else { return }
        streamSong = song
        refreshIndicators()
    }

    // A live stream that drops (network change, sleep) doesn't resume on its own.
    private func observeStream() {
        let center = NotificationCenter.default
        for name in [AVPlayerItem.failedToPlayToEndTimeNotification, AVPlayerItem.playbackStalledNotification, AVPlayerItem.didPlayToEndTimeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, note.object as? AVPlayerItem === self.player.currentItem else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.startStream() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.startStream()
        }
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
        spotify("set sound volume to \(spotifyVolume)\nplay\nreturn album of current track & linefeed & artist of current track & \" – \" & name of current track & linefeed & id of current track") { [weak self] result in
            let lines = result.components(separatedBy: "\n") + ["", ""]
            self?.spotifyAlbum = nonEmpty([lines[0]]).first
            self?.spotifyTrack = nonEmpty([lines[1]]).first
            self?.spotifyTrackID = nonEmpty([lines[2]]).first
            self?.refreshIndicators()
        }
        refreshIndicators()
    }

    private func stopRadio() {
        guard current != nil else { return }
        current = nil
        streamSong = nil
        player.replaceCurrentItem(with: nil)
    }

    private func stopSpotify() {
        guard spotifyActive else { return }
        spotifyActive = false
        spotify("pause")
    }

    private func fetchNowPlaying(shows: Bool) {
        for (index, station) in stations.enumerated() {
            if station.showURL == station.songURL {
                load(station.songURL) { [weak self] data in
                    self?.stationSongs[index] = station.song(data)
                    self?.stationShows[index] = station.show(data)
                }
                continue
            }
            load(station.songURL) { [weak self] data in self?.stationSongs[index] = station.song(data) }
            if shows {
                load(station.showURL) { [weak self] data in self?.stationShows[index] = station.show(data) }
            }
        }
    }

    private func load(_ url: URL, then apply: @escaping (Data) -> Void) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data else { return }
            DispatchQueue.main.async {
                apply(data)
                self?.refreshIndicators()
            }
        }.resume()
    }

    private var spotifyVolume: Int { muted ? 0 : Int((volume * 100).rounded()) }

    // Spotify broadcasts every play/pause/track change, so playback started in Spotify itself takes over from the radio.
    private func observeSpotify() {
        #if DEBUGHOOK
        // Lets a measurement run play a station without reacting to, and muting, the Spotify someone is listening to.
        if ProcessInfo.processInfo.environment["RADIO_NO_SPOTIFY"] != nil { return }
        #endif
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            guard let self, let info = note.userInfo else { return }
            if let name = info["Name"] as? String {
                self.spotifyTrack = nonEmpty([info["Artist"], name]).joined(separator: " – ")
                self.spotifyAlbum = nonEmpty([info["Album"]]).first
                self.spotifyTrackID = nonEmpty([info["Track ID"]]).first
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
        player.isMuted = muted
        if spotifyActive { spotify("set sound volume to \(spotifyVolume)") }
        refreshIndicators()
    }

    // The Web API that could like a track directly is capped at five allowlisted accounts, so this opens the
    // track (or a search for the radio's song) in Spotify, where its ⊕ button saves it.
    private var spotifyTarget: URL? {
        if spotifyActive { return spotifyTrackID.flatMap(URL.init(string:)) }
        guard let current, let song = songs[current],
              let query = song.replacingOccurrences(of: " – ", with: " ").addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "spotify:search:\(query)")
    }

    @objc func findInSpotify() {
        guard spotifyURL != nil, let spotifyTarget else { return NSSound.beep() }
        NSWorkspace.shared.open(spotifyTarget)
    }

    @objc func volumeUp() { setVolume(volume + 0.1) }
    @objc func volumeDown() { setVolume(volume - 0.1) }
    @objc func sliderMoved(_ sender: NSSlider) { setVolume(sender.doubleValue / 100) }

    @objc func openSource() {
        if spotifyActive, let spotifyURL {
            NSWorkspace.shared.openApplication(at: spotifyURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(stations[current ?? 0].site)
        }
    }

    @objc func editStreamURL(_ sender: NSMenuItem) {
        let key = "streamURL.\(sender.tag)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = UserDefaults.standard.string(forKey: key) ?? ""
        field.placeholderString = stations[sender.tag].stream.absoluteString
        let alert = NSAlert()
        alert.messageText = "\(stations[sender.tag].name): własny adres strumienia"
        alert.informativeText = "Np. osobisty link patrona. Puste pole przywraca publiczny strumień."
        alert.accessoryView = field
        alert.addButton(withTitle: "Zapisz")
        alert.addButton(withTitle: "Anuluj")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(URL(string: text)?.scheme == nil ? nil : text, forKey: key)
        if current == sender.tag { startStream() }
    }

    private func setVolume(_ value: Double) {
        volume = (min(max(value, 0), 1) * 100).rounded() / 100
        UserDefaults.standard.set(volume, forKey: "volume")
        player.volume = Float(volume)
        if muted {
            toggleMute()
        } else {
            if spotifyActive { spotify("set sound volume to \(spotifyVolume)") }
            refreshIndicators()
        }
    }

    private var songs: [String?] {
        stationSongs.indices.map { $0 == current ? streamSong ?? stationSongs[$0] : stationSongs[$0] }
    }

    func refreshIndicators() {
        let level = muted ? "wyciszone" : "\(Int((volume * 100).rounded()))%"
        let station = current.map { stations[$0] }
        let sourceName = spotifyActive ? "Spotify" : station?.name
        NSApp.dockTile.badgeLabel = muted ? "🔇" : nil

        let details = spotifyActive ? [spotifyAlbum, spotifyTrack] : current.map { [stationShows[$0], songs[$0]] } ?? []
        // Every assignment redraws the menu-bar item, even with an equal value, so only changes are written.
        let imageKey = "\(sourceName ?? "-") \(muted)"
        if imageKey != buttonImageKey {
            buttonImageKey = imageKey
            let icon = spotifyActive ? spotifyIcon(side: 18) : station.flatMap { logo($0, side: 18) }
            statusItem.button?.image = sourceName == nil ? NSImage(systemSymbolName: "radio", accessibilityDescription: "Radio") : muted ? icon.map(crossedOut) : icon
        }
        // An item too wide for the space left of the notch disappears from the menu bar altogether.
        let playing = showsNowPlaying ? (details.last ?? nil ?? details.first ?? nil).map { $0.count > 40 ? $0.prefix(39) + "…" : $0 } : nil
        let title = sourceName == nil ? "" : [muted ? nil : level, playing].compactMap { $0 }.joined(separator: " · ")
        if statusItem.button?.title != title { statusItem.button?.title = title }
        let nowPlaying = sourceName.map { ([$0] + details.compactMap { $0 }).joined(separator: "\n") }
        let toolTip = "\(nowPlaying ?? "Radio wyłączone")\n⌃⌥M wycisz · ⌃⌥↑ / ⌃⌥↓ głośność · ⌃⌥L otwórz w Spotify"
        if statusItem.button?.toolTip != toolTip { statusItem.button?.toolTip = toolTip }

        slider?.doubleValue = volume * 100
        let speaker = muted ? "speaker.slash" : volume == 0 ? "speaker" : "speaker.wave.\(min(Int(volume * 3) + 1, 3))"
        muteButton?.image = NSImage(systemSymbolName: speaker, accessibilityDescription: "Wycisz")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        levelLabel?.stringValue = muted ? "—" : level
        openSourceItem?.title = spotifyActive ? "Otwórz Spotify" : "Otwórz stronę stacji"
        for (index, entry) in (stationMenuItems + appStationMenuItems).enumerated() {
            entry.state = index % stations.count == current ? .on : .off
        }
        for (index, entry) in stationMenuItems.enumerated() {
            entry.attributedTitle = menuTitle(logo(stations[index], side: 18), stations[index].name, show: stationShows[index], song: songs[index])
            entry.onStateImage = checkmark(for: entry.attributedTitle)
        }
        for entry in spotifyMenuItems {
            entry.state = spotifyActive ? .on : .off
            if entry.menu === statusItem.menu {
                entry.attributedTitle = menuTitle(spotifyIcon(side: 18), "Spotify", show: spotifyAlbum, song: spotifyTrack)
                entry.onStateImage = checkmark(for: entry.attributedTitle)
            }
        }
    }

    @objc func toggleMenuBarIcon() {
        statusItem.isVisible.toggle()
    }

    private var showsNowPlaying: Bool { UserDefaults.standard.object(forKey: "showsNowPlaying") as? Bool ?? true }

    @objc func toggleNowPlaying() {
        UserDefaults.standard.set(!showsNowPlaying, forKey: "showsNowPlaying")
        refreshIndicators()
    }

    @objc func toggleDockIcon() {
        let shows = NSApp.activationPolicy() != .regular
        UserDefaults.standard.set(shows, forKey: "showsDockIcon")
        NSApp.setActivationPolicy(shows ? .regular : .accessory)
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
        case #selector(toggleNowPlaying):
            menuItem.state = showsNowPlaying ? .on : .off
        case #selector(toggleDockIcon):
            menuItem.state = showsDockIcon ? .on : .off
            return statusItem.isVisible
        case #selector(toggleKeepInDock):
            menuItem.state = dockTiles().contains(where: isOwnTile) ? .on : .off
        case #selector(toggleLaunchAtLogin):
            menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        case #selector(findInSpotify):
            return spotifyTarget != nil
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
        menu.addItem(item("Pokazuj, co leci, w pasku menu", #selector(toggleNowPlaying), ""))
        menu.addItem(item("Pokazuj w Docku", #selector(toggleDockIcon), ""))
        menu.addItem(item("Zachowaj w Docku", #selector(toggleKeepInDock), ""))
        menu.addItem(item("Uruchamiaj przy logowaniu", #selector(toggleLaunchAtLogin), ""))
        menu.addItem(.separator())
        for (index, station) in stations.enumerated() {
            let entry = item("\(station.name): własny adres strumienia…", #selector(editStreamURL(_:)), "")
            entry.tag = index
            menu.addItem(entry)
        }
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
            case "find": delegate?.findInSpotify()
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

    // A menu never resizes an item's view, so the volume row is stretched to whatever the titles make the menu.
    func menuWillOpen(_ menu: NSMenu) {
        volumeRow.setFrameSize(NSSize(width: 300, height: volumeRow.frame.height))
        volumeRow.setFrameSize(NSSize(width: max(menu.size.width, 300), height: volumeRow.frame.height))
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        for (index, station) in stations.enumerated() {
            let entry = item(station.name, #selector(stationChosen(_:)), "")
            entry.tag = index
            entry.attributedTitle = menuTitle(logo(station, side: 18), station.name)
            stationMenuItems.append(entry)
            menu.addItem(entry)
        }
        if spotifyURL != nil {
            let entry = item("Spotify", #selector(playSpotify), "")
            entry.attributedTitle = menuTitle(spotifyIcon(side: 18), "Spotify")
            spotifyMenuItems.append(entry)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        if spotifyURL != nil {
            let find = item("Otwórz w Spotify", #selector(findInSpotify), "l")
            let symbol = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.labelColor]))
            find.attributedTitle = menuTitle(symbol, "Otwórz w Spotify")
            find.keyEquivalentModifierMask = [.control, .option]
            menu.addItem(find)
        }

        muteButton = NSButton(image: NSImage(), target: self, action: #selector(toggleMute))
        muteButton.isBordered = false
        // A menu's window never becomes key, so an untinted button draws its symbol in the inactive grey.
        muteButton.contentTintColor = .labelColor
        // x 31 and 56 are where macOS 26 puts the rows' logos and their text.
        muteButton.frame = NSRect(x: 31, y: 8, width: 18, height: 24)

        slider = NSSlider()
        slider.cell = ThinSliderCell()
        slider.minValue = 0
        slider.maxValue = 100
        slider.doubleValue = volume * 100
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isContinuous = true
        slider.frame = NSRect(x: 56, y: 9, width: 186, height: 22)
        slider.autoresizingMask = .width

        levelLabel = NSTextField(labelWithString: "")
        levelLabel.alignment = .right
        levelLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        levelLabel.frame = NSRect(x: 248, y: 11, width: 40, height: 18)
        levelLabel.autoresizingMask = .minXMargin

        let row = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        volumeRow = row
        [muteButton, slider, levelLabel].forEach { row.addSubview($0!) }
        let rowItem = NSMenuItem()
        rowItem.view = row
        menu.addItem(rowItem)

        menu.addItem(.separator())
        openSourceItem = item("Otwórz stronę stacji", #selector(openSource), "")
        menu.addItem(openSourceItem)
        menu.addItem(settingsItem())
        menu.addItem(withTitle: "Zakończ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    // macOS 26 menus drop NSMenuItem.image here, so the logo rides in the title as a text attachment.
    private func menuTitle(_ image: NSImage?, _ name: String, show: String? = nil, song: String? = nil) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString()
        if let image {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -4, width: 18, height: 18)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        }
        // A line separator, unlike a newline, keeps the paragraph so headIndent lines every line up under the first.
        let lines = [show ?? name, song.map { "♪ \($0)" }].compactMap { $0 }.flatMap { wrapped($0, font) }
        title.append(NSAttributedString(string: lines.joined(separator: "\u{2028}"), attributes: [.font: font]))
        let style = NSMutableParagraphStyle()
        style.headIndent = image == nil ? 0 : 18 + ("  " as NSString).size(withAttributes: [.font: font]).width
        title.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: title.length))
        return title
    }

    // A menu is as wide as its widest title and never wraps one, so long lines are broken here.
    private func wrapped(_ text: String, _ font: NSFont, maxWidth: CGFloat = 340) -> [String] {
        var lines: [String] = []
        for word in text.split(separator: " ").map(String.init) {
            if let last = lines.last, ("\(last) \(word)" as NSString).size(withAttributes: [.font: font]).width <= maxWidth {
                lines[lines.count - 1] = "\(last) \(word)"
            } else {
                lines.append(word)
            }
        }
        return lines
    }

    // The menu centres the state image on the row, which on a multi-line row puts the check between the lines.
    private func checkmark(for title: NSAttributedString?) -> NSImage? {
        guard let title, let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .semibold)) else { return nil }
        let height = ceil(title.boundingRect(with: NSSize(width: 2000, height: 400), options: .usesLineFragmentOrigin).height)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: NSFont.menuFont(ofSize: 0))
        let image = NSImage(size: NSSize(width: check.size.width, height: max(height, lineHeight)), flipped: true) { _ in
            check.draw(in: NSRect(x: 0, y: (lineHeight - check.size.height) / 2, width: check.size.width, height: check.size.height))
            return true
        }
        image.isTemplate = true
        return image
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
        stationItem.submenu = stationMenu
        main.addItem(stationItem)

        let soundItem = NSMenuItem(title: "Dźwięk", action: nil, keyEquivalent: "")
        let soundMenu = NSMenu(title: "Dźwięk")
        soundMenu.addItem(item("Wycisz / włącz dźwięk", #selector(toggleMute), "m"))
        soundMenu.addItem(item("Głośniej", #selector(volumeUp), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))))
        soundMenu.addItem(item("Ciszej", #selector(volumeDown), String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))))
        soundItem.submenu = soundMenu
        main.addItem(soundItem)

        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(UserDefaults.standard.object(forKey: "showsDockIcon") as? Bool == false ? .accessory : .regular)
app.run()
