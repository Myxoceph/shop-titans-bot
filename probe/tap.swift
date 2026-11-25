// Probe: click one point (window fractions) in the game. Refuses unless the game is frontmost.
import AppKit
let a = CommandLine.arguments
guard a.count == 3, let fx = Double(a[1]), let fy = Double(a[2]), (0...1).contains(fx), (0...1).contains(fy) else { print("RED: arguman"); exit(1) }
guard AXIsProcessTrusted() else { print("RED: Erisilebilirlik izni yok"); exit(1) }
let bid = "com.ripostegames.shopr"
guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bid else { print("RED: oyun onde degil"); exit(1) }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let rects = list.compactMap { w -> CGRect? in
  guard w[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier, w[kCGWindowLayer as String] as? Int == 0,
        let d = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
  return CGRect(dictionaryRepresentation: d)
}
guard let r = rects.max(by: { $0.width * $0.height < $1.width * $1.height }) else { print("RED: pencere yok"); exit(1) }
let p = CGPoint(x: r.minX + fx * r.width, y: r.minY + fy * r.height)
func send(_ t: CGEventType) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
send(.mouseMoved); usleep(80_000); send(.leftMouseDown); usleep(80_000); send(.leftMouseUp); usleep(50_000)
print("TIKLANDI \(p)")
