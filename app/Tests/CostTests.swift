import Foundation

func runCostTests() {
    testPricingNormalizeAndNames()
    testPricingUSD()
    testClaudeParse()
    testCodexParse()
    testSummary()
    testSplitLines()
    print("CostTests passed")
}

private func testPricingNormalizeAndNames() {
    expectEqual(Pricing.normalize("claude-opus-5-5-20260801", provider: .claude), "claude-opus-5-5", "date suffix dropped")
    expectEqual(Pricing.normalize("anthropic.claude-sonnet-5", provider: .claude), "claude-sonnet-5", "vendor prefix dropped")
    expectEqual(Pricing.normalize("gpt-5.6", provider: .codex), "gpt-5.6-sol", "unsuffixed 5.6 is Sol")
    expectEqual(Pricing.normalize("openai/gpt-6-astra", provider: .codex), "gpt-6-astra", "openai/ prefix dropped")
    expectEqual(Pricing.displayName("claude-opus-5-5"), "Opus 5.5", "claude name")
    expectEqual(Pricing.displayName("claude-fable-5-1"), "Fable 5.1", "claude name 2")
    expectEqual(Pricing.displayName("claude-haiku-4-5"), "Haiku 4.5", "claude name 3")
    expectEqual(Pricing.displayName("gpt-6-astra"), "GPT-6 Astra", "codex name")
    expectEqual(Pricing.displayName("gpt-5.6-luna"), "GPT-5.6 Luna", "codex name 2")
    expectEqual(Pricing.displayName("chatgpt-web/medium"), "chatgpt-web/medium", "unknown stays as is")
}

private func testPricingUSD() {
    let m = 1_000_000
    expectEqual(Pricing.usd(TokenUsage(input: m), model: "claude-opus-5-5"), 4, "opus 5.5 input")
    expectEqual(Pricing.usd(TokenUsage(cacheRead: m), model: "claude-opus-5-5"), 0.2, "opus 5.5 cache read")
    expectEqual(Pricing.usd(TokenUsage(output: m), model: "claude-opus-5-5"), 20, "opus 5.5 output")
    expectEqual(Pricing.usd(TokenUsage(input: 300_000), model: "gpt-6-astra"), 6, "astra above 272K uses long-context input rate")
    expectEqual(Pricing.usd(TokenUsage(input: 200_000), model: "gpt-6-astra"), 2, "astra below threshold")
    expectEqual(Pricing.usd(TokenUsage(input: 10), model: "nope"), nil, "unknown model has no price")
}

private func testClaudeParse() {
    let a = #"{"type":"assistant","timestamp":"2026-09-25T15:30:00.000Z","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":2,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":50}}}"#
    let dup = a
    let synthetic = #"{"type":"assistant","timestamp":"2026-09-25T15:31:00Z","requestId":"r2","message":{"id":"m2","model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}"#
    let b = #"{"type":"assistant","timestamp":"2026-09-25T15:32:00Z","requestId":"r3","message":{"id":"m3","model":"claude-sonnet-5-20260101","usage":{"input_tokens":5,"output_tokens":7}}}"#
    var seen: [String] = []
    let first = CostParse.claude(lines: [a, dup, synthetic].map { Data($0.utf8) }, seen: &seen)
    expectEqual(first.count, 1, "duplicate and synthetic lines are skipped")
    expectEqual(first[0].usage, TokenUsage(input: 2, cacheWrite: 100, cacheRead: 1000, output: 50), "usage fields")
    expectEqual(first[0].model, "claude-opus-5-5", "model normalized")
    let second = CostParse.claude(lines: [dup, b].map { Data($0.utf8) }, seen: &seen)
    expectEqual(second.map(\.model), ["claude-sonnet-5"], "seen keys carry across chunks")
    expectEqual(CostParse.dayKey(first[0].date), 20260926, "15:30Z is the 26th in Tokyo")
}

private func testCodexParse() {
    let ctx = #"{"timestamp":"2026-09-25T06:24:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-luna"}}"#
    let tc = #"{"timestamp":"2026-09-25T06:24:27.932Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":30629,"cached_input_tokens":9984,"cache_write_input_tokens":0,"output_tokens":271,"reasoning_output_tokens":71,"total_tokens":30900}}}}"#
    let noModel = #"{"timestamp":"2026-09-25T06:20:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":5,"output_tokens":1}}}}"#
    var model: String? = nil
    let events = CostParse.codex(lines: [noModel, ctx, tc].map { Data($0.utf8) }, model: &model)
    expectEqual(events.count, 1, "events before any turn_context are skipped")
    expectEqual(events[0].model, "gpt-5.6-luna", "model from turn_context")
    expectEqual(events[0].usage, TokenUsage(input: 20645, cacheWrite: 0, cacheRead: 9984, output: 271), "cached tokens split out of input")
    expectEqual(model, "gpt-5.6-luna", "model state carried out")
}

private func testSummary() {
    let now = Date(timeIntervalSince1970: 1_790_400_000)     // 2026-09-26 14:20 JST
    let today = CostParse.dayKey(now)
    let rows = [
        CostRow(day: today, provider: .claude, model: "claude-opus-5-5", input: 10, usd: 3, requests: 1),
        CostRow(day: today - 1, provider: .claude, model: "claude-opus-5-5", input: 10, usd: 1, requests: 1),
        CostRow(day: today, provider: .claude, model: "claude-sonnet-5", input: 10, usd: 5, requests: 2),
        CostRow(day: 20260101, provider: .claude, model: "claude-sonnet-5", input: 10, usd: 99, requests: 1),
        CostRow(day: today, provider: .codex, model: "gpt-6-astra", input: 10, usd: 2, requests: 1),
    ]
    let s = CostSummary.build(rows: rows, period: .week, now: now)
    expectEqual(s.days.count, 7, "a week is seven days")
    expectEqual(s.days.last, today, "last day is today")
    expectEqual(s.providers.map(\.provider), [.claude, .codex], "provider order")
    expectEqual(s.providers[0].models.map(\.model), ["claude-sonnet-5", "claude-opus-5-5"], "sorted by usd desc; January row excluded")
    expectEqual(s.providers[0].total, 9, "claude total in window")
    expectEqual(s.providers[0].daily.last, 8, "today's total")
    expectEqual(s.providers[0].daily[5], 1, "yesterday")
    let m = CostSummary.build(rows: rows, period: .month, now: now)
    expectEqual(m.days.first, 20260901, "month starts on the 1st")
    expectEqual(m.days.count, 26, "26 days into September")
}

private func testSplitLines() {
    let d = Data("a\nbb\nccc".utf8)
    let (lines, consumed) = d.splitLines()
    expectEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["a", "bb"], "partial last line is held back")
    expectEqual(consumed, 5, "consumed up to the last newline")
    expectTrue(Data("x\"usage\"y".utf8).contains(ascii: "\"usage\""), "ascii contains")
}
