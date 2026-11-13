import AppKit
let src = NSImage(contentsOfFile: CommandLine.arguments[1])!; let k: CGFloat = 8
let sz = NSSize(width: src.size.width * k, height: src.size.height * k)
let out = NSImage(size: sz, flipped: false) { r in
    NSColor(white: 0.25, alpha: 1).setFill(); r.fill()
    src.draw(in: r); return true }
let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
