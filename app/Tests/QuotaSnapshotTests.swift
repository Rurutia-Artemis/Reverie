import Foundation

func runQuotaSnapshotTests() {
    testRealCodexRateLimits()
    testCodexExtraLimitsAndCredits()
    testCodexMissingBuckets()
    testClaudeUsage()
    testClaudeNotLoggedIn()
    testMergeKeepsLastGoodData()
    testStalenessAndFutureTimestamps()
    testPace()
    testQuotaSelection()
    print("QuotaSnapshotTests passed")
}

private func testRealCodexRateLimits() {
    // 2026-09-25 从 `codex app-server` 取到的真实回复（账号 id 已抹掉）：Pro 只有每周窗口。
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/codex-ratelimits-2026-09-25.json")
    let result = try! JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
    guard case .items(let items, let plan) = QuotaParse.codex(result) else { return fail("real Codex fixture should parse") }

    expectEqual(items.map(\.id), ["codex.weekly"], "main bucket weekly window only; duplicate limit id is skipped; no credits")
    expectEqual(plan, "Pro", "planType pro shows as Pro")
    expectEqual(items[0].title, "每周", "weekly title")
    expectEqual(items[0].value, .percent(usedPercent: 37, windowMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 1_790_611_835)),
                "epoch-second resetsAt should parse")
}

private func testCodexExtraLimitsAndCredits() {
    let result = json("""
    {"rateLimits":{"limitId":"codex","primary":{"usedPercent":-5,"windowDurationMins":300,"resetsAt":1790000000},
                   "secondary":{"usedPercent":140,"windowDurationMins":10080,"resetsAt":1790500000},
                   "credits":{"hasCredits":true,"unlimited":false,"balance":"12.5"}},
     "rateLimitsByLimitId":{
        "codex":{"limitId":"codex","primary":{"usedPercent":99,"windowDurationMins":300}},
        "codex_spark":{"limitId":"codex_spark","limitName":"GPT-6 Spark","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1790500000}}}}
    """)
    guard case .items(let items, let plan) = QuotaParse.codex(result) else { return fail("extra limits should parse") }
    expectEqual(items.map(\.id), ["codex.fiveHour", "codex.weekly", "codex.row.codex-spark-10080", "codex.credits"], "item order")
    expectEqual(items[0].remainingPercent, 100, "negative usage clamps to zero")
    expectEqual(items[1].remainingPercent, 0, "usage above 100 clamps")
    expectEqual(items[2].title, "GPT-6 Spark 每周", "named extra limit gets window label")
    expectEqual(items[3].value, .balance(amount: 12.5, unit: "credits"), "string balance parses when hasCredits")
}

private func testCodexMissingBuckets() {
    expectEqual(QuotaParse.codex([:]), .problem(.failed("rateLimits 缺失")), "missing rateLimits is a failure")
    guard case .items(let items, _) = QuotaParse.codex(json(#"{"rateLimits":{"limitId":"codex","primary":null,"secondary":null}}"#)) else {
        return fail("empty windows still parse")
    }
    expectTrue(items.isEmpty, "null windows produce no items")
}

private func testClaudeUsage() {
    // 形状按 Claude Code 2.1.263 get_usage 的回复：utilization 是 0–100，resets_at 是 ISO 8601。
    let response = json("""
    {"subscription_type":"max","rate_limits_available":true,"behaviors":null,
     "rate_limits":{"five_hour":{"utilization":14,"resets_at":"2026-09-25T17:00:00.123Z"},
                    "seven_day":{"utilization":44.5,"resets_at":"2026-09-27T03:59:00Z"},
                    "seven_day_opus":null,"seven_day_sonnet":{"utilization":null,"resets_at":null},
                    "model_scoped":[{"display_name":"Fable","utilization":42,"resets_at":"2026-09-27T03:59:00Z"},
                                    {"display_name":"  ","utilization":1,"resets_at":null}],
                    "extra_usage":null}}
    """)
    guard case .items(let items, let plan) = QuotaParse.claude(response) else { return fail("Claude usage should parse") }
    expectEqual(items.map(\.id), ["claude.fiveHour", "claude.weekly", "claude.row.claude-weekly-scoped-fable"],
                "five-hour, weekly and the Fable row keep the ids users already selected; null and blank rows are skipped")
    expectEqual(items.map(\.title), ["5 小时", "每周", "Fable 每周"], "titles")
    expectEqual(plan, "Max", "subscription_type max shows as Max")
    expectEqual(items[0].value, .percent(usedPercent: 14, windowMinutes: 300, resetsAt: isoFractional("2026-09-25T17:00:00.123Z")),
                "fractional ISO timestamps parse")
    expectEqual(items[2].value, .percent(usedPercent: 42, windowMinutes: 10080, resetsAt: iso("2026-09-27T03:59:00Z")), "Fable weekly")
}

private func testClaudeNotLoggedIn() {
    // 命令行没登录时 Claude Code 照样回 success，只是 rate_limits_available 为 false。
    let response = json(#"{"subscription_type":null,"rate_limits_available":false,"rate_limits":null,"behaviors":null}"#)
    expectEqual(QuotaParse.claude(response), .problem(.notLoggedIn), "unavailable limits mean not logged in")
    expectEqual(QuotaParse.claude([:]), .problem(.notLoggedIn), "empty response is treated the same")
    expectEqual(QuotaParse.planName("max", tier: "default_claude_max_20x"), "Max 20x", "tier multiplier appended")
    expectEqual(QuotaParse.planName("max", tier: "default_claude_max"), "Max", "no multiplier in tier")
    expectEqual(QuotaParse.planName("pro", tier: nil), "Pro", "codex plan")
    expectEqual(QuotaParse.tierSuffix("default_claude_max_5x"), "5x", "5x")
}

private func testMergeKeepsLastGoodData() {
    let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    let week = QuotaItem(id: "claude.weekly", provider: .claude, title: "每周", value: .percent(usedPercent: 40, windowMinutes: 10080, resetsAt: nil))
    let codex = QuotaItem(id: "codex.weekly", provider: .codex, title: "每周", value: .percent(usedPercent: 10, windowMinutes: 10080, resetsAt: nil))
    var snap = QuotaSnapshot(items: [], generatedAt: nil, updatedAt: [:])
    snap = snap.merging(.claude, .items([week], plan: "Max"), at: t0).merging(.codex, .items([codex], plan: nil), at: t0)
    expectEqual(snap.items.map(\.id), ["claude.weekly", "codex.weekly"], "both providers merge")
    expectEqual(snap.generatedAt, t0, "generatedAt follows the latest success")
    expectEqual(snap.plans[.claude], "Max", "plan recorded")

    let t1 = t0.addingTimeInterval(300)
    let later = snap.merging(.claude, .problem(.failed("timeout")), at: t1)
    expectEqual(later.items, snap.items, "a failed fetch keeps the previous data")
    expectEqual(later.updatedAt[.claude], t0, "a failed fetch does not bump updatedAt")
    expectEqual(later.problems[.claude], .failed("timeout"), "the failure is recorded")

    let week2 = QuotaItem(id: "claude.weekly", provider: .claude, title: "每周", value: .percent(usedPercent: 41, windowMinutes: 10080, resetsAt: nil))
    let recovered = later.merging(.claude, .items([week2], plan: nil), at: t1)
    expectEqual(recovered.items.map(\.value), [codex.value, week2.value], "a success replaces only that provider's items")
    expectEqual(recovered.problems[.claude], nil, "a success clears the problem")
    expectEqual(recovered.plans[.claude], "Max", "a success without plan keeps the old plan")
    expectFalse(recovered.isStale(.claude, now: t1.addingTimeInterval(899), after: 900), "fresh within 15 minutes")
    expectTrue(recovered.isStale(.codex, now: t1.addingTimeInterval(700), after: 900), "Codex last updated at t0 is stale after 15 minutes")
    expectTrue(QuotaProblem.notLoggedIn.needsUser && !QuotaProblem.failed("x").needsUser, "only login and install problems need the user")
}

private func testStalenessAndFutureTimestamps() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let current = QuotaSnapshot(items: [], generatedAt: now, updatedAt: [.codex: now.addingTimeInterval(-600)])
    expectFalse(current.isStale(.codex, now: now), "exactly ten minutes old should not yet be stale")
    expectEqual(current.minutesSinceUpdate(.codex, now: now), 10, "minutesSinceUpdate should use fixed dates")

    let future = QuotaSnapshot(items: [], generatedAt: now, updatedAt: [.codex: now.addingTimeInterval(61)])
    expectTrue(future.isStale(.codex, now: now), "timestamps more than a minute in the future should be stale")
    expectEqual(future.minutesSinceUpdate(.codex, now: now), 0, "future timestamps should not report negative minutes")
}

private func testPace() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let boundary = QuotaItem(
        id: "boundary",
        provider: .claude,
        title: "Boundary",
        value: .percent(usedPercent: 55, windowMinutes: 100, resetsAt: now.addingTimeInterval(50 * 60))
    )
    expectEqual(boundary.pace(now: now), QuotaPace(expectedRemainingPercent: 50, isFast: false), "exactly five points should not be fast")

    let fast = QuotaItem(
        id: "fast",
        provider: .claude,
        title: "Fast",
        value: .percent(usedPercent: 55.1, windowMinutes: 100, resetsAt: now.addingTimeInterval(50 * 60))
    )
    expectEqual(fast.pace(now: now), QuotaPace(expectedRemainingPercent: 50, isFast: true), "5.1 points should be fast")

    let noWindow = QuotaItem(
        id: "no-window",
        provider: .codex,
        title: "No window",
        value: .percent(usedPercent: 50, windowMinutes: nil, resetsAt: now)
    )
    expectEqual(noWindow.pace(now: now), nil, "pace should require both window length and reset time")
    let balance = QuotaItem(id: "balance", provider: .codex, title: "Credits", value: .balance(amount: 1, unit: "credits"))
    expectEqual(balance.remainingPercent, nil, "balances should not have a remaining percentage")
}

private func testQuotaSelection() {
    let first = QuotaItem(id: "new-a", provider: .claude, title: "A", value: .percent(usedPercent: 1, windowMinutes: nil, resetsAt: nil))
    let second = QuotaItem(id: "new-b", provider: .codex, title: "B", value: .balance(amount: 2, unit: "credits"))
    expectEqual(
        QuotaSelection.mergeSeen(["old", "new-b"], with: [first, second]),
        ["old", "new-b", "new-a"],
        "mergeSeen should preserve old order and append only new ids"
    )

    let six = ["1", "2", "3", "4", "5", "6"]
    expectEqual(QuotaSelection.toggling("7", in: six), nil, "a seventh selection should be rejected")
    expectEqual(QuotaSelection.toggling("3", in: six), ["1", "2", "4", "5", "6"], "selected items should still be removable at the limit")
    expectEqual(QuotaSelection.toggling("new", in: ["old"]), ["old", "new"], "new selections should append in checked order")

    let slots = QuotaSelection.slots(selected: ["new-b", "missing", "new-a"], items: [first, second])
    expectEqual(slots.map(\.id), ["new-b", "missing", "new-a"], "slots should preserve selection order")
    expectEqual(slots[0].item, second, "slots should carry matching data")
    expectEqual(slots[1].item, nil, "slots should retain missing selections as nil")
    expectEqual(slots[2].item, first, "later matching slots should retain data")
}

private func json(_ value: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(value.utf8)) as! [String: Any]
}

private func fail(_ message: String) {
    expectTrue(false, message)
}

private func iso(_ value: String) -> Date? {
    ISO8601DateFormatter().date(from: value)
}

private func isoFractional(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}
