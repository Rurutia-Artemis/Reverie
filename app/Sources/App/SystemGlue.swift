import AppKit
import Carbon

/// 单实例：在 Application Support 下的锁文件上加 flock，拿不到就说明已有实例在跑。
/// 进程崩溃时内核自动释放锁，新进程能重新拿到。
enum SingleInstance {
    private static var fd: Int32 = -1
    static func acquire() -> Bool {
        let dir = NSHomeDirectory() + "/Library/Application Support/Reverie"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        fd = open(dir + "/instance.lock", O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }      // 锁文件打不开时不阻止启动
        return flock(fd, LOCK_EX | LOCK_NB) == 0
    }
}

/// 全局快捷键（Carbon，不需要辅助功能权限）。
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private let id: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1, handler: @escaping () -> Void) {
        self.id = id
        if !Self.installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { HotKey.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            guard status == noErr else { return nil }
            Self.installed = true
        }
        let hkID = EventHotKeyID(signature: OSType(0x5256_5245), id: id)   // 'RVRE'
        guard RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        Self.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    /// 默认 ⌃⌥⌘R：切换音乐 / 额度。
    static let defaultKeyCode = UInt32(kVK_ANSI_R)
    static let defaultModifiers = UInt32(controlKey | optionKey | cmdKey)
}

/// 开机自启：LaunchAgent com.local.reverie。关 = disable（当前进程不退出），开 = enable 并在未加载时 bootstrap。
enum Autostart {
    static let label = "com.local.reverie"
    static var domain: String { "gui/\(getuid())" }
    static var plist: String { NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist" }

    @discardableResult
    private static func launchctl(_ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, out)
    }

    static var isLoaded: Bool { launchctl(["print", "\(domain)/\(label)"]).0 == 0 }
    static var isDisabled: Bool {
        let out = launchctl(["print-disabled", domain]).1
        return out.split(separator: "\n").contains { $0.contains("\"\(label)\"") && $0.contains("disabled") && !$0.contains("enabled") }
    }
    static var isOn: Bool { isLoaded && !isDisabled }

    static func set(_ on: Bool) {
        if on {
            launchctl(["enable", "\(domain)/\(label)"])
            // 已经手动在跑时 bootstrap 会再拉起一个实例，它拿不到锁会自己退出。
            if !isLoaded, FileManager.default.fileExists(atPath: plist) { launchctl(["bootstrap", domain, plist]) }
        } else {
            launchctl(["disable", "\(domain)/\(label)"])
        }
    }
}
