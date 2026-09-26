import Foundation

// MARK: - Config (absolute paths for the prototype)
enum Config {
    static let perl = "/usr/bin/perl"
    /// 开发时从源码目录跑（没打进 .app）用的根目录：环境变量 REVERIE_PROJECT_DIR，否则当前目录。
    static let projectDir = ProcessInfo.processInfo.environment["REVERIE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath

    // Prefer resources bundled inside the .app; fall back to the project dir (dev/snapshot runs).
    private static func resolve(_ rel: String) -> String {
        if let res = Bundle.main.resourcePath {
            let bundled = res + "/" + rel
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
        }
        return projectDir + "/" + rel
    }
    static var script: String { resolve("mediaremote-adapter/bin/mediaremote-adapter.pl") }
    static var framework: String { resolve("mediaremote-adapter/build/MediaRemoteAdapter.framework") }

    /// 按名字认副屏的兜底（一般不需要：第一次运行会记住最小的那块非主屏）。可用 REVERIE_TARGET_NAME 指定。
    static let targetScreenName = ProcessInfo.processInfo.environment["REVERIE_TARGET_NAME"] ?? ""
}
