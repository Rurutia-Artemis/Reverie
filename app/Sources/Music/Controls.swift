import AppKit
import ApplicationServices

// MARK: - Playback controls (transport via adapter `send`; favorite via NetEase ⌘L menu)
enum Controls {
    static func togglePlay() { send(2) }
    static func next() { send(4) }
    static func previous() { send(5) }
    // NetEase's 控制 menu item is "喜欢歌曲" when unliked and "取消喜欢" when liked — handle both.
    static let likeScript = """
    tell application "System Events"
      tell process "网易云音乐"
        tell menu 1 of menu bar item "控制" of menu bar 1
          if exists menu item "取消喜欢" then
            click menu item "取消喜欢"
          else
            click menu item "喜欢歌曲"
          end if
        end tell
      end tell
    end tell
    """
    static func like() { run("/usr/bin/osascript", ["-e", likeScript]) }
    // Run the menu click and report whether it actually ran (vs. blocked by missing Accessibility).
    static func likeResult() -> (ok: Bool, notAuthorized: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", likeScript]
        let err = Pipe(); p.standardError = err; p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return (false, false) }
        let e = err.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let s = String(data: e, encoding: .utf8) ?? ""
        let notAuth = s.contains("-1719") || s.contains("辅助") || s.lowercased().contains("not allowed")
        return (p.terminationStatus == 0, notAuth)
    }
    static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
    static func send(_ id: Int) { run(Config.perl, [Config.script, Config.framework, "send", String(id)]) }
    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
