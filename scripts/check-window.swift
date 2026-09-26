import AppKit
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}
func array(_ r: CGRect) -> [Double] {
    [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)]
}
func overlaps(_ r: CGRect, _ target: CGRect, threshold: CGFloat = 8) -> Bool {
    let i = r.intersection(target)
    return !i.isNull && i.width > threshold && i.height > threshold
}
func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}
// Same candidates as WindowEvictor; standalone so `swift scripts/check-window.swift` works.
let systemOwners: Set<String> = [
    "Dock", "Window Server", "WindowServer", "Control Center", "ControlCenter",
    "Notification Center", "NotificationCenter", "SystemUIServer", "loginwindow",
    "screencaptureui", "Screenshot", "ScreenSaverEngine"
]
let systemBundleIDs: Set<String> = [
    "com.apple.dock", "com.apple.WindowManager", "com.apple.controlcenter", "com.apple.notificationcenterui",
    "com.apple.systemuiserver", "com.apple.loginwindow", "com.apple.screencaptureui", "com.apple.ScreenSaver.Engine",
    "com.apple.Spotlight", "com.apple.TextInputMenuAgent", "com.apple.TextInputSwitcher", "com.apple.wallpaper.agent"
]
let arguments = Array(CommandLine.arguments.dropFirst())
let supported = ["--assert-covers-target", "--assert-no-reverie-on-main", "--assert-target-clean"]
guard arguments.count <= 1, arguments.first.map({ supported.contains($0) }) ?? true else {
    fail("Usage: swift scripts/check-window.swift [\(supported.joined(separator: " | "))]")
}
// Target = the display Reverie remembered (settings targetDisplayUUID); before first run, the smallest non-primary one.
func uuid(_ id: CGDirectDisplayID) -> String? {
    guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, u) as String
}
let savedUUID = UserDefaults(suiteName: "com.local.reverie")?.string(forKey: "targetDisplayUUID")
let externals = NSScreen.screens.compactMap { s -> (CGDirectDisplayID, CGRect)? in
    guard let id = displayID(s), id != CGMainDisplayID() else { return nil }
    return (id, CGDisplayBounds(id))
}
let target: CGRect? = externals.first { savedUUID != nil && uuid($0.0) == savedUUID }?.1
    ?? externals.min { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?.1
let mainBounds = CGDisplayBounds(CGMainDisplayID())
guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                          kCGNullWindowID) as? [[String: Any]] else {
    fail("CGWindowListCopyWindowInfo failed; cannot determine window state")
}
struct Window {
    let app: String
    let pid: pid_t
    let bounds: CGRect
    let layer: Int
    let alpha: Double
    let onScreen: Bool
}
let windows: [Window] = info.compactMap { item in
    guard let app = item[kCGWindowOwnerName as String] as? String,
          let pid = (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
          let raw = item[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: raw),
          let layer = item[kCGWindowLayer as String] as? Int,
          let alpha = item[kCGWindowAlpha as String] as? Double else { return nil }
    return Window(app: app, pid: pid, bounds: bounds, layer: layer, alpha: alpha,
                  onScreen: item[kCGWindowIsOnscreen as String] as? Bool ?? false)
}
let reverie = windows.filter { $0.app == "Reverie" }
// The probe has its own PID; exclude the actual Reverie owners as well as this probe.
let reveriePIDs = Set(reverie.map(\.pid))
let foreign = windows.filter { window in
    guard let target else { return false }
    return window.pid != getpid() && !reveriePIDs.contains(window.pid)
        && !systemOwners.contains(window.app) && (0...24).contains(window.layer)
        && !systemBundleIDs.contains(NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier ?? "")
        && window.alpha > 0 && overlaps(window.bounds, target)
}
switch arguments.first {
case "--assert-covers-target":
    guard let target else { fail("target display not connected") }
    guard reverie.contains(where: { window in
        zip(array(window.bounds), array(target)).allSatisfy { abs($0 - $1) <= 1 }
    }) else { fail("No on-screen Reverie window covers the target display within 1 point") }
case "--assert-no-reverie-on-main":
    guard !reverie.contains(where: { overlaps($0.bounds, mainBounds, threshold: 0) }) else {
        fail("An on-screen Reverie window intersects the CGMainDisplayID display")
    }
case "--assert-target-clean":
    guard target != nil else { fail("target display not connected; cleanliness cannot be checked") }
    guard foreign.isEmpty else {
        fail("Foreign windows remain on the target display: \(foreign.map(\.app).joined(separator: ", "))")
    }
default:
    let object: [String: Any] = [
        "target": target.map { array($0) as Any } ?? NSNull(),
        "reverie": reverie.map { ["bounds": array($0.bounds), "layer": $0.layer, "onScreen": $0.onScreen] as [String: Any] },
        "foreignOnTarget": foreign.map { ["app": $0.app, "layer": $0.layer, "bounds": array($0.bounds)] as [String: Any] },
        "frontmostApp": NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    ]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
