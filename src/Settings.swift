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
            guard alert.runInFront() == .alertFirstButtonReturn else { return }
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
            NSAlert(error: error).runInFront()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleNowPlaying):
            menuItem.state = showsNowPlaying ? .on : .off
        case #selector(toggleYouTubeSearch):
            menuItem.state = showsYouTubeSearch ? .on : .off
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

    // A quarantined app launched from Downloads runs from a random read-only copy that vanishes on quit.
    private func isInstalled() -> Bool {
        guard Bundle.main.bundlePath.contains("/AppTranslocation/") else { return true }
        let alert = NSAlert()
        alert.messageText = "Najpierw przenieś Radio do folderu Aplikacje"
        alert.informativeText = "Dopóki apka leży w Pobranych, macOS uruchamia ją z tymczasowej kopii. Przeciągnij Radio do Aplikacji i otwórz ponownie."
        alert.runInFront()
        return false
    }

    func settingsItem() -> NSMenuItem {
        let menu = NSMenu(title: "Ustawienia")
        menu.addItem(item("Pokazuj, co leci, w pasku menu", #selector(toggleNowPlaying)))
        menu.addItem(item("Pokazuj „Szukaj na YouTube”", #selector(toggleYouTubeSearch)))
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

extension NSAlert {
    // Radio is never the active app when its menu closes, so the alert would open behind the front window.
    @discardableResult
    func runInFront() -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return runModal()
    }
}
