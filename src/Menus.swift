import Cocoa

// Like Spotify's volume bar: thin at rest; under the pointer it shows a knob and a pointing hand, and the whole row's height takes a click or a drag — the stock slider takes one only on its thin bar.
final class RowSlider: NSSlider {
    private let knob: CGFloat = 12
    private var dragging = false
    private var knobShown: CGFloat = 0
    private var fade: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func cursorUpdate(with event: NSEvent) { showHand() }

    private var bar: NSRect { NSRect(x: knob / 2, y: bounds.midY - 2, width: bounds.width - knob, height: 4) }

    // Read live: a menu that closes under the pointer never sends mouseExited, which would leave the knob up next time.
    private var hovered: Bool {
        guard let window else { return false }
        return dragging || bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func mouseEntered(with event: NSEvent) { fadeKnob(); showHand() }
    override func mouseMoved(with event: NSEvent) { showHand() }

    // The menu resets the cursor to an arrow while it handles each move, so the hand is set once it's done.
    private func showHand() {
        NSCursor.pointingHand.set()
        DispatchQueue.main.async { if self.hovered { NSCursor.pointingHand.set() } }
    }
    override func mouseExited(with event: NSEvent) { fadeKnob(); NSCursor.arrow.set() }

    // In the menu's tracking mode too, which a default-mode timer would wait out.
    private func fadeKnob() {
        guard fade == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let target: CGFloat = self.hovered ? 1 : 0
            self.knobShown += max(min(target - self.knobShown, 0.15), -0.15)
            self.needsDisplay = true
            if self.knobShown == target { timer.invalidate(); self.fade = nil }
        }
        RunLoop.main.add(timer, forMode: .common)
        fade = timer
    }

    // No nextEvent loop of its own: a menu can swallow the mouse-up, and the loop would wait for it forever.
    override func mouseDown(with event: NSEvent) { dragging = true; follow(event) }
    override func mouseDragged(with event: NSEvent) { follow(event) }
    override func mouseUp(with event: NSEvent) { follow(event); dragging = false; fadeKnob() }

    private func follow(_ event: NSEvent) {
        // A menu hands its views events whose locationInWindow isn't always in this view's window.
        guard let window else { return }
        let x = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil).x
        doubleValue = minValue + (maxValue - minValue) * min(max((x - bar.minX) / bar.width, 0), 1)
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bar = bar
        // Without a fade running, the live pointer decides, so a menu closed under the pointer doesn't reopen with the knob up.
        let shown = fade == nil ? (hovered ? 1 : 0) : knobShown
        let filled = NSRect(x: bar.minX, y: bar.minY, width: bar.width * (doubleValue - minValue) / (maxValue - minValue), height: bar.height)
        NSColor.labelColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
        guard shown > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.withAlphaComponent(shown).setFill()
        let side = knob * (0.5 + 0.5 * shown)
        NSBezierPath(ovalIn: NSRect(x: filled.maxX - side / 2, y: bounds.midY - side / 2, width: side, height: side)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

// The quiet grey of Control Center's menus (Wi-Fi, Bluetooth); a plain menu item would highlight in the accent colour instead.
func drawRowHighlight(_ bounds: NSRect) {
    NSColor.labelColor.withAlphaComponent(0.1).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 6, yRadius: 6).fill()
}

// Every row of the status menu draws itself, so they all share one highlight; a source row also keeps the menu open when clicked, so a pause or a switch shows in place.
final class MenuRowView: NSView {
    private weak var item: NSMenuItem?
    private let keepsMenuOpen: Bool
    private(set) var naturalWidth: CGFloat = 0
    // Where macOS 26 puts a native row's check, its text and its trailing key equivalent or arrow.
    private let checkX: CGFloat = 13, textX: CGFloat = 31, trailingInset: CGFloat = 14, minHeight: CGFloat = 24

    init(_ item: NSMenuItem, keepsMenuOpen: Bool = false) {
        self.item = item
        self.keepsMenuOpen = keepsMenuOpen
        super.init(frame: .zero)
        item.view = self
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    private var title: NSAttributedString {
        item?.attributedTitle ?? NSAttributedString(string: item?.title ?? "", attributes: [.font: NSFont.menuFont(ofSize: 0)])
    }

    private var keyEquivalent: NSAttributedString? {
        guard let item, !item.keyEquivalent.isEmpty else { return nil }
        let mask = item.keyEquivalentModifierMask
        let modifiers = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")].filter { mask.contains($0.0) }.map(\.1)
        return NSAttributedString(string: modifiers.joined() + item.keyEquivalent.uppercased(), attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor])
    }

    private var arrow: NSImage? {
        guard item?.submenu != nil, let symbol = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) else { return nil }
        return tinted(symbol, .labelColor)
    }

    private var trailingWidth: CGFloat { keyEquivalent.map { $0.size().width + 24 } ?? arrow.map { $0.size.width + 24 } ?? 0 }

    func fit() {
        let size = title.boundingRect(with: NSSize(width: 2000, height: 400), options: .usesLineFragmentOrigin).size
        naturalWidth = ceil(textX + size.width + trailingWidth + 20)
        setFrameSize(NSSize(width: naturalWidth, height: max(ceil(size.height) + 6, minHeight)))
    }

    // A row resizing under an open menu relays the whole menu out mid-drag; menuWillOpen sizes it instead.
    func titleChanged() {
        if window?.isVisible != true { fit() }
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    // The menu takes the highlight away only after the pointer has left.
    override func mouseExited(with event: NSEvent) { needsDisplay = true; DispatchQueue.main.async { self.needsDisplay = true } }

    override func mouseUp(with event: NSEvent) {
        guard let item, item.isEnabled, item.submenu == nil, let action = item.action else { return }
        if !keepsMenuOpen { item.menu?.cancelTracking() }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    private var highlighted: Bool {
        guard let item, item.isEnabled, item.isHighlighted, let window else { return false }
        // A highlight the menu left behind on a row the pointer has already left.
        let pointer = window.mouseLocationOutsideOfEventStream
        return !(window.contentView?.frame.contains(pointer) ?? false) || bounds.contains(convert(pointer, from: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        if highlighted { drawRowHighlight(bounds) }
        NSGraphicsContext.current?.cgContext.setAlpha(item.isEnabled ? 1 : 0.35)
        let text = NSMutableAttributedString(attributedString: title)
        text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: text.length))
        let textHeight = ceil(text.boundingRect(with: NSSize(width: 2000, height: 400), options: .usesLineFragmentOrigin).height)
        let textY = max((bounds.height - textHeight) / 2, 0)
        text.draw(with: NSRect(x: textX, y: textY, width: bounds.width - textX, height: textHeight), options: .usesLineFragmentOrigin)
        let lineHeight = min(textHeight, NSLayoutManager().defaultLineHeight(for: .menuFont(ofSize: 0)))
        if let key = keyEquivalent {
            let size = key.size()
            key.draw(at: NSPoint(x: bounds.maxX - trailingInset - size.width, y: textY + (lineHeight - size.height) / 2))
        } else if let arrow {
            arrow.draw(in: NSRect(x: bounds.maxX - trailingInset - arrow.size.width, y: (bounds.height - arrow.size.height) / 2, width: arrow.size.width, height: arrow.size.height))
        }
        guard item.state == .on, let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .semibold)) else { return }
        // On the first line, not centred on a row of several.
        tinted(check, .labelColor).draw(in: NSRect(x: checkX, y: textY + (lineHeight - check.size.height) / 2, width: check.size.width, height: check.size.height))
    }
}

// The volume row highlights like the rows above it while the pointer is over it.
final class VolumeRowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard let window, bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return }
        drawRowHighlight(bounds)
    }
}

// Draws a template symbol in a colour resolved at draw time, next to images that keep their own colours.
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    NSImage(size: image.size, flipped: false) { bounds in
        image.draw(in: bounds)
        color.set()
        bounds.fill(using: .sourceAtop)
        return true
    }
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
        let state = muted ? "speaker.slash.fill" : paused ? "pause.fill" : nil
        let imageKey = "\(sourceName ?? "-") \(state ?? "")"
        if imageKey != buttonImageKey {
            buttonImageKey = imageKey
            let icon = spotifyActive ? spotifyImage : current.flatMap { logos[$0] }
            statusItem.button?.image = sourceName == nil ? NSImage(systemSymbolName: "radio", accessibilityDescription: "Radio") : icon.map { icon in state.map { besides(icon, $0) } ?? icon }
        }
        // An item too wide for the space left of the notch disappears from the menu bar altogether.
        let notch = ((statusItem.button?.window?.screen ?? NSScreen.main)?.safeAreaInsets.top ?? 0) > 0
        let limit = notch ? 40 : 100
        let playing = showsNowPlaying ? details.last.map { $0.count > limit ? $0.prefix(limit - 1) + "…" : $0 } : nil
        let parts = [state == nil ? level : nil, playing].compactMap { $0 }
        // A thin space widens the button's own image gap to match the gaps around „·”.
        let title = sourceName == nil || parts.isEmpty ? "" : "\u{2009}" + parts.joined(separator: " · ")
        if statusItem.button?.title != title { statusItem.button?.title = title }
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
            entry.state = isPlaying(entry) ? .on : .off
            entry.view?.needsDisplay = true
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
        (entry.view as? MenuRowView)?.titleChanged()
    }

    private func isPlaying(_ entry: NSMenuItem) -> Bool {
        entry.action == #selector(playSpotify) ? spotifyActive : entry.tag == current
    }

    // A menu never resizes an item's view.
    func menuWillOpen(_ menu: NSMenu) {
        let rowViews = menu.items.compactMap { $0.view as? MenuRowView }
        rowViews.forEach { $0.fit() }
        var rows = rowViews.map { ($0 as NSView, $0.naturalWidth) }
        if menu.items.contains(where: { $0.view === volumeRow }) { rows.append((volumeRow, volumeRowWidth)) }
        // A row's own width counts towards menu.size, so without the reset the menu never shrinks back.
        for (row, width) in rows { row.setFrameSize(NSSize(width: width, height: row.frame.height)) }
        for (row, width) in rows { row.setFrameSize(NSSize(width: max(menu.size.width, width), height: row.frame.height)) }
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        for entry in sourceItems(numbered: false) {
            if entry.action == #selector(playSpotify) { spotifyMenuItems.append(entry) } else { stationMenuItems.append(entry) }
            _ = MenuRowView(entry, keepsMenuOpen: true)
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
            _ = MenuRowView(entry)
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
