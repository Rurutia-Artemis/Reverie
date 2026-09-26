import SwiftUI
import AppKit

/// 定时（默认 5 分钟，设置里可改）直接问本机的 Claude Code 和 Codex 命令行要额度；翻到额度页时离上次超过 1 分钟也马上取一次。
/// 某个来源这次没取到时保留它上一次的数据，只记下原因；超过 3 个周期（至少 15 分钟）没更新，页面标过期。
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?

    /// 取到新项时回调，由设置并入「见过的项」。
    var onItemsSeen: (([QuotaItem]) -> Void)?
    /// 设置里手填的档位标签（例如「Max 20x」），非空时盖过自动取到的。
    var planOverrides: [QuotaProvider: String] = [:]

    private(set) var interval: TimeInterval = 300
    var staleAfter: TimeInterval { max(900, interval * 3) }

    private var timer: Timer?
    private var inFlight = false
    private var lastAttempt: Date?
    private var lastLogged: [QuotaProvider: QuotaProblem?] = [:]
    private let queue = DispatchQueue(label: "reverie.quota", qos: .utility)

    func start() {
        refresh()
        scheduleTimer()
    }

    func setInterval(minutes: Int) {
        let next = TimeInterval(max(1, minutes) * 60)
        guard next != interval else { return }
        interval = next
        if timer != nil { scheduleTimer() }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// 刚打开登录窗口：之后几分钟里多取几次，登录完成后尽快显示。
    func refreshSoon() {
        for delay in [20.0, 45, 90, 180] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
    }

    func refreshIfOld() {
        if let t = lastAttempt, Date().timeIntervalSince(t) < 60 { return }
        refresh()
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        lastAttempt = Date()
        queue.async { [weak self] in
            var claude = UsageProbe.claude()
            if case .items(let items, let plan?) = claude, QuotaParse.tierSuffix(plan) == nil, let x = QuotaParse.tierSuffix(UsageProbe.claudeTier()) {
                claude = .items(items, plan: plan + " " + x)
            }
            let codex = UsageProbe.codex()
            let now = Date()
            DispatchQueue.main.async {
                guard let self else { return }
                let base = self.snapshot ?? QuotaSnapshot(items: [], generatedAt: nil, updatedAt: [:])
                let next = base.merging(.claude, claude, at: now).merging(.codex, codex, at: now)
                self.snapshot = next
                self.inFlight = false
                self.logChanges(next.problems)
                if !next.items.isEmpty { self.onItemsSeen?(next.items) }
            }
        }
    }

    // MARK: 界面数据

    static func providerName(_ p: QuotaProvider) -> String { p == .claude ? "Claude" : "Codex" }

    func vm(selected: [String], titles: [String: String], showUsed: Bool, now: Date) -> QuotaVM {
        var vm = QuotaVM()
        vm.now = now
        vm.showUsed = showUsed
        guard let snap = snapshot else {
            vm.status = .unavailable("正在读取额度…")
            return vm
        }
        if snap.items.isEmpty, !snap.problems.isEmpty {
            vm.status = .unavailable(QuotaProvider.allCases.compactMap { p in snap.problems[p].map { Self.fullText($0, p) } }
                .joined(separator: "\n"))
            return vm
        }
        let perProvider = Dictionary(grouping: selected, by: { $0.split(separator: ".").first.map(String.init) ?? "" })
        let capped = selected.filter { id in
            let p = id.split(separator: ".").first.map(String.init) ?? ""
            return (perProvider[p]?.firstIndex(of: id) ?? 0) < 4
        }
        vm.cards = QuotaSelection.slots(selected: Array(capped.prefix(QuotaSelection.maxItems)), items: snap.items).compactMap { slot in
            let provider: QuotaProvider = slot.id.hasPrefix("claude.") ? .claude : .codex
            guard let item = slot.item else {
                // 来源已经回答过、只是没有这一项（例如 Codex Pro 没有 5 小时窗口）就不占位；还没取到过才留空卡位。
                if snap.updatedAt[provider] != nil { return nil }
                return QuotaCard(id: slot.id, provider: Self.providerName(provider), title: titles[slot.id] ?? Self.fallbackTitle(slot.id), value: .missing)
            }
            let value: QuotaCard.Value
            switch item.value {
            case .percent(let used, let w, let r): value = .percent(used: used, windowMinutes: w, resetsAt: r)
            case .balance(let a, let u): value = .balance(amount: a, unit: u)
            }
            return QuotaCard(id: item.id, provider: Self.providerName(item.provider), title: item.title, value: value)
        }
        for p in QuotaProvider.allCases where vm.cards.contains(where: { $0.provider == Self.providerName(p) }) {
            let stale = snap.isStale(p, now: now, after: staleAfter)
            if stale, snap.updatedAt[p] != nil {
                vm.stale[Self.providerName(p)] = snap.minutesSinceUpdate(p, now: now) ?? -1
            }
            // 要用户动手的问题一直提示；偶尔一次没取到，等数据过期了再提示。
            if let problem = snap.problems[p], problem.needsUser || stale {
                vm.problems[Self.providerName(p)] = Self.shortText(problem)
            }
        }
        for (p, plan) in snap.plans { vm.plans[Self.providerName(p)] = plan }
        for (p, plan) in planOverrides where !plan.trimmingCharacters(in: .whitespaces).isEmpty { vm.plans[Self.providerName(p)] = plan }
        if let g = snap.generatedAt { vm.updatedMinutes = max(0, Int(now.timeIntervalSince(g) / 60)) }
        return vm
    }

    /// 设置窗口里的一行状态。
    func statusText(_ p: QuotaProvider, now: Date = Date()) -> String {
        guard let snap = snapshot else { return inFlight ? "正在读取…" : "还没读取" }
        if let problem = snap.problems[p] {
            switch problem {
            case .cliMissing: return "没有找到 \(p == .claude ? "claude" : "codex") 命令行"
            case .notLoggedIn: return "命令行没有登录"
            case .failed(let m): return "最近一次没取到（\(m)）"
            }
        }
        guard let t = snap.updatedAt[p] else { return "还没读取" }
        return "已登录 · " + TimeText.ago(max(0, Int(now.timeIntervalSince(t) / 60))) + "更新"
    }

    func needsLogin(_ p: QuotaProvider) -> Bool { snapshot?.problems[p] == .notLoggedIn }

    static func shortText(_ p: QuotaProblem) -> String {
        switch p {
        case .cliMissing: return "没找到命令行"
        case .notLoggedIn: return "命令行未登录"
        case .failed: return "最近没取到数据"
        }
    }

    static func fullText(_ p: QuotaProblem, _ provider: QuotaProvider) -> String {
        let cli = provider == .claude ? "claude" : "codex"
        let name = provider == .claude ? "Claude Code" : "Codex"
        switch p {
        case .cliMissing: return "没有找到 \(name) 命令行（\(cli)）"
        case .notLoggedIn: return "\(name) 命令行没有登录，在终端运行 " + (provider == .claude ? "claude auth login" : "codex login")
        case .failed: return "\(name) 额度暂时没取到，稍后自动重试"
        }
    }

    /// 来源的问题有变化时写一行到 ~/Library/Logs/Reverie/quota.log（原文，方便排查）。
    private func logChanges(_ problems: [QuotaProvider: QuotaProblem]) {
        for p in QuotaProvider.allCases {
            let now = problems[p]
            if let last = lastLogged[p], last == now { continue }
            lastLogged[p] = .some(now)
            let text: String
            switch now {
            case nil: text = "ok"
            case .cliMissing?: text = "cli missing"
            case .notLoggedIn?: text = "not logged in"
            case .failed(let m)?: text = "failed: " + m
            }
            Self.log("\(p.rawValue) \(text)")
        }
    }

    private static func log(_ e: String) {
        let dir = NSHomeDirectory() + "/Library/Logs/Reverie"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let line = ISO8601DateFormatter().string(from: Date()) + " " + e + "\n"
        let path = dir + "/quota.log"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }

    static func fallbackTitle(_ id: String) -> String {
        if id.hasSuffix(".fiveHour") { return "5 小时" }
        if id.hasSuffix(".weekly") { return "每周" }
        if id == "codex.codeReview" { return "代码审查" }
        if id == "codex.credits" { return "Credits" }
        if id.hasPrefix("claude.row.claude-weekly-scoped-") {
            let name = String(id.dropFirst("claude.row.claude-weekly-scoped-".count))
            return name.prefix(1).uppercased() + name.dropFirst() + " 每周"
        }
        return String(id.split(separator: ".").last ?? "")
    }
}
