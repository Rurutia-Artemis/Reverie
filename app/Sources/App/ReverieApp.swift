import AppKit
import SwiftUI

@main
struct ReverieApp {
    static let delegate = AppDelegate()
    static func main() {
        let env = ProcessInfo.processInfo.environment
        if let scene = env["REVERIE_FIXTURE"] {
            // fixture 模式：只离屏渲染，不上屏、不启动任何后台工作。
            if env["REVERIE_FONT"] == "alimama" { typeSettings.scheme = .alimama }
            if let w = env["REVERIE_FONT_WEIGHT"].flatMap(Double.init) { typeSettings.weightAdjust = w }
            if let b = env["REVERIE_FONT_BEVEL"].flatMap(Double.init) { typeSettings.bevel = b }
            if let t = env["REVERIE_THEME"].flatMap(Backdrop.init(rawValue:)) { T.palette = t.resolved(systemIsDark: true, custom: Color(hex: UInt32(env["REVERIE_CUSTOM"] ?? "", radix: 16) ?? 0x1B2A4A)) }
            let out = env["REVERIE_SNAPSHOT"] ?? "/dev/null"
            let ok = MainActor.assumeIsolated { () -> Bool in
                guard let s = FixtureScene(rawValue: scene) else { return false }
                return FixtureRenderer.render(s, to: out)
            }
            print(ok ? "snapshot written to \(out)" : "fixture render failed: \(scene)")
            exit(ok ? 0 : 1)
        }
        let app = NSApplication.shared
        app.delegate = delegate
        // 菜单栏程序：没有 Dock 图标，控制都在菜单栏和主屏的设置窗口里。
        app.setActivationPolicy(.accessory)
        if let icon = loadAppIcon() {
            app.applicationIconImage = icon
            app.dockTile.display()
        }
        app.run()
    }

    private static func loadAppIcon() -> NSImage? {
        if let bundled = Bundle.main.url(forResource: "Reverie", withExtension: "icns"),
           let image = NSImage(contentsOf: bundled) {
            return image
        }
        return NSImage(contentsOfFile: Config.projectDir + "/app/Resources/Reverie.icns")
    }
}
