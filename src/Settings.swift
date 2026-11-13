import Cocoa
import ServiceManagement

extension AppDelegate {
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

    @objc func toggleMenuBarIcon() {
        statusItem.isVisible.toggle()
    }

    var showsNowPlaying: Bool { UserDefaults.standard.bool(forKey: "showsNowPlaying") }

    @objc func toggleNowPlaying() {
        UserDefaults.standard.set(!showsNowPlaying, forKey: "showsNowPlaying")
        refreshIndicators()
    }

    var showsYouTubeSearch: Bool { UserDefaults.standard.bool(forKey: "showsYouTubeSearch") }

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

    func settingsItem() -> NSMenuItem {
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
}
