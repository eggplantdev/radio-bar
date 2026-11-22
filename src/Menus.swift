import Cocoa

extension AppDelegate {
    func refreshIndicators() {
        let level = "\(percent)%"
        let sourceName = spotifyActive ? "Spotify" : current.map { stations[$0].name }

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
        playPauseButton?.symbol = paused ? "play.fill" : "pause.fill"
        playPauseButton?.isEnabled = source != nil
        // A live stream has no previous or next song.
        previousButton?.isEnabled = spotifyActive
        nextButton?.isEnabled = spotifyActive
        // „Otwórz w Spotify” already opens Spotify on the playing track.
        openSourceItem?.isHidden = spotifyActive
        for entry in stationMenuItems + [spotifyMenuItem].compactMap({ $0 }) {
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
        if let entry = spotifyMenuItem {
            decorate(entry, spotifyImage, "Spotify", show: spotifyAlbum, song: spotifyTrack)
        }
        // A song arriving while the menu is open can add a line to its row.
        if statusMenuOpen, let menu = statusItem.menu { fitRows(menu) }
    }

    private func decorate(_ entry: NSMenuItem, _ image: NSImage?, _ name: String, show: String?, song: String?) {
        entry.attributedTitle = menuTitle(image, name, show: show, song: song)
        entry.view?.needsDisplay = true
    }

    private func isPlaying(_ entry: NSMenuItem) -> Bool {
        entry.action == #selector(playSpotify) ? spotifyActive : entry.tag == current
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem.menu { statusMenuOpen = true }
        fitRows(menu)
    }

    // A menu never resizes an item's view.
    private func fitRows(_ menu: NSMenu) {
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

        for entry in sourceItems() {
            if entry.action == #selector(playSpotify) { spotifyMenuItem = entry } else { stationMenuItems.append(entry) }
            entry.view = MenuRowView(entry, keepsMenuOpen: true)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        youTubeItem = symbolItem("Szukaj na YouTube", "play.rectangle", #selector(findOnYouTube))
        youTubeItem.isHidden = !showsYouTubeSearch
        menu.addItem(youTubeItem)

        previousButton = TransportButton("Poprzedni utwór", target: self, action: #selector(previousTrack))
        playPauseButton = TransportButton("Odtwórz / wstrzymaj", target: self, action: #selector(togglePause))
        nextButton = TransportButton("Następny utwór", target: self, action: #selector(nextTrack))
        previousButton.symbol = "backward.fill"
        nextButton.symbol = "forward.fill"
        for (index, button) in [previousButton!, playPauseButton!, nextButton!].enumerated() {
            button.frame = NSRect(x: 250 + CGFloat(index) * 26, y: 6, width: 26, height: 28)
            button.autoresizingMask = .minXMargin
        }

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
        slider.frame = NSRect(x: 56, y: 0, width: 142, height: 40)
        slider.autoresizingMask = .width

        levelLabel = NSTextField(labelWithString: "")
        levelLabel.alignment = .right
        levelLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        levelLabel.frame = NSRect(x: 204, y: 11, width: 40, height: 18)
        levelLabel.autoresizingMask = .minXMargin

        let row = VolumeRowView(frame: NSRect(x: 0, y: 0, width: volumeRowWidth, height: 40))
        volumeRow = row
        [previousButton, playPauseButton, nextButton, muteButton, slider, levelLabel].forEach { row.addSubview($0!) }
        let rowItem = NSMenuItem()
        rowItem.view = row
        menu.addItem(rowItem)

        menu.addItem(.separator())
        openSourceItem = item("Otwórz stronę stacji", #selector(openSource))
        menu.addItem(openSourceItem)
        if spotifyURL != nil {
            let find = symbolItem("Otwórz w Spotify", "arrow.up.forward.app", #selector(findInSpotify), "l")
            find.keyEquivalentModifierMask = [.control, .option]
            menu.addItem(find)
        }
        menu.addItem(settingsItem())
        menu.addItem(withTitle: "Zakończ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(footerItem())
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

    private func footerItem() -> NSMenuItem {
        let entry = item("eggplantdev.com", #selector(openEggplantdev))
        let font = NSFont.menuFont(ofSize: 11)
        let title = NSMutableAttributedString(string: "© 2026 eggplantdev.com  ", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        let attachment = NSTextAttachment()
        attachment.image = brandMark(height: 18)
        attachment.bounds = NSRect(x: 0, y: (font.capHeight - 18) / 2, width: attachment.image!.size.width, height: 18)
        title.append(NSAttributedString(attachment: attachment))
        entry.attributedTitle = title
        return entry
    }

    @objc func openEggplantdev() {
        NSWorkspace.shared.open(URL(string: "https://eggplantdev.com")!)
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

    private func sourceItems() -> [NSMenuItem] {
        var entries = stations.enumerated().map { index, station in
            let entry = item(station.name, #selector(stationChosen(_:)))
            entry.tag = index
            return entry
        }
        if spotifyURL != nil { entries.append(item("Spotify", #selector(playSpotify))) }
        return entries
    }

    // Never shown by an accessory app, but ⌘V in an alert's text field and ⌘Q still go through it.
    func makeMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
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

        return main
    }
}
