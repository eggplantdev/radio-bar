import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
func post(_ t: CGEventType, _ b: CGMouseButton = .left) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: b)?.post(tap: .cghidEventTap) }
switch a[1] {
case "move": post(.mouseMoved)
case "click": post(.mouseMoved); usleep(100_000); post(.leftMouseDown); usleep(50_000); post(.leftMouseUp)
case "rclick": post(.mouseMoved); usleep(100_000); post(.rightMouseDown, .right); usleep(50_000); post(.rightMouseUp, .right)
case "pos": print(CGEvent(source: nil)!.location)
default: break
}
