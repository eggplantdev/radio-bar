import Cocoa

extension AppDelegate {
    func installDebugHook() {
        let out = NSHomeDirectory() + "/Library/Logs/radio-debug.log"
        func log(_ s: String) {
            let line = s + "\n"
            if let h = FileHandle(forWritingAtPath: out) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
            else { try? line.write(toFile: out, atomically: true, encoding: .utf8) }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("station.debug"), object: nil, queue: .main) { [weak self] n in
            guard let self, let cmd = n.object as? String else { return }
            switch cmd {
            case "mute": self.toggleMute(); log("mute -> \(self.muted)")
            case "up": self.volumeUp()
            case "down": self.volumeDown()
            case "off": self.turnOff(); log("off")
            case "state":
                log("state station=\(self.current.map { stations[$0].name } ?? "off") muted=\(self.muted) volume=\(self.volume) title=\(self.statusItem.button?.title ?? "-") rate=\(self.player.rate) item=\(self.player.currentItem.map { "\($0.status.rawValue)" } ?? "-") streamSong=\(self.streamSong ?? "-") checks=\(self.stationMenuItems.map { $0.state == .on }) logos=\(self.stationMenuItems.map { $0.attributedTitle?.containsAttachments ?? false }) songs=\(self.stationSongs.map { $0 ?? "-" }) shows=\(self.stationShows.map { $0 ?? "-" }) items=\(self.stationMenuItems.map { $0.attributedTitle?.string ?? "" }) spotifyID=\(self.spotifyTrackID ?? "-") spotify=\(self.spotifyMenuItems.map { "\($0.state == .on):\($0.attributedTitle?.string ?? $0.title)" })")
            case "rmenu": DispatchQueue.main.async { self.statusItem.button?.performClick(nil) }
            case "popup": DispatchQueue.main.async { _ = self.statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 400, y: 700), in: nil) }
            case "closemenu": self.statusItem.menu?.cancelTracking()
            case let c where c.hasPrefix("snap "):
                guard let b = self.statusItem.button, let rep = b.bitmapImageRepForCachingDisplay(in: b.bounds) else { log("snap fail"); break }
                b.cacheDisplay(in: b.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(c.dropFirst(5))))
                log("snap -> \(b.bounds.size)")
            case let c where c.hasPrefix("snaprows "):
                let titles = (self.stationMenuItems + self.spotifyMenuItems.filter { $0.attributedTitle != nil }).compactMap(\.attributedTitle)
                let sizes = titles.map { $0.boundingRect(with: NSSize(width: 2000, height: 400), options: .usesLineFragmentOrigin).size }
                let size = NSSize(width: (sizes.map(\.width).max() ?? 0) + 20, height: sizes.map { $0.height + 12 }.reduce(0, +))
                let image = NSImage(size: size, flipped: true) { rect in
                    NSColor.windowBackgroundColor.setFill(); rect.fill()
                    var y: CGFloat = 6
                    for (title, s) in zip(titles, sizes) { title.draw(with: NSRect(x: 10, y: y, width: s.width, height: s.height), options: .usesLineFragmentOrigin); y += s.height + 12 }
                    return true
                }
                let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(c.dropFirst(9))))
                log("snaprows \(size)")
            case let c where c.hasPrefix("snaprow "):
                let row = self.volumeRow!
                row.appearance = NSAppearance(named: .darkAqua)
                row.setFrameSize(NSSize(width: 420, height: row.frame.height))
                let rep = row.bitmapImageRepForCachingDisplay(in: row.bounds)!
                row.cacheDisplay(in: row.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(c.dropFirst(8))))
                log("snaprow")
            case let c where c.hasPrefix("call "):
                self.perform(NSSelectorFromString(String(c.dropFirst(5)))); log("called \(c.dropFirst(5))")
            case let c where c.hasPrefix("spotify "):
                var error: NSDictionary?
                let result = NSAppleScript(source: "tell application id \"com.spotify.client\" to \(c.dropFirst(8))")?.executeAndReturnError(&error)
                log("spotify \(c.dropFirst(8)) -> \(result?.stringValue ?? "-") \(error.map { "\($0)" } ?? "")")
            case let c where c.hasPrefix("fakesong "):
                let rest = c.dropFirst(9)
                self.stationSongs[Int(String(rest.prefix(1)))!] = String(rest.dropFirst(2))
                self.refreshIndicators(); log("fakesong")
            case "settings":
                let states = ["toggleMenuBarIcon", "toggleDockIcon", "toggleKeepInDock", "toggleLaunchAtLogin"].map { name -> String in
                    let probe = NSMenuItem(title: name, action: NSSelectorFromString(name), keyEquivalent: "")
                    let enabled = self.validateMenuItem(probe)
                    return "\(name)=\(probe.state == .on ? "on" : "off")\(enabled ? "" : "(disabled)")"
                }
                log("settings " + states.joined(separator: " "))
            case let c where c.hasPrefix("station "):
                let entry = self.stationMenuItems[Int(c.dropFirst(8))!]
                self.stationChosen(entry); log("station -> \(entry.title)")
            case let c where c.hasPrefix("slider "):
                self.slider.doubleValue = Double(c.dropFirst(7))!
                self.sliderMoved(self.slider); log("slider -> \(self.volume)")
            default:
                log("unknown \(cmd)")
            }
        }
    }
}
