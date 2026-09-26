import Foundation
import AppKit

/// 直接问本机命令行要额度，不经过 CodexBar。两边的登录都由各自的命令行管，Reverie 不读令牌。
/// - Claude：起一个 `claude -p`，只收发控制消息 initialize / get_usage（和 /usage 同一份数据），不提问、不耗额度。
/// - Codex：起 `codex app-server`，走 JSON-RPC initialize / account/rateLimits/read。
/// 都是同步调用，放在后台队列里跑。
enum UsageProbe {
    static func claude(timeout: TimeInterval = 20) -> QuotaFetchResult {
        guard let exe = Executables.find("claude") else { return .problem(.cliMissing) }
        var env = Executables.environment(for: exe)
        env["DISABLE_AUTOUPDATER"] = "1"
        let args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                    "--strict-mcp-config", "--no-session-persistence",
                    "--settings", #"{"remoteControlAtStartup":false}"#]
        guard let s = try? LineJSONSession(executable: exe, arguments: args, environment: env, cwd: Executables.probeDirectory()) else {
            return .problem(.failed("claude 启动失败"))
        }
        defer { s.finish() }
        let deadline = Date().addingTimeInterval(timeout)

        func control(_ id: String, _ request: [String: Any]) -> [String: Any]? {
            s.send(["type": "control_request", "request_id": id, "request": request])
            let reply = s.next(until: deadline) {
                $0["type"] as? String == "control_response"
                    && ($0["response"] as? [String: Any])?["request_id"] as? String == id
            }
            return reply?["response"] as? [String: Any]
        }

        guard let ini = control("reverie-init", ["subtype": "initialize"]) else { return .problem(.failed("claude 没有响应")) }
        guard ini["subtype"] as? String == "success" else { return .problem(.failed("initialize: \(ini["error"] ?? "失败")")) }
        guard let r = control("reverie-usage", ["subtype": "get_usage", "skip_behaviors": true]) else {
            return .problem(.failed("get_usage 没有响应"))
        }
        guard r["subtype"] as? String == "success", let body = r["response"] as? [String: Any] else {
            return .problem(.failed("get_usage: \(r["error"] ?? "失败")"))
        }
        return QuotaParse.claude(body)
    }

    /// Claude 订阅倍数（20x / 5x）：命令行不给，只有钥匙串里 Claude Code 自己存的凭证项带 rateLimitTier。
    /// 用系统的 /usr/bin/security 读那一项（Claude Code 也是用它写的，所以不弹授权），只取档位字段，其余当场丢掉，不写日志。
    /// 6 小时内只读一次。
    nonisolated(unsafe) private static var tierCache: (value: String?, at: Date)?
    static func claudeTier() -> String? {
        if let c = tierCache, Date().timeIntervalSince(c.at) < 6 * 3600 { return c.value }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        p.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        var tier: String? = nil
        if (try? p.run()) != nil {
            let done = DispatchSemaphore(value: 0)
            p.terminationHandler = { _ in done.signal() }
            if done.wait(timeout: .now() + 4) == .timedOut { p.terminate() }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let oauth = obj["claudeAiOauth"] as? [String: Any] {
                tier = oauth["rateLimitTier"] as? String
            }
        }
        tierCache = (tier, Date())
        return tier
    }

    static func codex(timeout: TimeInterval = 15) -> QuotaFetchResult {
        guard let exe = Executables.find("codex") else { return .problem(.cliMissing) }
        let args = ["-s", "read-only", "-a", "never", "app-server"]
        guard let s = try? LineJSONSession(executable: exe, arguments: args, environment: Executables.environment(for: exe),
                                           cwd: Executables.probeDirectory()) else {
            return .problem(.failed("codex 启动失败"))
        }
        defer { s.finish() }
        let deadline = Date().addingTimeInterval(timeout)

        func rpc(_ id: Int, _ method: String, _ params: [String: Any]? = nil) -> [String: Any]? {
            var msg: [String: Any] = ["id": id, "method": method]
            if let params { msg["params"] = params }
            s.send(msg)
            return s.next(until: deadline) { ($0["id"] as? NSNumber)?.intValue == id }
        }

        guard let ini = rpc(1, "initialize", ["clientInfo": ["name": "reverie", "version": "1.0"]]) else {
            return .problem(.failed("codex 没有响应"))
        }
        if let e = ini["error"] { return .problem(.failed("initialize: \(e)")) }
        s.send(["method": "initialized"])
        guard let m = rpc(2, "account/rateLimits/read") else { return .problem(.failed("rateLimits 没有响应")) }
        if let e = m["error"] as? [String: Any] {
            let text = (e["message"] as? String) ?? "\(e)"
            let lower = text.lowercased()
            if ["login", "log in", "sign in", "auth", "unauthorized"].contains(where: lower.contains) { return .problem(.notLoggedIn) }
            return .problem(.failed(text))
        }
        guard let result = m["result"] as? [String: Any] else { return .problem(.failed("rateLimits 返回为空")) }
        return QuotaParse.codex(result)
    }
}

/// 找命令行：常见安装目录先找，找不到再问一次登录 shell。launchd 起的进程 PATH 只有系统目录。
enum Executables {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: URL] = [:]
    nonisolated(unsafe) private static var shellPATH: String?? = nil

    static func find(_ name: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[name], FileManager.default.isExecutableFile(atPath: hit.path) { return hit }
        let home = NSHomeDirectory()
        let common = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", home + "/.npm-global/bin",
                      home + "/.bun/bin", home + "/.volta/bin"]
        for dirs in [common, nil] {
            for dir in dirs ?? (loginShellPATH()?.split(separator: ":").map(String.init) ?? [])
            where FileManager.default.isExecutableFile(atPath: dir + "/" + name) {
                let url = URL(fileURLWithPath: dir + "/" + name)
                cache[name] = url
                return url
            }
        }
        return nil
    }

    /// 子进程的环境：只给必要的几项，不把 Reverie 自己的环境变量带过去。
    /// PATH 带上命令行所在目录（codex 是 node 脚本，要找得到同目录的 node）。
    static func environment(for exe: URL) -> [String: String] {
        let home = NSHomeDirectory()
        var path = [exe.deletingLastPathComponent().path, home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                    "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        lock.lock()
        if let extra = shellPATH ?? nil { path += extra.split(separator: ":").map(String.init) }
        lock.unlock()
        var seen = Set<String>()
        path = path.filter { seen.insert($0).inserted }
        return ["HOME": home, "USER": NSUserName(), "LOGNAME": NSUserName(), "SHELL": "/bin/zsh",
                "LANG": "en_US.UTF-8", "TMPDIR": NSTemporaryDirectory(), "PATH": path.joined(separator: ":")]
    }

    static func probeDirectory() -> URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Reverie/probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 调用方已持锁。只问一次，结果缓存。
    private static func loginShellPATH() -> String? {
        if let cached = shellPATH { return cached }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", "print -r -- \"__PATH__$PATH\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        // 不用 readDataToEndOfFile：shell 配置里起的后台进程可能一直占着管道。
        let got = NSLock()
        var data = Data()
        out.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; got.lock(); data.append(d); got.unlock() }
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        var result: String? = nil
        if (try? p.run()) != nil {
            if done.wait(timeout: .now() + 5) == .timedOut { p.terminate() }
            Thread.sleep(forTimeInterval: 0.1)
            out.fileHandleForReading.readabilityHandler = nil
            got.lock()
            let text = String(data: data, encoding: .utf8) ?? ""
            got.unlock()
            result = text.split(separator: "\n").last(where: { $0.hasPrefix("__PATH__") }).map { String($0.dropFirst(8)) }
        }
        shellPATH = .some(result)
        return result
    }
}

/// 一个按行收发 JSON 的子进程。stdout 每行一个 JSON 对象；stderr 丢掉。
final class LineJSONSession {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let cond = NSCondition()
    private var buffer = Data()
    private var inbox: [[String: Any]] = []
    private var closed = false
    private let exited = DispatchSemaphore(value: 0)

    private static let ignoreSigpipe: Void = { signal(SIGPIPE, SIG_IGN) }()   // 子进程先退出时写 stdin 不能把 Reverie 带崩

    init(executable: URL, arguments: [String], environment: [String: String], cwd: URL) throws {
        _ = Self.ignoreSigpipe
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = cwd
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = self.exited
        process.terminationHandler = { _ in exited.signal() }
        output.fileHandleForReading.readabilityHandler = { [weak self] h in self?.consume(h.availableData) }
        try process.run()
    }

    private func consume(_ data: Data) {
        cond.lock()
        defer { cond.broadcast(); cond.unlock() }
        if data.isEmpty {
            closed = true
            output.fileHandleForReading.readabilityHandler = nil
            return
        }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { inbox.append(obj) }
        }
        if buffer.count > 4 << 20 { buffer.removeAll(); closed = true }   // 一行超过 4MB 不正常，放弃
        if inbox.count > 500 { inbox.removeFirst(inbox.count - 500) }
    }

    func send(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    /// 等第一条满足条件的消息，等到截止时间或子进程关掉 stdout 就返回 nil。
    func next(until deadline: Date, where match: ([String: Any]) -> Bool) -> [String: Any]? {
        cond.lock()
        defer { cond.unlock() }
        while true {
            if let i = inbox.firstIndex(where: match) { return inbox.remove(at: i) }
            if closed { return nil }
            if !cond.wait(until: deadline) { return nil }
        }
    }

    /// 关 stdin 让它自己退出；2 秒不退发 SIGTERM，再 1 秒不退 SIGKILL。
    func finish() {
        try? input.fileHandleForWriting.close()
        guard process.isRunning else { return }
        if exited.wait(timeout: .now() + 2) == .success { return }
        process.terminate()
        if exited.wait(timeout: .now() + 1) == .success { return }
        kill(process.processIdentifier, SIGKILL)
    }
}

/// 在「终端」里打开命令行的登录（claude auth login / codex login）。
/// 写一个 .command 文件交给系统打开，不需要「自动化」授权；登录过程和浏览器授权都由命令行自己完成。
enum LoginLauncher {
    @discardableResult
    static func open(_ provider: QuotaProvider) -> Bool {
        let name = provider == .claude ? "claude" : "codex"
        guard let exe = Executables.find(name) else { return false }
        let title = provider == .claude ? "Claude Code" : "Codex"
        let args = provider == .claude ? "auth login" : "login"
        let script = """
        #!/bin/zsh -l
        export PATH="\(exe.deletingLastPathComponent().path):$PATH"
        clear
        echo "Reverie：登录 \(title) 命令行"
        echo
        "\(exe.path)" \(args)
        echo
        echo "完成后可以关掉这个窗口，Reverie 会在几分钟内自动刷新额度。"
        """
        let url = Executables.probeDirectory().appendingPathComponent("login-\(name).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch { return false }
        return NSWorkspace.shared.open(url)
    }
}
