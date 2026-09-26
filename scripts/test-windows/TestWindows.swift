import AppKit
import CoreGraphics
import Foundation

func usage() -> Never {
    fputs("Usage: swift scripts/test-windows/TestWindows.swift --mode floating|immovable --x N --y N (CG points)\n", stderr)
    exit(1)
}
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 6 else { usage() }
var options: [String: String] = [:]
for index in stride(from: 0, to: arguments.count, by: 2) {
    let key = arguments[index]
    guard ["--mode", "--x", "--y"].contains(key), options[key] == nil else { usage() }
    options[key] = arguments[index + 1]
}
guard let mode = options["--mode"], ["floating", "immovable"].contains(mode),
      let x = Double(options["--x"] ?? ""), x.isFinite,
      let y = Double(options["--y"] ?? ""), y.isFinite else { usage() }

final class TestWindowDelegate: NSObject, NSWindowDelegate {
    let anchor: CGPoint
    let immovable: Bool
    var restoring = false
    var clicks = 0
    init(anchor: CGPoint, immovable: Bool) {
        self.anchor = anchor
        self.immovable = immovable
    }
    func windowDidMove(_ notification: Notification) {
        guard immovable, !restoring, let window = notification.object as? NSWindow,
              window.frame.origin != anchor else { return }
        restoring = true
        window.setFrameOrigin(anchor)
        restoring = false
    }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    @objc func clicked(_ sender: NSButton) {
        clicks += 1
        sender.title = "Clicked \(clicks)"
        print("\(clicks) click(s) received")
        fflush(stdout)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
// Main-screen height in points, never pixel dimensions or NSScreen.main (focus dependent).
let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
let frame = CGRect(x: x, y: Double(primaryHeight) - y - 300, width: 400, height: 300)
let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable],
                      backing: .buffered, defer: false)
// setFrame fixes the outer window to 400x300, including its title bar.
window.setFrame(frame, display: false)
window.title = mode
window.level = mode == "floating" ? .floating : .normal
window.isReleasedWhenClosed = false
let delegate = TestWindowDelegate(anchor: frame.origin, immovable: mode == "immovable")
window.delegate = delegate
let button = NSButton(title: "Test click", target: delegate, action: #selector(TestWindowDelegate.clicked(_:)))
button.frame = CGRect(x: 90, y: 90, width: 220, height: 60)
button.setAccessibilityIdentifier("test-click")
window.contentView?.addSubview(button)
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
// AppKit may constrain the initial frame during presentation; restore the requested CG origin.
window.setFrame(frame, display: true)
let expiry = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: false) { _ in NSApp.terminate(nil) }
RunLoop.main.add(expiry, forMode: .common)
app.run()
