import Cocoa

extension NSView {
    // Read live: a menu that closes under the pointer never sends mouseExited.
    var pointerInside: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
}

func drawRowHighlight(_ bounds: NSRect) {
    NSColor.labelColor.withAlphaComponent(0.1).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 6, yRadius: 6).fill()
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

// The eggplantdev mark from eggplantdev.com: an aubergine of dots, coloured top to bottom along the brand ramp, with a glow.
func brandMark(height: CGFloat) -> NSImage {
    let grid = ["0001000", "0011000", "0011100", "0111100", "0111110", "1111110", "1111111", "1111111", "0111110", "0011100"]
    let ramp: [(CGFloat, CGFloat, CGFloat)] = [(0x10, 0xff, 0xaa), (0x00, 0xe5, 0xff), (0xa8, 0x55, 0xf7), (0xd9, 0x46, 0xef)]
    let gap = height / CGFloat(grid.count + 1), radius = gap * 2.9 / 8
    return NSImage(size: NSSize(width: gap * 8, height: height), flipped: true) { _ in
        for (row, line) in grid.enumerated() {
            let t = CGFloat(row) / CGFloat(grid.count - 1) * CGFloat(ramp.count - 1)
            let i = min(Int(t), ramp.count - 2), f = t - CGFloat(i)
            let (a, b) = (ramp[i], ramp[i + 1])
            let color = NSColor(srgbRed: (a.0 + (b.0 - a.0) * f) / 255, green: (a.1 + (b.1 - a.1) * f) / 255, blue: (a.2 + (b.2 - a.2) * f) / 255, alpha: 1)
            let glow = NSShadow()
            glow.shadowColor = color
            glow.shadowBlurRadius = radius * 1.6
            glow.set()
            color.setFill()
            for (column, cell) in line.enumerated() where cell == "1" {
                NSBezierPath(ovalIn: NSRect(x: gap * CGFloat(column + 1) - radius, y: gap * CGFloat(row + 1) - radius, width: radius * 2, height: radius * 2)).fill()
            }
        }
        return true
    }
}

// A menu opened from the menu bar leaves Radio in the background, where macOS ignores its cursor changes; this private flag lifts that.
let cursorInBackground: Bool = {
    typealias DefaultConnection = @convention(c) () -> Int32
    typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    guard let symbols = dlopen(nil, RTLD_NOW), let connection = dlsym(symbols, "_CGSDefaultConnection"),
          let setProperty = dlsym(symbols, "CGSSetConnectionProperty") else { return false }
    let id = unsafeBitCast(connection, to: DefaultConnection.self)()
    return unsafeBitCast(setProperty, to: SetProperty.self)(id, id, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
}()

// The whole row's height takes a click or a drag — the stock slider takes one only on its thin bar.
final class RowSlider: NSSlider {
    private let knob: CGFloat = 12
    private var dragging = false
    private var hand: Timer?
    // Pointer anywhere in the row: its highlight, the green fill and the knob come and go together.
    private(set) var lit = false {
        didSet { if lit != oldValue { needsDisplay = true; superview?.needsDisplay = true } }
    }

    func updateLit() { lit = dragging || superview?.pointerInside == true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        _ = cursorInBackground
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override func cursorUpdate(with event: NSEvent) { showHand() }

    private var bar: NSRect { NSRect(x: knob / 2, y: bounds.midY - 2, width: bounds.width - knob, height: 4) }
    private var overBar: Bool { dragging || pointerInside }

    override func mouseEntered(with event: NSEvent) { updateLit(); showHand() }
    // A menu opened with the pointer already over the slider sends no mouseEntered.
    override func mouseMoved(with event: NSEvent) { updateLit(); showHand() }
    override func mouseExited(with event: NSEvent) { updateLit(); NSCursor.arrow.set() }

    // The menu sets the arrow again after every event it handles, so the hand is held by a timer while the pointer stays.
    private func showHand() {
        NSCursor.pointingHand.set()
        guard hand == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self, self.overBar else {
                timer.invalidate()
                self?.hand = nil
                NSCursor.arrow.set()
                return
            }
            NSCursor.pointingHand.set()
        }
        RunLoop.main.add(timer, forMode: .common)
        hand = timer
    }

    // A menu closed mid-drag or under the pointer sends neither mouseUp nor mouseExited.
    func menuClosed() {
        hand?.invalidate()
        hand = nil
        dragging = false
        lit = false
    }

    // No nextEvent loop of its own: a menu can swallow the mouse-up, and the loop would wait for it forever.
    override func mouseDown(with event: NSEvent) { dragging = true; follow(event) }
    override func mouseDragged(with event: NSEvent) { follow(event) }
    override func mouseUp(with event: NSEvent) { follow(event); dragging = false; updateLit() }

    private func follow(_ event: NSEvent) {
        // A menu hands its views events whose locationInWindow isn't always in this view's window.
        guard let window else { return }
        let x = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil).x
        doubleValue = minValue + (maxValue - minValue) * min(max((x - bar.minX) / bar.width, 0), 1)
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bar = bar
        let filled = NSRect(x: bar.minX, y: bar.minY, width: bar.width * (doubleValue - minValue) / (maxValue - minValue), height: bar.height)
        NSColor.labelColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        (lit ? NSColor(srgbRed: 0.12, green: 0.84, blue: 0.38, alpha: 1) : .labelColor).setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
        guard lit else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: filled.maxX - knob / 2, y: bounds.midY - knob / 2, width: knob, height: knob)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

class HoverRowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    // A menu with views opens in an ordinary window, which lands on the desktop space behind another display's full-screen app.
    override func viewDidMoveToWindow() {
        window?.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    // The menu takes the highlight away only after the pointer has left.
    override func mouseExited(with event: NSEvent) { needsDisplay = true; DispatchQueue.main.async { self.needsDisplay = true } }
}

// Its own highlight, on top of the whole row's, shows which button a click lands on.
final class TransportButton: NSButton {
    init(_ description: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .none
        imagePosition = .imageOnly
        setAccessibilityLabel(description)
        // A menu's window never becomes key, so an untinted button draws its symbol in the inactive grey.
        contentTintColor = .labelColor
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    var symbol = "" {
        didSet {
            guard symbol != oldValue else { return }
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        }
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.35 }
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled, pointerInside {
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

final class VolumeRowView: HoverRowView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        // A menu opened with the pointer already in the row sends no mouseEntered.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    private var slider: RowSlider? { subviews.lazy.compactMap { $0 as? RowSlider }.first }

    override func mouseEntered(with event: NSEvent) { slider?.updateLit() }
    override func mouseExited(with event: NSEvent) { slider?.updateLit() }
    override func mouseMoved(with event: NSEvent) { slider?.updateLit() }

    override func draw(_ dirtyRect: NSRect) {
        if slider?.lit == true { drawRowHighlight(bounds) }
    }
}

private let menuFont = NSFont.menuFont(ofSize: 0)
private let menuLineHeight = NSLayoutManager().defaultLineHeight(for: menuFont)

final class MenuRowView: HoverRowView {
    private weak var item: NSMenuItem?
    // A plain menu item closes the menu when clicked; a source row stays open, so a pause or a switch shows in place.
    private let keepsMenuOpen: Bool
    // Where macOS 26 puts a native row's check, its text and its trailing key equivalent or arrow.
    private let checkX: CGFloat = 13, textX: CGFloat = 31, trailingInset: CGFloat = 14, minHeight: CGFloat = 24

    init(_ item: NSMenuItem, keepsMenuOpen: Bool = false) {
        self.item = item
        self.keepsMenuOpen = keepsMenuOpen
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    private var title: NSAttributedString {
        item?.attributedTitle ?? NSAttributedString(string: item?.title ?? "", attributes: [.font: menuFont])
    }

    private var titleSize: NSSize {
        title.boundingRect(with: NSSize(width: 2000, height: 400), options: .usesLineFragmentOrigin).size
    }

    private var keyEquivalent: NSAttributedString? {
        guard let item, !item.keyEquivalent.isEmpty else { return nil }
        let mask = item.keyEquivalentModifierMask
        let modifiers = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")].filter { mask.contains($0.0) }.map(\.1)
        return NSAttributedString(string: modifiers.joined() + item.keyEquivalent.uppercased(), attributes: [.font: menuFont, .foregroundColor: NSColor.secondaryLabelColor])
    }

    private var arrow: NSImage? {
        guard item?.submenu != nil, let symbol = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) else { return nil }
        return tinted(symbol, .labelColor)
    }

    // Returns the width the row needs; the menu stretches it to its own width afterwards.
    func fit() -> CGFloat {
        let size = titleSize
        let trailing = (keyEquivalent?.size().width ?? arrow?.size.width).map { $0 + 24 } ?? 0
        let width = ceil(textX + size.width + trailing + 30)
        setFrameSize(NSSize(width: width, height: max(ceil(size.height) + 12, minHeight)))
        return width
    }

    override func mouseUp(with event: NSEvent) {
        guard pointerInside, let item, item.isEnabled, item.submenu == nil, let action = item.action else { return }
        let target = item.target
        if keepsMenuOpen { NSApp.sendAction(action, to: target, from: item); return }
        item.menu?.cancelTracking()
        // The default mode never runs inside the menu's tracking, so a modal alert or a Dock restart waits until it has closed.
        RunLoop.main.perform(inModes: [.default]) { NSApp.sendAction(action, to: target, from: item) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        if item.isEnabled, item.isHighlighted { drawRowHighlight(bounds) }
        NSGraphicsContext.current?.cgContext.setAlpha(item.isEnabled ? 1 : 0.35)
        let text = NSMutableAttributedString(attributedString: title)
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { color, range, _ in
            if color == nil { text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
        }
        let textHeight = ceil(titleSize.height)
        let textY = max((bounds.height - textHeight) / 2, 0)
        text.draw(with: NSRect(x: textX, y: textY, width: bounds.width - textX, height: textHeight), options: .usesLineFragmentOrigin)
        let lineHeight = min(textHeight, menuLineHeight)
        if let key = keyEquivalent {
            let size = key.size()
            key.draw(at: NSPoint(x: bounds.maxX - trailingInset - size.width, y: textY + (lineHeight - size.height) / 2))
        } else if let arrow {
            arrow.draw(in: NSRect(x: bounds.maxX - trailingInset - arrow.size.width, y: (bounds.height - arrow.size.height) / 2, width: arrow.size.width, height: arrow.size.height))
        }
        guard item.state == .on, let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .semibold)) else { return }
        tinted(check, .labelColor).draw(in: NSRect(x: checkX, y: textY + (lineHeight - check.size.height) / 2, width: check.size.width, height: check.size.height))
    }
}
