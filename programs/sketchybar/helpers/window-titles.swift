// Emit "<windowNumber>\t<title>" for every on-screen window.
//
// WHY THIS EXISTS: OmniWM's `query windows` reports a STALE title. Renaming a
// cmux tab/session updates the real window title immediately, but OmniWM keeps
// serving the old one, so the bar kept showing "** WARNING:** Superpowers..."
// for a window the user had renamed to "rename".
//
// CoreGraphics has the live value, and its kCGWindowNumber is the SAME id as
// OmniWM's windowId (verified), which makes this a clean join on a stable key.
// Matching on the title itself is not viable: renames change it by definition,
// and several cmux windows legitimately share one title.
//
// Needs no extra TCC permission -- window NAMES require Screen Recording on
// some macOS versions, so callers must tolerate an empty title and fall back.
import CoreGraphics
import Foundation

let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    exit(0)
}
var out: [String] = []
for w in list {
    guard let num = w[kCGWindowNumber as String] as? Int else { continue }
    let name = (w[kCGWindowName as String] as? String ?? "")
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
    if !name.isEmpty { out.append("\(num)\t\(name)") }
}
if !out.isEmpty { print(out.joined(separator: "\n")) }
