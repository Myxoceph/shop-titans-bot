// Probe: scroll wheel at a window fraction. Args: x y dy steps
import AppKit
let a = CommandLine.arguments; let x = Double(a[1])!, y = Double(a[2])!, dy = Int32(a[3])!, n = Int(a[4])!
guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.ripostegames.shopr" else { print("RED: oyun onde degil"); exit(1) }
let p = CGPoint(x: x*1470, y: 33 + y*923)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(150_000)
for _ in 0..<n { CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap); usleep(40_000) }
