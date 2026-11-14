import Cocoa

extension AppDelegate {
    func observeSpotify() {
        guard listensToSpotify else { return }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            guard let self, let info = note.userInfo else { return }
            if let name = info["Name"] as? String {
                self.spotifyTrack = nonEmpty([info["Artist"], name]).joined(separator: " – ")
                self.spotifyAlbum = nonEmpty([info["Album"]]).first
                self.spotifyTrackID = nonEmpty([info["Track ID"]]).first
            }
            let playing = info["Player State"] as? String == "Playing"
            self.spotifyPaused = !playing
            if playing, !self.spotifyActive {
                self.adoptSpotify()
                self.syncSpotifyVolume()
            }
            self.refreshIndicators()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.spotify.client" else { return }
            if self.spotifyActive { self.source = nil }
            (self.spotifyTrack, self.spotifyAlbum, self.spotifyTrackID) = (nil, nil, nil)
            self.refreshIndicators()
        }
    }

    // Asks only a running Spotify that Radio may already drive, so a launch never starts it or raises the Automation prompt.
    static func spotifyIsPlaying() -> Bool {
        guard listensToSpotify, !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty,
              AEDeterminePermissionToAutomateTarget(NSAppleEventDescriptor(bundleIdentifier: "com.spotify.client").aeDesc,
                                                    AEEventClass(typeWildCard), AEEventID(typeWildCard), false) == noErr else { return false }
        let script = NSAppleScript(source: "tell application id \"com.spotify.client\" to return player state is playing")
        return script?.executeAndReturnError(nil).booleanValue == true
    }

    // A plain `tell` launches Spotify, which a pause or a volume change must not do.
    func spotifyIfRunning(_ commands: String, then: (() -> Void)? = nil) {
        spotify(Self.ifRunning(commands), tell: false) { _ in then?() }
    }

    static func ifRunning(_ commands: String) -> String {
        "if application id \"com.spotify.client\" is running then\ntell application id \"com.spotify.client\"\n\(commands)\nend tell\nend if"
    }

    func spotify(_ commands: String, tell: Bool = true, then: ((String?) -> Void)? = nil) {
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
    func syncSpotifyVolume() {
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
}
