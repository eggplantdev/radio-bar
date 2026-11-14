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
    private var knobShown: CGFloat = 0
    private var fade: Timer?
    private var hand: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        _ = cursorInBackground
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override func cursorUpdate(with event: NSEvent) { showHand() }

    private var bar: NSRect { NSRect(x: knob / 2, y: bounds.midY - 2, width: bounds.width - knob, height: 4) }
    private var hovered: Bool { dragging || pointerInside }

    override func mouseEntered(with event: NSEvent) { fadeKnob(); showHand() }
    // A menu opened with the pointer already over the slider sends no mouseEntered.
    override func mouseMoved(with event: NSEvent) { if knobShown == 0 { fadeKnob() }; showHand() }
    override func mouseExited(with event: NSEvent) { fadeKnob(); NSCursor.arrow.set() }

    // The menu sets the arrow again after every event it handles, so the hand is held by a timer while the pointer stays.
    private func showHand() {
        NSCursor.pointingHand.set()
        guard hand == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self, self.hovered else {
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

    // A menu closed mid-drag or under the pointer sends neither mouseUp nor mouseExited.
    func menuClosed() {
        hand?.invalidate()
        hand = nil
        fade?.invalidate()
        fade = nil
        dragging = false
        knobShown = 0
        needsDisplay = true
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
        let filled = NSRect(x: bar.minX, y: bar.minY, width: bar.width * (doubleValue - minValue) / (maxValue - minValue), height: bar.height)
        NSColor.labelColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        (NSColor.labelColor.blended(withFraction: knobShown, of: NSColor(srgbRed: 0.12, green: 0.84, blue: 0.38, alpha: 1)) ?? .labelColor).setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
        guard knobShown > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        // Grows instead of fading: a fading white knob is invisible on the white fill of a dark menu.
        NSColor.white.setFill()
        let side = knob * knobShown
        NSBezierPath(ovalIn: NSRect(x: filled.maxX - side / 2, y: bounds.midY - side / 2, width: side, height: side)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

class HoverRowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    // The menu takes the highlight away only after the pointer has left.
    override func mouseExited(with event: NSEvent) { needsDisplay = true; DispatchQueue.main.async { self.needsDisplay = true } }
}

final class VolumeRowView: HoverRowView {
    override func draw(_ dirtyRect: NSRect) {
        if pointerInside { drawRowHighlight(bounds) }
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
        let width = ceil(textX + size.width + trailing + 20)
        setFrameSize(NSSize(width: width, height: max(ceil(size.height) + 6, minHeight)))
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
        text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: text.length))
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
