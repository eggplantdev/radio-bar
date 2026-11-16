import AVFoundation
import Carbon
import Cocoa
import ServiceManagement

private let spotifyTag = -1
let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client")

let listensToSpotify: Bool = {
    #if DEBUGHOOK
    // Lets a measurement run play a station without reacting to, and muting, the Spotify someone is listening to.
    if ProcessInfo.processInfo.environment["RADIO_NO_SPOTIFY"] != nil { return false }
    #endif
    return spotifyURL != nil
}()

enum Source: Equatable {
    case station(Int)
    case spotify
}

private let hotKeys: [(id: UInt32, key: Int, action: Selector)] = [
    (1, kVK_ANSI_M, #selector(AppDelegate.toggleMute)),
    (2, kVK_UpArrow, #selector(AppDelegate.volumeUp)),
    (3, kVK_DownArrow, #selector(AppDelegate.volumeDown)),
    (4, kVK_ANSI_L, #selector(AppDelegate.findInSpotify)),
]

let iconSide: CGFloat = 18
let volumeRowWidth: CGFloat = 340
private let session = URLSession(configuration: .ephemeral)

// Built from an ASCII set: on macOS 13 URL(string:) returns nil for an unescaped „ą”.
private let queryCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate, AVPlayerItemMetadataOutputPushDelegate {
    let player = AVPlayer()
    var streamSong: String?
    var statusItem: NSStatusItem!
    var slider: RowSlider!
    var volumeRow: NSView!
    var openSourceItem: NSMenuItem!
    var youTubeItem: NSMenuItem!
    var buttonImageKey: String?
    var statusMenuOpen = false
    var muteButton: NSButton!
    var previousButton: TransportButton!
    var playPauseButton: TransportButton!
    var nextButton: TransportButton!
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
    var source: Source? {
        didSet { paused = false }
    }
    var current: Int? {
        if case let .station(index) = source { return index }
        return nil
    }
    var spotifyActive: Bool { source == .spotify }
    var spotifyTrack: String?
    var spotifyAlbum: String?
    var spotifyTrackID: String?
    var paused = false
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
        // The menu bar moves to whichever display is active, and only a notched one needs the short title.
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: statusItem.button?.window, queue: .main) { [weak self] _ in
            self?.refreshIndicators()
        }
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
        spotifyQueue.async { [weak self] in
            // Spotify already playing wins over the saved station, as it does whenever play is pressed in Spotify.
            let spotify = (last == spotifyTag && spotifyURL != nil) || Self.spotifyIsPlaying()
            DispatchQueue.main.async {
                if spotify { self?.playSpotify() } else { self?.play(station: stations.indices.contains(last) ? last : 0) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard spotifyActive, muted || spotifyVolumeInFlight else { return }
        let source = Self.ifRunning("pause\nset sound volume to \(spotifyLevel)")
        spotifyQueue.sync { _ = NSAppleScript(source: source)?.executeAndReturnError(nil) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSource()
        return true
    }

    func play(station index: Int) {
        stopSpotify()
        source = .station(index)
        UserDefaults.standard.set(index, forKey: "station")
        startStream()
        refreshIndicators()
    }

    private func streamURL(_ index: Int) -> URL {
        UserDefaults.standard.string(forKey: "streamURL.\(index)").flatMap(URL.init(string:)) ?? stations[index].stream
    }

    func startStream() {
        guard let current, !paused else { return }
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
        if sender.tag == current { return togglePause() }
        play(station: sender.tag)
    }

    func adoptSpotify() {
        stopRadio()
        source = .spotify
        UserDefaults.standard.set(spotifyTag, forKey: "station")
    }

    @objc func playSpotify() {
        if spotifyActive { return togglePause() }
        adoptSpotify()
        spotify("set sound volume to \(spotifyVolume)\nplay\nreturn album of current track & linefeed & artist of current track & \" – \" & name of current track & linefeed & id of current track") { [weak self] result in
            guard let self else { return }
            if let result {
                let lines = result.components(separatedBy: "\n") + ["", ""]
                self.spotifyAlbum = nonEmpty([lines[0]]).first
                self.spotifyTrack = nonEmpty([lines[1]]).first
                self.spotifyTrackID = nonEmpty([lines[2]]).first
            } else if self.spotifyActive {
                self.source = nil
            }
            self.refreshIndicators()
        }
        refreshIndicators()
    }

    // A live stream resumes from now, not from where it was paused.
    @objc func togglePause() {
        paused.toggle()
        if spotifyActive {
            spotifyIfRunning(paused ? "pause" : "play")
        } else if paused {
            stopRadio()
        } else {
            startStream()
        }
        refreshIndicators()
    }

    @objc func previousTrack() {
        if spotifyActive { spotifyIfRunning("previous track") }
    }

    @objc func nextTrack() {
        if spotifyActive { spotifyIfRunning("next track") }
    }

    private func stopRadio() {
        guard current != nil else { return }
        streamSong = nil
        player.replaceCurrentItem(with: nil)
    }

    private func stopSpotify() {
        guard spotifyActive else { return }
        // Mute is Spotify's volume 0, which would otherwise outlive Radio switching away from it.
        spotifyIfRunning("pause\nset sound volume to \(spotifyLevel)")
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

    var percent: Int { Int((volume * 100).rounded()) }
    // Spotify's sound volume is loudness ≈ (value/100)^3.3 (measured), the radio's is linear, so the same slider is as loud on both.
    var spotifyLevel: Int { Int((pow(volume, 1 / 3.3) * 100).rounded()) }
    var spotifyVolume: Int { muted ? 0 : spotifyLevel }

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

    var spotifyTarget: URL? {
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

    var songs: [String?] {
        stationSongs.indices.map { $0 == current ? streamSong ?? stationSongs[$0] : stationSongs[$0] }
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
}

UserDefaults.standard.register(defaults: ["volume": 1.0, "showsNowPlaying": true, "showsDockIcon": true])
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(UserDefaults.standard.bool(forKey: "showsDockIcon") ? .regular : .accessory)
app.run()
