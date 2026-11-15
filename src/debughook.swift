#if DEBUGHOOK
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
            case "state":
                log("state cursorInBackground=\(cursorInBackground) screen=\(self.statusItem.button?.window?.screen?.localizedName ?? "-") station=\(self.current.map { stations[$0].name } ?? "off") muted=\(self.muted) volume=\(self.volume) title=\(self.statusItem.button?.title ?? "-") rate=\(self.player.rate) item=\(self.player.currentItem.map { "\($0.status.rawValue)" } ?? "-") streamSong=\(self.streamSong ?? "-") checks=\(self.stationMenuItems.map { $0.state == .on }) logos=\(self.stationMenuItems.map { $0.attributedTitle?.containsAttachments ?? false }) songs=\(self.stationSongs.map { $0 ?? "-" }) shows=\(self.stationShows.map { $0 ?? "-" }) items=\(self.stationMenuItems.map { $0.attributedTitle?.string ?? "" }) spotifyID=\(self.spotifyTrackID ?? "-") youtube=\(self.youTubeTarget?.absoluteString ?? "-") youtubeHidden=\(self.youTubeItem.isHidden) spotify=\(self.spotifyMenuItems.map { "\($0.state == .on):\($0.attributedTitle?.string ?? $0.title)" })")
            case "popup": DispatchQueue.main.async { _ = self.statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 400, y: 700), in: nil) }
            case "closemenu": self.statusItem.menu?.cancelTracking()
            case "where":
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let cg = { (r: NSRect) in "x=\(Int(r.minX)) y=\(Int(top - r.maxY)) w=\(Int(r.width)) h=\(Int(r.height))" }
                log("where item=\(self.statusItem.button?.window.map { cg($0.frame) } ?? "-") on=\(self.statusItem.button?.window?.screen?.localizedName ?? "-") open=\(self.statusMenuOpen) screens=\(NSScreen.screens.map { "\($0.localizedName) \(cg($0.frame))" })")
            case let c where c.hasPrefix("snap "):
                guard let b = self.statusItem.button, let rep = b.bitmapImageRepForCachingDisplay(in: b.bounds) else { log("snap fail"); break }
                b.cacheDisplay(in: b.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(c.dropFirst(5))))
                log("snap -> \(b.bounds.size)")
            case let c where c.hasPrefix("snapmenu "):
                guard let menu = self.statusItem.menu else { break }
                let parts = c.dropFirst(9).split(separator: " ")
                let target = parts.count > 1 ? menu.items.first { $0.submenu != nil }?.submenu ?? menu : menu
                self.menuWillOpen(target)
                defer { self.menuDidClose(target) }
                let views = target.items.filter { !$0.isHidden }.map { $0.view ?? NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 11)) }
                let width = views.map(\.frame.width).max() ?? 0
                let reps = views.map { v -> NSBitmapImageRep in
                    let appearance = v.appearance
                    v.appearance = NSAppearance(named: .darkAqua)
                    defer { v.appearance = appearance }
                    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
                    v.cacheDisplay(in: v.bounds, to: rep)
                    return rep
                }
                let size = NSSize(width: width, height: views.map(\.frame.height).reduce(0, +))
                let image = NSImage(size: size, flipped: true) { rect in
                    NSColor(white: 0.17, alpha: 1).setFill(); rect.fill()
                    var y: CGFloat = 0
                    for (v, rep) in zip(views, reps) { rep.draw(in: NSRect(x: 0, y: y, width: v.frame.width, height: v.frame.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil); y += v.frame.height }
                    return true
                }
                try? NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(parts[0])))
                log("snapmenu \(size)")
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
#endif
