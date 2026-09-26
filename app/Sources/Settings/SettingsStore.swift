import SwiftUI
import AppKit

/// 设置存储接口：正式运行读写 UserDefaults；fixture 注入纯内存实现，不落盘。
protocol SettingsBackend: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

final class UserDefaultsBackend: SettingsBackend {
    private let d = UserDefaults.standard
    func object(forKey key: String) -> Any? { d.object(forKey: key) }
    func set(_ value: Any?, forKey key: String) { d.set(value, forKey: key) }
}

final class MemoryBackend: SettingsBackend {
    private var store: [String: Any] = [:]
    func object(forKey key: String) -> Any? { store[key] }
    func set(_ value: Any?, forKey key: String) { store[key] = value }
}

enum Page: Int, CaseIterable {
    case music = 0, quota = 1, cost = 2
    var next: Page { Page(rawValue: (rawValue + 1) % Page.allCases.count) ?? .music }
    var previous: Page { Page(rawValue: (rawValue + Page.allCases.count - 1) % Page.allCases.count) ?? .music }
}

final class SettingsStore: ObservableObject {
    private let b: SettingsBackend

    // 外观
    @Published var fontScheme: FontScheme { didSet { b.set(fontScheme.rawValue, forKey: "fontScheme"); syncType() } }
    @Published var fontWeightAdjust: Double { didSet { b.set(fontWeightAdjust, forKey: "fontWeightAdjust"); syncType() } }
    @Published var fontBevel: Double { didSet { b.set(fontBevel, forKey: "fontBevel"); syncType() } }
    @Published var japaneseFont: String { didSet { b.set(japaneseFont, forKey: "japaneseFont"); syncType() } }
    @Published var textColor: Color { didSet { persistColor(); T.customText = textColor } }
    @Published var backdrop: Backdrop { didSet { b.set(backdrop.rawValue, forKey: "backdrop"); syncPalette() } }
    /// 「自定义」背景的底色。
    @Published var customBackdrop: Color { didSet { persist(customBackdrop, "customBg"); syncPalette() } }
    /// 系统当前是不是深色外观（不存盘，由 AppDelegate 跟着系统更新）；「跟随系统」用它。
    @Published var systemIsDark = true { didSet { syncPalette() } }

    // 页面
    @Published var page: Page { didSet { b.set(page.rawValue, forKey: "currentPage") } }
    @Published var lyricsMode: Bool { didSet { b.set(lyricsMode, forKey: "lyricsMode") } }

    // 音乐
    @Published var lyricsTranslation: Bool { didSet { b.set(lyricsTranslation, forKey: "lyricsTranslation") } }
    @Published var idleShowsQuota: Bool { didSet { b.set(idleShowsQuota, forKey: "idleShowsQuota") } }

    // 播放源（允许名单，空 = 所有应用）
    @Published var allowedSources: [String] { didSet { b.set(allowedSources, forKey: "allowedSources") } }

    // 额度
    @Published var quotaSelected: [String] { didSet { b.set(quotaSelected, forKey: "quotaItems") } }
    @Published var quotaSeen: [String] { didSet { b.set(quotaSeen, forKey: "quotaSeenItems") } }
    @Published var quotaTitles: [String: String] { didSet { b.set(quotaTitles, forKey: "quotaTitles") } }
    @Published var quotaShowUsed: Bool { didSet { b.set(quotaShowUsed, forKey: "quotaShowUsed") } }
    @Published var quotaRefreshMinutes: Int { didSet { b.set(quotaRefreshMinutes, forKey: "quotaRefreshMinutes") } }

    @Published var claudePlanLabel: String { didSet { b.set(claudePlanLabel, forKey: "claudePlanLabel") } }
    @Published var codexPlanLabel: String { didSet { b.set(codexPlanLabel, forKey: "codexPlanLabel") } }

    // 消费
    @Published var costPeriod: CostPeriod { didSet { b.set(costPeriod.rawValue, forKey: "costPeriod") } }

    // 副屏
    @Published var targetDisplayUUID: String? { didSet { b.set(targetDisplayUUID, forKey: "targetDisplayUUID") } }
    @Published var evictorEnabled: Bool { didSet { b.set(evictorEnabled, forKey: "evictorEnabled") } }

    /// 默认显示项与定稿设计一致：Claude 5 小时、每周、Fable 每周；Codex 5 小时、每周。
    static let defaultQuota = ["claude.fiveHour", "claude.weekly", "claude.row.claude-weekly-scoped-fable", "codex.fiveHour", "codex.weekly"]

    init(backend: SettingsBackend = UserDefaultsBackend()) {
        b = backend
        fontScheme = FontScheme(rawValue: b.object(forKey: "fontScheme") as? String ?? "") ?? .alimama
        backdrop = Backdrop(rawValue: b.object(forKey: "backdrop") as? String ?? "") ?? .night
        customBackdrop = Color(.sRGB, red: b.object(forKey: "customBgR") as? Double ?? (0x1B / 255.0),
                               green: b.object(forKey: "customBgG") as? Double ?? (0x2A / 255.0),
                               blue: b.object(forKey: "customBgB") as? Double ?? (0x4A / 255.0))
        fontWeightAdjust = b.object(forKey: "fontWeightAdjust") as? Double ?? 0
        fontBevel = b.object(forKey: "fontBevel") as? Double ?? 60
        japaneseFont = b.object(forKey: "japaneseFont") as? String ?? "Hiragino Sans"
        let r = b.object(forKey: "textR") as? Double ?? (0xF5 / 255.0)
        let g = b.object(forKey: "textG") as? Double ?? (0xF5 / 255.0)
        let bl = b.object(forKey: "textB") as? Double ?? (0xF7 / 255.0)
        textColor = Color(.sRGB, red: r, green: g, blue: bl)
        page = Page(rawValue: b.object(forKey: "currentPage") as? Int ?? 0) ?? .music
        lyricsMode = b.object(forKey: "lyricsMode") as? Bool ?? false
        lyricsTranslation = b.object(forKey: "lyricsTranslation") as? Bool ?? false
        idleShowsQuota = b.object(forKey: "idleShowsQuota") as? Bool ?? false
        allowedSources = SourceFilterLogic.migrateAllowedSources(
            storedAllowed: b.object(forKey: "allowedSources") as? [String],
            legacyPinned: b.object(forKey: "pinnedSourceBundleID") as? String,
            legacyConfigured: b.object(forKey: "pinnedSourceConfigured") as? Bool ?? false,
            netease: SourceCatalog.neteaseBundleID, appleMusic: SourceFilterLogic.appleMusicBundleID)
        quotaSelected = b.object(forKey: "quotaItems") as? [String] ?? Self.defaultQuota
        quotaSeen = b.object(forKey: "quotaSeenItems") as? [String] ?? Self.defaultQuota
        quotaTitles = b.object(forKey: "quotaTitles") as? [String: String] ?? [:]
        quotaShowUsed = b.object(forKey: "quotaShowUsed") as? Bool ?? false
        quotaRefreshMinutes = b.object(forKey: "quotaRefreshMinutes") as? Int ?? 5
        costPeriod = CostPeriod(rawValue: b.object(forKey: "costPeriod") as? String ?? "") ?? .week
        claudePlanLabel = b.object(forKey: "claudePlanLabel") as? String ?? ""
        codexPlanLabel = b.object(forKey: "codexPlanLabel") as? String ?? ""
        targetDisplayUUID = b.object(forKey: "targetDisplayUUID") as? String
        evictorEnabled = b.object(forKey: "evictorEnabled") as? Bool ?? true
        T.customText = textColor
        syncType()
        syncPalette()
    }

    private func syncPalette() {
        T.palette = backdrop.resolved(systemIsDark: systemIsDark, custom: customBackdrop)
    }

    /// 字体、配色、文字颜色一变，副屏整棵视图重建（这些值是全局的，SwiftUI 看不出变化）。
    var renderKey: String {
        "\(T.palette.name)|\(fontScheme.rawValue)|\(fontWeightAdjust)|\(fontBevel)|\(japaneseFont)|\(textColor.description)"
    }

    private func syncType() {
        typeSettings = TypeSettings(scheme: fontScheme, weightAdjust: fontWeightAdjust, bevel: fontBevel, japanese: japaneseFont)
    }

    private func persist(_ c: Color, _ key: String) {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
        b.set(Double(n.redComponent), forKey: key + "R")
        b.set(Double(n.greenComponent), forKey: key + "G")
        b.set(Double(n.blueComponent), forKey: key + "B")
    }

    private func persistColor() {
        let n = NSColor(textColor).usingColorSpace(.sRGB) ?? .white
        b.set(Double(n.redComponent), forKey: "textR")
        b.set(Double(n.greenComponent), forKey: "textG")
        b.set(Double(n.blueComponent), forKey: "textB")
    }
}

enum FontChoices {
    static let japanese = ["Hiragino Sans", "Hiragino Mincho ProN", "YuGothic", "Klee"]
}
