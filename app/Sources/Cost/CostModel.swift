// reverie:logic 纯逻辑，单元测试会编进来，不许依赖 SwiftUI / AppKit。
import Foundation

/// 消费统计的数据模型：把本机 Claude Code / Codex 记录里的 token 按 API 价格折成美元。
/// 这是「按 API 价格要花多少」，订阅用户实际付的是月费，不是这个数。

enum CostProvider: String, Codable, CaseIterable {
    case claude, codex
}

enum CostPeriod: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var title: String { self == .week ? "7 天" : "本月" }
    var longTitle: String { self == .week ? "近 7 天" : "本月" }
}

struct TokenUsage: Equatable {
    var input = 0          // 未命中缓存的输入
    var cacheWrite = 0     // 写入缓存的输入
    var cacheRead = 0      // 命中缓存的输入
    var output = 0
    var total: Int { input + cacheWrite + cacheRead + output }
}

/// 一次模型调用。
struct CostEvent: Equatable {
    let date: Date
    let provider: CostProvider
    let model: String        // 规范化后的模型名，例如 claude-opus-5-5 / gpt-6-astra
    let usage: TokenUsage
}

// MARK: - 价格

/// 美元 / 百万 token。来源 models.dev 目录（2026-09-26 取）；超长上下文一档只有 Codex 模型有。
struct Price: Equatable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite: Double
    var longThreshold: Int? = nil      // 单次输入超过这个数，整次按下面的价
    var longInput: Double? = nil
    var longOutput: Double? = nil
    var longCacheRead: Double? = nil
    var longCacheWrite: Double? = nil
}

enum Pricing {
    static let version = "models.dev-2026-09-26"

    static let table: [String: Price] = [
        "claude-opus-5-5": Price(input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5),
        "claude-opus-5": Price(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25),
        "claude-opus-4-8": Price(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25),
        "claude-sonnet-5": Price(input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5),
        "claude-fable-5-1": Price(input: 10, output: 50, cacheRead: 0.25, cacheWrite: 12.5),
        "claude-fable-5": Price(input: 10, output: 50, cacheRead: 1, cacheWrite: 12.5),
        "claude-haiku-4-5": Price(input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25),
        "gpt-6-astra": Price(input: 10, output: 50, cacheRead: 1, cacheWrite: 12.5,
                             longThreshold: 272_000, longInput: 20, longOutput: 75, longCacheRead: 2, longCacheWrite: 25),
        "gpt-6-sol": Price(input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5,
                           longThreshold: 272_000, longInput: 4, longOutput: 15, longCacheRead: 0.4, longCacheWrite: 5),
        "gpt-6-luna": Price(input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite: 0.125,
                            longThreshold: 272_000, longInput: 0.2, longOutput: 0.75, longCacheRead: 0.02, longCacheWrite: 0.25),
        "gpt-5.6-sol": Price(input: 4, output: 20, cacheRead: 0.4, cacheWrite: 5,
                             longThreshold: 272_000, longInput: 8, longOutput: 30, longCacheRead: 0.8, longCacheWrite: 10),
        "gpt-5.6-terra": Price(input: 2, output: 12, cacheRead: 0.2, cacheWrite: 2.5,
                               longThreshold: 272_000, longInput: 4, longOutput: 18, longCacheRead: 0.4, longCacheWrite: 5),
        "gpt-5.6-luna": Price(input: 0.2, output: 1.2, cacheRead: 0.02, cacheWrite: 0.25,
                              longThreshold: 272_000, longInput: 0.4, longOutput: 1.8, longCacheRead: 0.04, longCacheWrite: 0.5),
        "gpt-5.5": Price(input: 5, output: 30, cacheRead: 0.5, cacheWrite: 6.25,
                         longThreshold: 272_000, longInput: 10, longOutput: 45, longCacheRead: 1, longCacheWrite: 12.5),
    ]

    /// 去掉厂商前缀和日期后缀，别名归到正式名。认不出的原样返回。
    static func normalize(_ raw: String, provider: CostProvider) -> String {
        var m = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch provider {
        case .claude:
            if m.hasPrefix("anthropic.") { m = String(m.dropFirst("anthropic.".count)) }
            if let r = m.range(of: #"-v\d+:\d+$"#, options: .regularExpression) { m.removeSubrange(r) }
            if let r = m.range(of: #"-\d{8}$"#, options: .regularExpression) { m.removeSubrange(r) }
        case .codex:
            if m.hasPrefix("openai/") { m = String(m.dropFirst("openai/".count)) }
            if m == "gpt-5.6" { m = "gpt-5.6-sol" }
            if m == "gpt-reserve" { m = "gpt-5.6-luna" }
        }
        return m
    }

    static func price(for model: String) -> Price? { table[model] }

    /// 一次调用的美元数；没有价格的模型返回 nil。
    static func usd(_ usage: TokenUsage, model: String) -> Double? {
        guard let p = table[model] else { return nil }
        let long = p.longThreshold.map { usage.input + usage.cacheWrite + usage.cacheRead > $0 } ?? false
        let i = long ? (p.longInput ?? p.input) : p.input
        let o = long ? (p.longOutput ?? p.output) : p.output
        let cr = long ? (p.longCacheRead ?? p.cacheRead) : p.cacheRead
        let cw = long ? (p.longCacheWrite ?? p.cacheWrite) : p.cacheWrite
        return (Double(usage.input) * i + Double(usage.output) * o + Double(usage.cacheRead) * cr + Double(usage.cacheWrite) * cw) / 1_000_000
    }

    /// 界面上的名字：claude-opus-5-5 → Opus 5.5，gpt-6-astra → GPT-6 Astra。
    static func displayName(_ model: String) -> String {
        var parts = model.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return model }
        if parts[0] == "claude" {
            parts.removeFirst()
            guard let family = parts.first else { return model }
            let version = parts.dropFirst().filter { Int($0) != nil }.joined(separator: ".")
            return family.prefix(1).uppercased() + family.dropFirst() + (version.isEmpty ? "" : " " + version)
        }
        if parts[0] == "gpt", parts.count >= 2 {
            let rest = parts.dropFirst(2).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            return "GPT-" + parts[1] + (rest.isEmpty ? "" : " " + rest)
        }
        return model
    }
}

// MARK: - 解析本机记录

/// 一个文件里解析出来的按天、按模型的汇总行。
struct CostRow: Codable, Equatable {
    var day: Int               // 东京时区的 yyyymmdd
    var provider: CostProvider
    var model: String
    var input = 0
    var cacheWrite = 0
    var cacheRead = 0
    var output = 0
    var usd = 0.0
    var requests = 0

    mutating func add(_ e: CostEvent, usd value: Double) {
        input += e.usage.input; cacheWrite += e.usage.cacheWrite; cacheRead += e.usage.cacheRead; output += e.usage.output
        usd += value; requests += 1
    }
    var tokens: Int { input + cacheWrite + cacheRead + output }
}

enum CostParse {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .current

    static func dayKey(_ d: Date) -> Int {
        var c = Calendar(identifier: .gregorian); c.timeZone = tokyo
        let p = c.dateComponents([.year, .month, .day], from: d)
        return (p.year ?? 0) * 10000 + (p.month ?? 0) * 100 + (p.day ?? 0)
    }

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]
        return g.date(from: s)
    }

    /// Claude Code 的会话记录：每条 assistant 消息带 message.usage 与 message.model。
    /// 同一条消息（message.id + requestId）会重复写好几行，只算一次；`<synthetic>` 不是模型调用。
    /// `seen` 传进来、带出去，增量解析时跨块去重。
    static func claude(lines: [Data], seen: inout [String], maxSeen: Int = 400) -> [CostEvent] {
        var out: [CostEvent] = []
        var seenSet = Set(seen)
        for line in lines {
            guard line.contains(ascii: "\"usage\""),
                  let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any],
                  let rawModel = msg["model"] as? String, !rawModel.hasPrefix("<"),
                  let ts = date(obj["timestamp"] as? String) else { continue }
            let key = ((msg["id"] as? String) ?? "") + ":" + ((obj["requestId"] as? String) ?? "")
            if key != ":" {
                if seenSet.contains(key) { continue }
                seenSet.insert(key); seen.append(key)
                if seen.count > maxSeen { seenSet.remove(seen.removeFirst()) }
            }
            let u = TokenUsage(input: int(usage["input_tokens"]), cacheWrite: int(usage["cache_creation_input_tokens"]),
                               cacheRead: int(usage["cache_read_input_tokens"]), output: int(usage["output_tokens"]))
            guard u.total > 0 else { continue }
            out.append(CostEvent(date: ts, provider: .claude, model: Pricing.normalize(rawModel, provider: .claude), usage: u))
        }
        return out
    }

    /// Codex 的会话记录：turn_context 给出当前模型，之后每个 token_count 事件的 last_token_usage 是一次请求的用量
    /// （实测各事件的 last_token_usage 加起来等于最终的 total_token_usage）。input_tokens 包含缓存部分。
    static func codex(lines: [Data], model: inout String?) -> [CostEvent] {
        var out: [CostEvent] = []
        for line in lines {
            if line.contains(ascii: "\"turn_context\"") {
                if let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], obj["type"] as? String == "turn_context",
                   let m = (obj["payload"] as? [String: Any])?["model"] as? String {
                    model = Pricing.normalize(m, provider: .codex)
                }
                continue
            }
            guard line.contains(ascii: "\"token_count\""), let model,
                  let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any],
                  let ts = date(obj["timestamp"] as? String) else { continue }
            let input = int(last["input_tokens"]), cached = int(last["cached_input_tokens"]), cw = int(last["cache_write_input_tokens"])
            let u = TokenUsage(input: max(0, input - cached - cw), cacheWrite: cw, cacheRead: cached, output: int(last["output_tokens"]))
            guard u.total > 0 else { continue }
            out.append(CostEvent(date: ts, provider: .codex, model: model, usage: u))
        }
        return out
    }

    /// 事件并成按天、按模型的行；没有价格的模型记进 unpriced，不进结果。
    static func rows(_ events: [CostEvent], unpriced: inout Set<String>) -> [CostRow] {
        var map: [String: CostRow] = [:]
        var order: [String] = []
        for e in events {
            guard let usd = Pricing.usd(e.usage, model: e.model) else { unpriced.insert(e.model); continue }
            let day = dayKey(e.date)
            let key = "\(day)|\(e.provider.rawValue)|\(e.model)"
            if map[key] == nil { map[key] = CostRow(day: day, provider: e.provider, model: e.model); order.append(key) }
            map[key]!.add(e, usd: usd)
        }
        return order.compactMap { map[$0] }
    }

    private static func int(_ v: Any?) -> Int {
        if let n = v as? NSNumber { return n.intValue }
        return 0
    }
}

extension Data {
    /// 只查 ASCII 子串，用来在 JSON 解析前快速筛行。
    func contains(ascii pattern: String) -> Bool {
        guard let p = pattern.data(using: .utf8), p.count <= count else { return false }
        return range(of: p) != nil
    }

    /// 按换行切开；最后没有换行的半行不算，返回它的起点，下次从那里接着读。
    func splitLines() -> (lines: [Data], consumed: Int) {
        var lines: [Data] = []
        var start = startIndex
        while let nl = self[start...].firstIndex(of: 0x0A) {
            if nl > start { lines.append(self[start..<nl]) }
            start = nl + 1
        }
        return (lines, start - startIndex)
    }
}

// MARK: - 汇总

struct CostSummary: Equatable {
    struct Model: Equatable {
        let model: String
        let usd: Double
        let tokens: Int
        let requests: Int
    }
    struct Provider: Equatable {
        let provider: CostProvider
        let models: [Model]        // 按金额降序
        let daily: [Double]        // 与 days 一一对应
        var total: Double { models.reduce(0) { $0 + $1.usd } }
    }
    var period: CostPeriod
    var days: [Int]                // 东京时区 yyyymmdd，从早到今天
    var providers: [Provider]      // claude, codex 顺序

    /// 从所有文件的行里算出一个周期的汇总。
    static func build(rows: [CostRow], period: CostPeriod, now: Date) -> CostSummary {
        var c = Calendar(identifier: .gregorian); c.timeZone = CostParse.tokyo
        let today = c.startOfDay(for: now)
        let first: Date
        switch period {
        case .week: first = c.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: first = c.date(from: c.dateComponents([.year, .month], from: today)) ?? today
        }
        var days: [Int] = []
        var d = first
        while d <= today {
            days.append(CostParse.dayKey(d))
            guard let next = c.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        let dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, $0) })

        var providers: [Provider] = []
        for p in CostProvider.allCases {
            var byModel: [String: (usd: Double, tokens: Int, requests: Int)] = [:]
            var daily = [Double](repeating: 0, count: days.count)
            for r in rows where r.provider == p {
                guard let i = dayIndex[r.day] else { continue }
                daily[i] += r.usd
                var m = byModel[r.model] ?? (0, 0, 0)
                m.usd += r.usd; m.tokens += r.tokens; m.requests += r.requests
                byModel[r.model] = m
            }
            var models: [Model] = []
            for (name, v) in byModel { models.append(Model(model: name, usd: v.usd, tokens: v.tokens, requests: v.requests)) }
            models.sort { a, b in
                if a.usd != b.usd { return a.usd > b.usd }
                return a.model < b.model
            }
            providers.append(Provider(provider: p, models: models, daily: daily))
        }
        return CostSummary(period: period, days: days, providers: providers)
    }
}
