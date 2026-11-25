import AppKit
func k(_ d: Bool) { CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), virtualKey: 53, keyDown: d)?.post(tap: .cghidEventTap) }
k(true); usleep(800_000); k(false)
