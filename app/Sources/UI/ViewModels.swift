import SwiftUI
import AppKit

struct LyricLine: Equatable {
    let time: Double
    let text: String
    var translation: String? = nil
}

/// 从封面取出的颜色：氛围光与进度条渐变。
struct AlbumPalette: Equatable {
    var glow: Color
    var glow2: Color
    var progressStart: Color
    var progressEnd: Color
    static let neutral = AlbumPalette(glow: Color(hex: 0x7A7A86), glow2: Color(hex: 0x33404A),
                                      progressStart: Color(hex: 0xF5F5F7), progressEnd: Color(hex: 0xC7C7CC))
}

struct MusicVM {
    enum Phase: Equatable { case idle, otherApp(name: String), track }
    var phase: Phase = .idle
    var title = ""
    var artist = ""
    var album = ""
    var sourceName = ""
    var sourceDot = Color(hex: 0xE83A3A)
    var elapsed: Double = 0
    var duration: Double = 0
    var playing = false
    var liked: Bool? = nil          // nil = 这个来源不支持红心
    var artwork: NSImage? = nil
    var palette = AlbumPalette.neutral
    var backdrop: CoverBackdrop? = nil
    var lyrics: [LyricLine] = []
    var currentLine: Int? = nil
    var identity: TrackIdentity? = nil   // 界面显示的这首歌；点按钮时用它核对
    var now = Date()
    var progress: Double { duration > 0 ? min(1, max(0, elapsed / duration)) : 0 }
}

struct MusicActions {
    var prev: () -> Void = {}
    var playPause: () -> Void = {}
    var next: () -> Void = {}
    var like: () -> Void = {}
    var toggleLyrics: () -> Void = {}
}

struct QuotaCard: Identifiable, Equatable {
    enum Value: Equatable {
        case percent(used: Double, windowMinutes: Double?, resetsAt: Date?)
        case balance(amount: Double, unit: String)
        case missing
    }
    let id: String
    let provider: String      // 显示名：Claude / Codex
    let title: String
    let value: Value

    var remaining: Double? {
        if case .percent(let used, _, _) = value { return max(0, min(100, 100 - used)) }
        return nil
    }
    var used: Double? {
        if case .percent(let used, _, _) = value { return used }
        return nil
    }
    var resetsAt: Date? {
        if case .percent(_, _, let r) = value { return r }
        return nil
    }
    var isRing: Bool {
        if case .percent = value { return true }
        return value == .missing
    }
    /// 按时间应该剩下的比例与是否偏快；窗口与重置时间缺一不算。
    func pace(now: Date) -> (expectedRemaining: Double, fast: Bool)? {
        guard case .percent(let used, let w?, let r?) = value, w > 0 else { return nil }
        let left = r.timeIntervalSince(now) / 60
        guard left > 0 else { return nil }      // 已过重置时间：旧数值不再代表当前窗口
        let expected = max(0, min(1, left / w)) * 100
        return (expected, (expected - (100 - used)) > 5)
    }
}

struct QuotaVM {
    enum Status: Equatable { case ok, unavailable(String) }
    var status: Status = .ok
    var cards: [QuotaCard] = []
    var updatedMinutes: Int? = nil
    var stale: [String: Int] = [:]      // 过期的来源 → 多少分钟前
    var problems: [String: String] = [:] // 没取到数据的来源 → 原因（短句，写在卡片标题右边）
    var plans: [String: String] = [:]    // 来源 → 订阅档位（Max / Pro …），写在卡片标题旁边的小牌子上
    var now = Date()
    var showUsed = false
}

enum TimeText {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .current
    static func weekday(_ d: Date) -> String {
        var c = Calendar(identifier: .gregorian); c.timeZone = tokyo
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][c.component(.weekday, from: d) - 1]
    }
    static func hm(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = tokyo; f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    static func clock(_ d: Date) -> String { hm(d) }
    static func date(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = tokyo; f.dateFormat = "M月d日"
        return f.string(from: d) + " " + weekday(d)
    }
    /// 12 小时内写倒计时「1:42 后重置」，更远写「周日 13:00」。
    static func reset(_ at: Date?, now: Date) -> String {
        guard let at else { return "" }
        if at <= now { return "已过重置时间" }
        let mins = Int(max(0, at.timeIntervalSince(now)) / 60)
        if mins < 12 * 60 { return String(format: "%d:%02d 后重置", mins / 60, mins % 60) }
        return weekday(at) + " " + hm(at)
    }
    /// 距离某个时间还有多久：「2 天 5 小时」「3 小时 12 分」「8 分钟」。
    static func left(until at: Date, now: Date) -> String {
        let mins = Int(max(0, at.timeIntervalSince(now)) / 60)
        if mins >= 1440 { return "\(mins / 1440) 天 \(mins % 1440 / 60) 小时" }
        if mins >= 60 { return "\(mins / 60) 小时 \(mins % 60) 分" }
        return "\(mins) 分钟"
    }
    static func ago(_ minutes: Int) -> String {
        if minutes < 0 { return "未知时间" }
        if minutes < 1 { return "刚刚" }
        if minutes < 60 { return "\(minutes) 分钟前" }
        if minutes < 48 * 60 { return "\(minutes / 60) 小时前" }
        return "\(minutes / 1440) 天前"
    }
}
