import Cocoa
import WebKit

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
                log("state station=\(self.current.map { stations[$0].name } ?? "off") muted=\(self.muted) volume=\(self.volume) title=\(self.statusItem.button?.title ?? "-") window=\(self.window.title) checks=\(self.stationMenuItems.map { $0.state == .on }) logos=\(self.stationMenuItems.map { $0.attributedTitle?.containsAttachments ?? false }) track=\(self.stationTrack ?? "-") items=\(self.stationMenuItems.map { $0.attributedTitle?.string ?? "" }) spotify=\(self.spotifyMenuItems.map { "\($0.state == .on):\($0.attributedTitle?.string ?? $0.title)" })")
            case "rmenu": DispatchQueue.main.async { self.statusItem.button?.performClick(nil) }
            case "popup": DispatchQueue.main.async { _ = self.statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 400, y: 700), in: nil) }
            case "closemenu": self.statusItem.menu?.cancelTracking()
            case let c where c.hasPrefix("snap "):
                guard let b = self.statusItem.button, let rep = b.bitmapImageRepForCachingDisplay(in: b.bounds) else { log("snap fail"); break }
                b.cacheDisplay(in: b.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(c.dropFirst(5))))
                log("snap -> \(b.bounds.size)")
            case let c where c.hasPrefix("call "):
                self.perform(NSSelectorFromString(String(c.dropFirst(5)))); log("called \(c.dropFirst(5))")
            case let c where c.hasPrefix("spotify "):
                var error: NSDictionary?
                let result = NSAppleScript(source: "tell application id \"com.spotify.client\" to \(c.dropFirst(8))")?.executeAndReturnError(&error)
                log("spotify \(c.dropFirst(8)) -> \(result?.stringValue ?? "-") \(error.map { "\($0)" } ?? "")")
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
                self.web.evaluateJavaScript(cmd) { r, e in log("js: \(String(describing: r)) err: \(String(describing: e))") }
            }
        }
    }
}
