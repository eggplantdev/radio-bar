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
    // nil: the show comes from the song's own response.
    let showURL: URL?
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
        showURL: nil,
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

private let hotKeys: [(id: UInt32, key: Int, action: Selector)] = [
    (1, kVK_ANSI_M, #selector(AppDelegate.toggleMute)),
    (2, kVK_UpArrow, #selector(AppDelegate.volumeUp)),
    (3, kVK_DownArrow, #selector(AppDelegate.volumeDown)),
    (4, kVK_ANSI_L, #selector(AppDelegate.findInSpotify)),
]

private let iconSide: CGFloat = 18
private let volumeRowWidth: CGFloat = 300
private let session = URLSession(configuration: .ephemeral)

// Built from an ASCII set: on macOS 13 URL(string:) returns nil for an unescaped „ą”.
private let queryCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

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
    var youTubeItem: NSMenuItem!
    var buttonImageKey: String?
    var muteButton: NSButton!
    var levelLabel: NSTextField!
    var stationMenuItems: [NSMenuItem] = []
    var appStationMenuItems: [NSMenuItem] = []
    var rowsKey: String?
    var retryDelay: TimeInterval = 3
    var statusObservation: NSKeyValueObservation?
    var scrollRemainder = 0.0
    var spotifyVolumeInFlight = false
    var spotifyVolumePending = false
    var permissionAlertShown = false
    lazy var logos = stations.map(logo)
    lazy var spotifyImage = spotifyURL.map { url -> NSImage in
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: iconSide, height: iconSide)
        return icon
    }
    var current: Int?
    var spotifyActive = false
    var spotifyTrack: String?
    var spotifyAlbum: String?
    var spotifyTrackID: String?
    var stationSongs = [String?](repeating: nil, count: stations.count)
    var stationShows = [String?](repeating: nil, count: stations.count)
    var spotifyMenuItems: [NSMenuItem] = []
    let spotifyQueue = DispatchQueue(label: "spotify")
    var muted = false
    var volume = UserDefaults.standard.double(forKey: "volume")

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
        var ticks = 0
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            ticks += 1
            self?.fetchNowPlaying(shows: ticks % 20 == 0)
        }
        timer.tolerance = 3
        // In the default mode only, the timer would stop while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        fetchNowPlaying(shows: true)

        let last = UserDefaults.standard.integer(forKey: "station")
        if last == spotifyTag, spotifyURL != nil {
            playSpotify()
        } else {
            play(station: stations.indices.contains(last) ? last : 0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard spotifyActive, muted || spotifyVolumeInFlight else { return }
        let source = Self.ifRunning("pause\nset sound volume to \(percent)")
        spotifyQueue.sync { _ = NSAppleScript(source: source)?.executeAndReturnError(nil) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSource()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for entry in sourceItems(numbered: false) {
            entry.state = isPlaying(entry) ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item(muted ? "Włącz dźwięk" : "Wycisz", #selector(toggleMute)))
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
        let output = AVPlayerItemMetadataOutput(identifiers: [AVMetadataIdentifier.icyMetadataStreamTitle.rawValue])
        output.setDelegate(self, queue: .main)
        item.add(output)
        // A stream that can't load (no network yet after wake or login, a bad custom URL) fails without any notification.
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .readyToPlay { self?.retryDelay = 3 }
                if item.status == .failed { self?.retry(item) }
            }
        }
        streamSong = nil
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func retry(_ item: AVPlayerItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self, item === self.player.currentItem else { return }
            self.startStream()
            self.retryDelay = min(self.retryDelay * 2, 60)
        }
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard let current, player.currentItem?.outputs.contains(output) == true,
              let title = groups.flatMap(\.items).first?.stringValue else { return }
        let plain = { (text: String) in text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
        let filler = title == "AD" || plain(title).contains(plain(stations[current].name))
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
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.retry(item)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.startStream()
        }
    }

    @objc func stationChosen(_ sender: NSMenuItem) {
        play(station: sender.tag)
    }

    private func adoptSpotify() {
        stopRadio()
        spotifyActive = true
        UserDefaults.standard.set(spotifyTag, forKey: "station")
    }

    @objc func playSpotify() {
        adoptSpotify()
        spotify("set sound volume to \(spotifyVolume)\nplay\nreturn album of current track & linefeed & artist of current track & \" – \" & name of current track & linefeed & id of current track") { [weak self] result in
            guard let result else {
                self?.spotifyActive = false
                self?.refreshIndicators()
                return
            }
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
        // Mute is Spotify's volume 0, which would otherwise outlive Radio switching away from it.
        spotifyIfRunning("pause\nset sound volume to \(percent)")
    }

    private func fetchNowPlaying(shows: Bool) {
        for (index, station) in stations.enumerated() {
            load(station.songURL) { [weak self] data in
                self?.stationSongs[index] = station.song(data)
                if station.showURL == nil { self?.stationShows[index] = station.show(data) }
            }
            if shows, let showURL = station.showURL {
                load(showURL) { [weak self] data in self?.stationShows[index] = station.show(data) }
            }
        }
    }

    private func load(_ url: URL, then apply: @escaping (Data) -> Void) {
        // The Nowy Świat API sits behind a CDN that serves the same song for hours unless the URL is new.
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        session.dataTask(with: components.url!) { [weak self] data, _, _ in
            guard let data else { return }
            DispatchQueue.main.async {
                apply(data)
                self?.refreshIndicators()
            }
        }.resume()
    }

    private var percent: Int { Int((volume * 100).rounded()) }
    private var spotifyVolume: Int { muted ? 0 : percent }

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
                self.adoptSpotify()
                self.syncSpotifyVolume()
            }
            self.refreshIndicators()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.spotify.client" else { return }
            self.spotifyActive = false
            (self.spotifyTrack, self.spotifyAlbum, self.spotifyTrackID) = (nil, nil, nil)
            self.refreshIndicators()
        }
    }

    // A plain `tell` launches Spotify, which a pause or a volume change must not do.
    private func spotifyIfRunning(_ commands: String, then: (() -> Void)? = nil) {
        spotify(Self.ifRunning(commands), tell: false) { _ in then?() }
    }

    private static func ifRunning(_ commands: String) -> String {
        "if application id \"com.spotify.client\" is running then\ntell application id \"com.spotify.client\"\n\(commands)\nend tell\nend if"
    }

    private func spotify(_ commands: String, tell: Bool = true, then: ((String?) -> Void)? = nil) {
        let source = tell ? "tell application id \"com.spotify.client\"\n\(commands)\nend tell" : commands
        spotifyQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let denied = error?[NSAppleScript.errorNumber] as? Int == -1743
            DispatchQueue.main.async {
                then?(result?.stringValue)
                if denied { self.permissionDenied() }
            }
        }
    }

    private func permissionDenied() {
        guard !permissionAlertShown else { return }
        permissionAlertShown = true
        let alert = NSAlert()
        alert.messageText = "Radio nie ma zgody na sterowanie Spotify"
        alert.informativeText = "Włącz Spotify przy Radio w Ustawieniach systemowych → Prywatność i ochrona → Automatyzacja."
        alert.addButton(withTitle: "Otwórz Ustawienia")
        alert.addButton(withTitle: "Anuluj")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }

    // A scroll sends dozens of changes a second; each script takes tens of ms, so only the latest one is sent.
    private func syncSpotifyVolume() {
        guard spotifyActive else { return }
        guard !spotifyVolumeInFlight else { return spotifyVolumePending = true }
        spotifyVolumeInFlight = true
        spotifyIfRunning("set sound volume to \(spotifyVolume)") { [weak self] in
            guard let self else { return }
            self.spotifyVolumeInFlight = false
            if self.spotifyVolumePending {
                self.spotifyVolumePending = false
                self.syncSpotifyVolume()
            }
        }
    }

    @objc func toggleMute() {
        muted.toggle()
        player.isMuted = muted
        syncSpotifyVolume()
        refreshIndicators()
    }

    private var searchText: String? {
        (spotifyActive ? spotifyTrack : current.flatMap { songs[$0] })?
            .replacingOccurrences(of: " – ", with: " ").addingPercentEncoding(withAllowedCharacters: queryCharacters)
    }

    private var spotifyTarget: URL? {
        if spotifyActive { return spotifyTrackID.flatMap(URL.init(string:)) }
        return searchText.flatMap { URL(string: "spotify:search:\($0)") }
    }

    @objc func findInSpotify() {
        guard spotifyURL != nil, let spotifyTarget else { return NSSound.beep() }
        NSWorkspace.shared.open(spotifyTarget)
    }

    var youTubeTarget: URL? {
        searchText.flatMap { URL(string: "https://www.youtube.com/results?search_query=\($0)") }
    }

    @objc func findOnYouTube() {
        guard let youTubeTarget else { return NSSound.beep() }
        NSWorkspace.shared.open(youTubeTarget)
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
        let hint = "Np. osobisty link patrona. Puste pole przywraca publiczny strumień."
        var info = hint
        while true {
            let alert = NSAlert()
            alert.messageText = "\(stations[sender.tag].name): własny adres strumienia"
            alert.informativeText = info
            alert.accessoryView = field
            alert.addButton(withTitle: "Zapisz")
            alert.addButton(withTitle: "Anuluj")
            alert.window.initialFirstResponder = field
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            let url = URL(string: text)
            guard text.isEmpty || (["http", "https"].contains(url?.scheme?.lowercased()) && url?.host != nil) else {
                info = "To nie jest adres strumienia — musi zaczynać się od https:// albo http://.\n\(hint)"
                continue
            }
            UserDefaults.standard.set(text.isEmpty ? nil : text, forKey: key)
            if current == sender.tag { startStream() }
            return
        }
    }

    private func setVolume(_ value: Double) {
        let rounded = (min(max(value, 0), 1) * 100).rounded() / 100
        guard rounded != volume || muted else { return }
        volume = rounded
        UserDefaults.standard.set(volume, forKey: "volume")
        player.volume = Float(volume)
        muted = false
        player.isMuted = false
        syncSpotifyVolume()
        refreshIndicators()
    }

    private var songs: [String?] {
        stationSongs.indices.map { $0 == current ? streamSong ?? stationSongs[$0] : stationSongs[$0] }
    }

    func refreshIndicators() {
        let level = muted ? "wyciszone" : "\(percent)%"
        let sourceName = spotifyActive ? "Spotify" : current.map { stations[$0].name }
        let badge = muted ? "🔇" : nil
        if NSApp.dockTile.badgeLabel != badge { NSApp.dockTile.badgeLabel = badge }

        let details = (spotifyActive ? [spotifyAlbum, spotifyTrack] : current.map { [stationShows[$0], songs[$0]] } ?? []).compactMap { $0 }
        // Every assignment redraws the menu-bar item, even with an equal value.
        let imageKey = "\(sourceName ?? "-") \(muted)"
        if imageKey != buttonImageKey {
            buttonImageKey = imageKey
            let icon = spotifyActive ? spotifyImage : current.flatMap { logos[$0] }
            statusItem.button?.image = sourceName == nil ? NSImage(systemSymbolName: "radio", accessibilityDescription: "Radio") : muted ? icon.map(crossedOut) : icon
        }
        // An item too wide for the space left of the notch disappears from the menu bar altogether.
        let playing = showsNowPlaying ? details.last.map { $0.count > 40 ? $0.prefix(39) + "…" : $0 } : nil
        let title = sourceName == nil ? "" : [muted ? nil : level, playing].compactMap { $0 }.joined(separator: " · ")
        if statusItem.button?.title != title { statusItem.button?.title = title }
        let nowPlaying = sourceName.map { ([$0] + details).joined(separator: "\n") }
        let toolTip = "\(nowPlaying ?? "Radio wyłączone")\n⌃⌥M wycisz · ⌃⌥↑ / ⌃⌥↓ głośność · ⌃⌥L otwórz w Spotify"
        if statusItem.button?.toolTip != toolTip { statusItem.button?.toolTip = toolTip }

        slider?.doubleValue = volume * 100
        let speaker = muted ? "speaker.slash" : volume == 0 ? "speaker" : "speaker.wave.\(min(Int(volume * 3) + 1, 3))"
        muteButton?.image = NSImage(systemSymbolName: speaker, accessibilityDescription: "Wycisz")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        levelLabel?.stringValue = muted ? "—" : level
        openSourceItem?.title = spotifyActive ? "Otwórz Spotify" : "Otwórz stronę stacji"
        for entry in stationMenuItems + appStationMenuItems + spotifyMenuItems {
            entry.state = isPlaying(entry) ? .on : .off
        }

        // Volume changes arrive dozens of times a second and change nothing in the rows.
        let rows = "\(stationShows) \(songs) \(spotifyAlbum ?? "") \(spotifyTrack ?? "")"
        guard rows != rowsKey else { return }
        rowsKey = rows
        for (index, entry) in stationMenuItems.enumerated() {
            decorate(entry, logos[index], stations[index].name, show: stationShows[index], song: songs[index])
        }
        if let entry = spotifyMenuItems.first(where: { $0.menu === statusItem.menu }) {
            decorate(entry, spotifyImage, "Spotify", show: spotifyAlbum, song: spotifyTrack)
        }
    }

    private func decorate(_ entry: NSMenuItem, _ image: NSImage?, _ name: String, show: String?, song: String?) {
        let title = menuTitle(image, name, show: show, song: song)
        entry.attributedTitle = title
        entry.onStateImage = checkmark(for: title)
    }

    private func isPlaying(_ entry: NSMenuItem) -> Bool {
        entry.action == #selector(playSpotify) ? spotifyActive : entry.tag == current
    }

    @objc func toggleMenuBarIcon() {
        statusItem.isVisible.toggle()
    }

    private var showsNowPlaying: Bool { UserDefaults.standard.bool(forKey: "showsNowPlaying") }

    @objc func toggleNowPlaying() {
        UserDefaults.standard.set(!showsNowPlaying, forKey: "showsNowPlaying")
        refreshIndicators()
    }

    private var showsYouTubeSearch: Bool { UserDefaults.standard.bool(forKey: "showsYouTubeSearch") }

    @objc func toggleYouTubeSearch() {
        UserDefaults.standard.set(!showsYouTubeSearch, forKey: "showsYouTubeSearch")
        youTubeItem.isHidden = !showsYouTubeSearch
    }

    @objc func toggleDockIcon() {
        let shows = NSApp.activationPolicy() != .regular
        UserDefaults.standard.set(shows, forKey: "showsDockIcon")
        NSApp.setActivationPolicy(shows ? .regular : .accessory)
    }

    @objc func toggleKeepInDock() {
        guard var tiles = dockTiles() else { return NSSound.beep() }
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
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
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
        case #selector(toggleYouTubeSearch):
            menuItem.state = showsYouTubeSearch ? .on : .off
        case #selector(toggleDockIcon):
            menuItem.state = showsDockIcon ? .on : .off
            return statusItem.isVisible
        case #selector(toggleKeepInDock):
            menuItem.state = dockTiles()?.contains(where: isOwnTile) == true ? .on : .off
        case #selector(toggleLaunchAtLogin):
            menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        case #selector(findInSpotify):
            return spotifyTarget != nil
        case #selector(findOnYouTube):
            return youTubeTarget != nil
        default:
            break
        }
        return true
    }

    // nil when unreadable: writing a list built from nothing would wipe the user's Dock.
    private func dockTiles() -> [[String: Any]]? {
        CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]]
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
        menu.addItem(item("Pokazuj w pasku menu", #selector(toggleMenuBarIcon)))
        menu.addItem(item("Pokazuj, co leci, w pasku menu", #selector(toggleNowPlaying)))
        menu.addItem(item("Pokazuj „Szukaj na YouTube”", #selector(toggleYouTubeSearch)))
        menu.addItem(item("Pokazuj w Docku", #selector(toggleDockIcon)))
        menu.addItem(item("Zachowaj w Docku", #selector(toggleKeepInDock)))
        menu.addItem(item("Uruchamiaj przy logowaniu", #selector(toggleLaunchAtLogin)))
        menu.addItem(.separator())
        for (index, station) in stations.enumerated() {
            let entry = item("\(station.name): własny adres strumienia…", #selector(editStreamURL(_:)))
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
            // A slow trackpad step is below the 1% the volume is rounded to, so steps add up until they reach it.
            self.scrollRemainder += event.hasPreciseScrollingDeltas ? raw * 0.004 : raw * 0.05
            guard abs(self.scrollRemainder) >= 0.01 else { return nil }
            self.setVolume(self.volume + self.scrollRemainder)
            self.scrollRemainder = 0
            return nil
        }
    }

    private func installHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let action = hotKeys.first(where: { $0.id == id.id })?.action { NSApp.sendAction(action, to: NSApp.delegate, from: nil) }
            return noErr
        }, 1, &spec, nil, nil)

        for hotKey in hotKeys {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(hotKey.key), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x5244_494F), id: hotKey.id), GetApplicationEventTarget(), 0, &ref)
        }
    }

    // A menu never resizes an item's view.
    func menuWillOpen(_ menu: NSMenu) {
        // The row's own width counts towards menu.size, so without the reset the menu never shrinks back.
        volumeRow.setFrameSize(NSSize(width: volumeRowWidth, height: volumeRow.frame.height))
        volumeRow.setFrameSize(NSSize(width: max(menu.size.width, volumeRowWidth), height: volumeRow.frame.height))
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        for entry in sourceItems(numbered: false) {
            if entry.action == #selector(playSpotify) { spotifyMenuItems.append(entry) } else { stationMenuItems.append(entry) }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        if spotifyURL != nil {
            let find = symbolItem("Otwórz w Spotify", "arrow.up.forward.app", #selector(findInSpotify), "l")
            find.keyEquivalentModifierMask = [.control, .option]
            menu.addItem(find)
        }
        youTubeItem = symbolItem("Szukaj na YouTube", "play.rectangle", #selector(findOnYouTube))
        youTubeItem.isHidden = !showsYouTubeSearch
        menu.addItem(youTubeItem)

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

        let row = NSView(frame: NSRect(x: 0, y: 0, width: volumeRowWidth, height: 40))
        volumeRow = row
        [muteButton, slider, levelLabel].forEach { row.addSubview($0!) }
        let rowItem = NSMenuItem()
        rowItem.view = row
        menu.addItem(rowItem)

        menu.addItem(.separator())
        openSourceItem = item("Otwórz stronę stacji", #selector(openSource))
        menu.addItem(openSourceItem)
        menu.addItem(settingsItem())
        menu.addItem(withTitle: "Zakończ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    // macOS 26 menus drop NSMenuItem.image here.
    private func menuTitle(_ image: NSImage?, _ name: String, show: String? = nil, song: String? = nil) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString()
        if let image {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -4, width: iconSide, height: iconSide)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        }
        // A line separator, unlike a newline, keeps the paragraph so headIndent lines every line up under the first.
        let lines = [show ?? name, song.map { "♪ \($0)" }].compactMap { $0 }.flatMap { wrapped($0, font) }
        title.append(NSAttributedString(string: lines.joined(separator: "\u{2028}"), attributes: [.font: font]))
        let style = NSMutableParagraphStyle()
        style.headIndent = image == nil ? 0 : iconSide + ("  " as NSString).size(withAttributes: [.font: font]).width
        title.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: title.length))
        return title
    }

    // A menu is as wide as its widest title and never wraps one.
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
    private func checkmark(for title: NSAttributedString) -> NSImage? {
        guard let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
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

    private func logo(_ station: Station) -> NSImage? {
        guard let source = NSImage(named: station.logo) else { return nil }
        return NSImage(size: NSSize(width: iconSide, height: iconSide), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: iconSide * 0.22, yRadius: iconSide * 0.22).addClip()
            source.draw(in: rect)
            return true
        }
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func symbolItem(_ title: String, _ symbol: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let entry = item(title, action, key)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.labelColor]))
        entry.attributedTitle = menuTitle(image, title)
        return entry
    }

    private func sourceItems(numbered: Bool) -> [NSMenuItem] {
        var entries = stations.enumerated().map { index, station in
            let entry = item(station.name, #selector(stationChosen(_:)), numbered ? "\(index + 1)" : "")
            entry.tag = index
            return entry
        }
        if spotifyURL != nil { entries.append(item("Spotify", #selector(playSpotify), numbered ? "\(stations.count + 1)" : "")) }
        return entries
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
        editMenu.addItem(withTitle: "Cofnij", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Ponów", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Wytnij", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopiuj", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Wklej", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Zaznacz wszystko", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let stationItem = NSMenuItem(title: "Stacja", action: nil, keyEquivalent: "")
        let stationMenu = NSMenu(title: "Stacja")
        for entry in sourceItems(numbered: true) {
            if entry.action == #selector(playSpotify) { spotifyMenuItems.append(entry) } else { appStationMenuItems.append(entry) }
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

UserDefaults.standard.register(defaults: ["volume": 1.0, "showsNowPlaying": true, "showsDockIcon": true])
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(UserDefaults.standard.bool(forKey: "showsDockIcon") ? .regular : .accessory)
app.run()
