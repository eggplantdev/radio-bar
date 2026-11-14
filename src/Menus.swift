import Cocoa

extension AppDelegate {
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

    func refreshIndicators() {
        let level = "\(percent)%"
        let sourceName = spotifyActive ? "Spotify" : current.map { stations[$0].name }
        let badge = muted ? "🔇" : nil
        if NSApp.dockTile.badgeLabel != badge { NSApp.dockTile.badgeLabel = badge }

        let details = (spotifyActive ? [spotifyAlbum, spotifyTrack] : current.map { [stationShows[$0], songs[$0]] } ?? []).compactMap { $0 }
        let state = muted ? "speaker.slash.fill" : paused ? "pause.fill" : nil
        let imageKey = "\(sourceName ?? "-") \(state ?? "")"
        // An item too wide for the space left of the notch disappears from the menu bar altogether.
        let notch = ((statusItem.button?.window?.screen ?? NSScreen.main)?.safeAreaInsets.top ?? 0) > 0
        let limit = notch ? 40 : 100
        let playing = showsNowPlaying ? details.last.map { $0.count > limit ? $0.prefix(limit - 1) + "…" : $0 } : nil
        let parts = [state == nil ? level : nil, playing].compactMap { $0 }
        // A thin space widens the button's own image gap to match the gaps around „·”.
        let title = sourceName == nil || parts.isEmpty ? "" : "\u{2009}" + parts.joined(separator: " · ")
        // The menu hangs from the item's left edge, so a wider or narrower item would shift the open menu sideways.
        if !statusMenuOpen {
            // Every assignment redraws the menu-bar item, even with an equal value.
            if imageKey != buttonImageKey {
                buttonImageKey = imageKey
                let icon = spotifyActive ? spotifyImage : current.flatMap { logos[$0] }
                statusItem.button?.image = sourceName == nil ? NSImage(systemSymbolName: "radio", accessibilityDescription: "Radio") : icon.map { icon in state.map { besides(icon, $0) } ?? icon }
            }
            if statusItem.button?.title != title { statusItem.button?.title = title }
        }
        let nowPlaying = sourceName.map { ([$0] + details).joined(separator: "\n") }
        let toolTip = "\(nowPlaying ?? "Radio wyłączone")\n⌃⌥M wycisz · ⌃⌥↑ / ⌃⌥↓ głośność · ⌃⌥L otwórz w Spotify"
        if statusItem.button?.toolTip != toolTip { statusItem.button?.toolTip = toolTip }

        slider?.doubleValue = volume * 100
        let speaker = muted ? "speaker.slash" : volume == 0 ? "speaker" : "speaker.wave.\(min(Int(volume * 3) + 1, 3))"
        muteButton?.image = NSImage(systemSymbolName: speaker, accessibilityDescription: "Wycisz")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        levelLabel?.stringValue = muted ? "—" : level
        // „Otwórz w Spotify” already opens Spotify on the playing track.
        openSourceItem?.isHidden = spotifyActive
        for entry in stationMenuItems + appStationMenuItems + spotifyMenuItems {
            let state: NSControl.StateValue = isPlaying(entry) ? .on : .off
            if entry.state != state { entry.state = state; entry.view?.needsDisplay = true }
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
        entry.attributedTitle = menuTitle(image, name, show: show, song: song)
        entry.view?.needsDisplay = true
    }

    private func isPlaying(_ entry: NSMenuItem) -> Bool {
        entry.action == #selector(playSpotify) ? spotifyActive : entry.tag == current
    }

    // A menu never resizes an item's view.
    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem.menu { statusMenuOpen = true }
        let rows = menu.items.compactMap(\.view).map { ($0, ($0 as? MenuRowView)?.fit() ?? volumeRowWidth) }
        // A row's own width counts towards menu.size, so without the reset the menu never shrinks back.
        for (row, width) in rows { row.setFrameSize(NSSize(width: width, height: row.frame.height)) }
        let menuWidth = menu.size.width
        for (row, width) in rows { row.setFrameSize(NSSize(width: max(menuWidth, width), height: row.frame.height)) }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        statusMenuOpen = false
        slider?.menuClosed()
        refreshIndicators()
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        for entry in sourceItems(numbered: false) {
            if entry.action == #selector(playSpotify) { spotifyMenuItems.append(entry) } else { stationMenuItems.append(entry) }
            entry.view = MenuRowView(entry, keepsMenuOpen: true)
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
        muteButton.focusRingType = .none
        // A menu's window never becomes key, so an untinted button draws its symbol in the inactive grey.
        muteButton.contentTintColor = .labelColor
        // x 31 and 56 are where macOS 26 puts the rows' logos and their text.
        muteButton.frame = NSRect(x: 31, y: 8, width: 18, height: 24)

        slider = RowSlider()
        slider.minValue = 0
        slider.maxValue = 100
        slider.doubleValue = volume * 100
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isContinuous = true
        slider.frame = NSRect(x: 56, y: 0, width: 186, height: 40)
        slider.autoresizingMask = .width

        levelLabel = NSTextField(labelWithString: "")
        levelLabel.alignment = .right
        levelLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        levelLabel.frame = NSRect(x: 248, y: 11, width: 40, height: 18)
        levelLabel.autoresizingMask = .minXMargin

        let row = VolumeRowView(frame: NSRect(x: 0, y: 0, width: volumeRowWidth, height: 40))
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
        for entry in menu.items + menu.items.flatMap({ $0.submenu?.items ?? [] }) where !entry.isSeparatorItem && entry.view == nil {
            entry.view = MenuRowView(entry)
        }
        menu.items.compactMap(\.submenu).forEach { $0.delegate = self }
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

    private func besides(_ icon: NSImage, _ symbol: String) -> NSImage {
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) else { return icon }
        let gap: CGFloat = 5
        return NSImage(size: NSSize(width: icon.size.width + gap + glyph.size.width, height: icon.size.height), flipped: false) { rect in
            icon.draw(in: NSRect(origin: .zero, size: icon.size))
            let glyphRect = NSRect(x: icon.size.width + gap, y: (rect.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height)
            tinted(glyph, .labelColor).draw(in: glyphRect)
            return true
        }
    }

    func logo(_ station: Station) -> NSImage? {
        guard let source = NSImage(named: station.logo) else { return nil }
        return NSImage(size: NSSize(width: iconSide, height: iconSide), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: iconSide * 0.22, yRadius: iconSide * 0.22).addClip()
            source.draw(in: rect)
            return true
        }
    }

    func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
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

    func makeMenu() -> NSMenu {
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
