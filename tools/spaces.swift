import Cocoa

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray?
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

let pid = Int32(CommandLine.arguments[1])!
let seconds = Double(CommandLine.arguments[2]) ?? 60
let cid = CGSMainConnectionID()
var last = ""
let end = Date().addingTimeInterval(seconds)
while Date() < end {
    var lines: [String] = []
    let displays = (CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]]) ?? []
    for d in displays {
        let cur = (d["Current Space"] as? [String: Any])?["ManagedSpaceID"] ?? "-"
        let type = (d["Current Space"] as? [String: Any])?["type"] ?? "-"
        lines.append("display \(d["Display Identifier"] ?? "-") currentSpace=\(cur) type=\(type)")
    }
    let infos = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) ?? []
    for w in infos where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
        let id = w[kCGWindowNumber as String] as! Int
        let spaces = (CGSCopySpacesForWindows(cid, 7, [id] as CFArray) as? [Int]) ?? []
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        lines.append("win \(id) layer=\(w[kCGWindowLayer as String] ?? "-") onscreen=\(w[kCGWindowIsOnscreen as String] ?? false) bounds=\(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0) spaces=\(spaces)")
    }
    let s = lines.joined(separator: "\n")
    if s != last { print("--- \(Date())\n\(s)"); fflush(stdout); last = s }
    Thread.sleep(forTimeInterval: 0.15)
}
