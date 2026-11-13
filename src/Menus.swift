import Cocoa

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

    // A menu never resizes an item's view.
    func menuWillOpen(_ menu: NSMenu) {
        // The row's own width counts towards menu.size, so without the reset the menu never shrinks back.
        volumeRow.setFrameSize(NSSize(width: volumeRowWidth, height: volumeRow.frame.height))
        volumeRow.setFrameSize(NSSize(width: max(menu.size.width, volumeRowWidth), height: volumeRow.frame.height))
    }

    func makeStatusMenu() -> NSMenu {
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
