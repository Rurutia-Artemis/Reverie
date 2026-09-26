// reverie:logic 纯逻辑，单元测试会编进来，不许依赖 SwiftUI / AppKit。
import Foundation

enum QuotaProvider: String, Codable, CaseIterable {
    case claude
    case codex
}

enum QuotaValue: Equatable {
    case percent(usedPercent: Double, windowMinutes: Double?, resetsAt: Date?)
    case balance(amount: Double, unit: String)
}

struct QuotaItem: Equatable, Identifiable {
    let id: String
    let provider: QuotaProvider
    let title: String
    let value: QuotaValue
}

/// 某个来源这次没取到额度的原因。
enum QuotaProblem: Equatable {
    case cliMissing          // 本机没找到命令行
    case notLoggedIn         // 命令行没登录
    case failed(String)      // 其它失败（超时、返回格式不对），原文写日志

    /// 登录、安装这类问题要用户动手，不会自己好。
    var needsUser: Bool { self == .cliMissing || self == .notLoggedIn }
}

enum QuotaFetchResult: Equatable {
    case items([QuotaItem], plan: String?)     // plan：订阅档位，例如 Max / Pro / Plus
    case problem(QuotaProblem)
}

struct QuotaSnapshot: Equatable {
    var items: [QuotaItem]
    var generatedAt: Date?
    var updatedAt: [QuotaProvider: Date]
    var problems: [QuotaProvider: QuotaProblem] = [:]
    var plans: [QuotaProvider: String] = [:]

    /// 并入一个来源这次的结果：取到了就整块换新；没取到就保留上一次的数据，只记下原因。
    func merging(_ provider: QuotaProvider, _ result: QuotaFetchResult, at now: Date) -> QuotaSnapshot {
        var next = self
        switch result {
        case .items(let fresh, let plan):
            next.items = items.filter { $0.provider != provider } + fresh
            next.updatedAt[provider] = now
            next.generatedAt = max(generatedAt ?? now, now)
            next.problems[provider] = nil
            if let plan { next.plans[provider] = plan }
        case .problem(let p):
            next.problems[provider] = p
        }
        return next
    }

    func isStale(_ provider: QuotaProvider, now: Date, after: TimeInterval = 600) -> Bool {
        guard let providerDate = updatedAt[provider],
              Self.isUsableTimestamp(providerDate, now: now, after: after),
              let generatedAt,
              Self.isUsableTimestamp(generatedAt, now: now, after: after) else {
            return true
        }
        return false
    }

    func minutesSinceUpdate(_ provider: QuotaProvider, now: Date) -> Int? {
        guard let date = updatedAt[provider] else { return nil }
        let elapsed = now.timeIntervalSince(date)
        guard elapsed.isFinite else { return nil }
        return Int(max(0, elapsed) / 60)
    }

    private static func isUsableTimestamp(_ timestamp: Date, now: Date, after: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        guard age.isFinite else { return false }
        return age >= -60 && age <= after
    }
}

/// 把命令行返回的 JSON 变成额度项。
/// - Claude：Claude Code 控制请求 `get_usage` 的回复（和 /usage 同一份数据）。
/// - Codex：`codex app-server` 的 `account/rateLimits/read` 结果。
enum QuotaParse {
    static func claude(_ response: [String: Any]) -> QuotaFetchResult {
        guard response["rate_limits_available"] as? Bool == true,
              let limits = response["rate_limits"] as? [String: Any] else {
            return .problem(.notLoggedIn)
        }
        var out: [QuotaItem] = []
        func add(_ id: String, _ title: String, minutes: Double, _ window: Any?) {
            guard let w = window as? [String: Any],
                  let used = percentage(w["utilization"]),
                  !out.contains(where: { $0.id == id }) else { return }
            out.append(QuotaItem(id: id, provider: .claude, title: title,
                                 value: .percent(usedPercent: used, windowMinutes: minutes, resetsAt: date(w["resets_at"]))))
        }
        add("claude.fiveHour", "5 小时", minutes: 300, limits["five_hour"])
        add("claude.weekly", "每周", minutes: 10080, limits["seven_day"])
        // 按模型的每周额度（例如 Fable）；id 沿用 CodexBar 的写法，已选的显示项不用重选。
        for case let m as [String: Any] in (limits["model_scoped"] as? [Any] ?? []) {
            guard let name = (m["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            add("claude.row.claude-weekly-scoped-" + slug(name), name + " 每周", minutes: 10080, m)
        }
        add("claude.row.claude-weekly-scoped-opus", "Opus 每周", minutes: 10080, limits["seven_day_opus"])
        add("claude.row.claude-weekly-scoped-sonnet", "Sonnet 每周", minutes: 10080, limits["seven_day_sonnet"])
        return .items(out, plan: planName(response["subscription_type"] as? String))
    }

    static func codex(_ result: [String: Any]) -> QuotaFetchResult {
        var buckets: [(id: String, body: [String: Any])] = []
        if let main = result["rateLimits"] as? [String: Any] {
            buckets.append(((main["limitId"] as? String) ?? "codex", main))
        }
        if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            for (key, value) in byID.sorted(by: { $0.key < $1.key }) {
                guard let body = value as? [String: Any], !buckets.contains(where: { $0.id == key }) else { continue }
                buckets.append((key, body))
            }
        }
        guard !buckets.isEmpty else { return .problem(.failed("rateLimits 缺失")) }

        var out: [QuotaItem] = []
        for bucket in buckets {
            let isMain = bucket.id == "codex"
            for key in ["primary", "secondary"] {
                guard let w = bucket.body[key] as? [String: Any],
                      let minutes = finite(w["windowDurationMins"]), minutes > 0,
                      let used = percentage(w["usedPercent"]),
                      let kind = windowKind(provider: .codex, minutes: minutes) else { continue }
                let value = QuotaValue.percent(usedPercent: used, windowMinutes: minutes, resetsAt: date(w["resetsAt"]))
                let id: String, title: String
                if isMain {
                    (id, title) = kind
                } else {
                    let name = (bucket.body["limitName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? bucket.id
                    id = "codex.row.\(slug(bucket.id))-\(Int(minutes.rounded()))"
                    title = "\(name) \(kind.title)"
                }
                guard !out.contains(where: { $0.id == id }) else { continue }
                out.append(QuotaItem(id: id, provider: .codex, title: title, value: value))
            }
        }
        if let credits = (result["rateLimits"] as? [String: Any])?["credits"] as? [String: Any],
           credits["hasCredits"] as? Bool == true,
           let balance = finite(credits["balance"]) ?? (credits["balance"] as? String).flatMap(Double.init) {
            out.append(QuotaItem(id: "codex.credits", provider: .codex, title: "Credits", value: .balance(amount: balance, unit: "credits")))
        }
        return .items(out, plan: planName((result["rateLimits"] as? [String: Any])?["planType"] as? String))
    }

    /// 订阅档位显示名：max → Max，plus → Plus。倍数（20x / 5x）来自钥匙串里的 rateLimitTier，另外补。
    static func planName(_ raw: String?, tier: String? = nil) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else { return nil }
        let known = ["max": "Max", "pro": "Pro", "plus": "Plus", "team": "Team", "enterprise": "Enterprise", "business": "Business", "free": "Free", "edu": "Edu"]
        let name = known[raw] ?? (raw.prefix(1).uppercased() + raw.dropFirst())
        if let x = tierSuffix(tier) { return name + " " + x }
        return name
    }

    /// default_claude_max_20x → 20x；没有倍数的档位返回 nil。
    static func tierSuffix(_ tier: String?) -> String? {
        guard let tier = tier?.lowercased(), let r = tier.range(of: #"(\d+)x$"#, options: .regularExpression) else { return nil }
        return String(tier[r])
    }

    static func windowKind(provider: QuotaProvider, minutes: Double) -> (id: String, title: String)? {
        if (240...360).contains(minutes) {
            return ("\(provider.rawValue).fiveHour", "5 小时")
        }
        if (9000...12000).contains(minutes) {
            return ("\(provider.rawValue).weekly", "每周")
        }

        let rounded = Int(minutes.rounded())
        guard rounded > 0 else { return nil }
        let title: String
        if rounded % 1440 == 0 {
            title = "\(rounded / 1440) 天"
        } else if rounded % 60 == 0 {
            title = "\(rounded / 60) 小时"
        } else {
            title = "\(rounded) 分钟"
        }
        return ("\(provider.rawValue).window.\(rounded)", title)
    }

    /// 小写，字母数字以外的连续字符合成一个「-」。
    static func slug(_ value: String) -> String {
        var result = ""
        var lastWasDash = false
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func finite(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              String(cString: number.objCType) != "c" else { return nil }
        let parsed = number.doubleValue
        return parsed.isFinite ? parsed : nil
    }

    static func percentage(_ value: Any?) -> Double? {
        guard let parsed = finite(value) else { return nil }
        return min(100, max(0, parsed))
    }

    static func date(_ value: Any?) -> Date? {
        if let numeric = finite(value) {
            let seconds = numeric < 1_000_000_000_000 ? numeric : numeric / 1000
            guard seconds.isFinite else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = value as? String else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: string) { return parsed }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}

struct QuotaPace: Equatable {
    let expectedRemainingPercent: Double
    let isFast: Bool
}

extension QuotaItem {
    func pace(now: Date) -> QuotaPace? {
        guard case let .percent(usedPercent, windowMinutes, resetsAt) = value,
              let windowMinutes,
              windowMinutes.isFinite,
              windowMinutes > 0,
              let resetsAt else {
            return nil
        }
        let remainingMinutes = resetsAt.timeIntervalSince(now) / 60
        guard remainingMinutes.isFinite else { return nil }
        let expectedRemaining = min(100, max(0, remainingMinutes / windowMinutes * 100))
        let actualRemaining = 100 - usedPercent
        return QuotaPace(
            expectedRemainingPercent: expectedRemaining,
            isFast: expectedRemaining - actualRemaining > 5
        )
    }

    var remainingPercent: Double? {
        guard case let .percent(usedPercent, _, _) = value else { return nil }
        return 100 - usedPercent
    }
}

enum QuotaSelection {
    static let maxItems = 6
    static let defaultIDs = ["claude.fiveHour", "claude.weekly", "codex.fiveHour", "codex.weekly"]

    static func mergeSeen(_ seen: [String], with items: [QuotaItem]) -> [String] {
        var merged = seen
        var known = Set(seen)
        for item in items where known.insert(item.id).inserted {
            merged.append(item.id)
        }
        return merged
    }

    static func toggling(_ id: String, in selected: [String]) -> [String]? {
        if selected.contains(id) {
            return selected.filter { $0 != id }
        }
        guard selected.count < maxItems else { return nil }
        return selected + [id]
    }

    static func slots(selected: [String], items: [QuotaItem]) -> [(id: String, item: QuotaItem?)] {
        selected.map { id in
            (id: id, item: items.first(where: { $0.id == id }))
        }
    }
}
