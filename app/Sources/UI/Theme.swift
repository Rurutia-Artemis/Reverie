import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: a)
    }
}

/// 背景方案。夜读是 v2 定稿；石墨、夜蓝、暖炭只调底色和光晕；浅色整套反过来；跟随系统在夜读和浅色之间切。
enum Backdrop: String, CaseIterable, Identifiable {
    case night, graphite, navy, ember, light, system, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .night: return "夜读（默认）"
        case .graphite: return "石墨"
        case .navy: return "夜蓝"
        case .ember: return "暖炭"
        case .light: return "浅色"
        case .system: return "跟随系统（深色用夜读，浅色用浅色）"
        case .custom: return "自定义"
        }
    }
    func resolved(systemIsDark: Bool, custom: Color = Color(hex: 0x1B2A4A)) -> Palette {
        switch self {
        case .night: return .night
        case .graphite: return .graphite
        case .navy: return .navy
        case .ember: return .ember
        case .light: return .light
        case .system: return systemIsDark ? .night : .light
        case .custom: return .custom(custom)
        }
    }
}

/// 一套配色。界面里不直接写白色黑色，轨道、描边、分隔都用 ink（深色主题是白，浅色主题是黑）。
struct Palette: Equatable {
    var name: String
    var isLight = false
    var bg: Color
    var text = Color(hex: 0xF5F5F7)
    var text2 = Color(hex: 0x9C9CA3)
    var text3 = Color(hex: 0x6B6B72)
    var panelTop: Color
    var panelBottom: Color
    var capsuleTop: Color
    var capsuleBottom: Color
    var ink = Color.white
    var inkScale = 1.0
    var warn = Color(hex: 0xFFC04D)
    var glowWarm = 0.14
    var glowCool = 0.14
    var albumGlow = 1.0          // 封面氛围光强度倍数
    var shadow = 1.0             // 阴影强度倍数
    var panelShadow = 0.0        // 卡片投影（浅色主题靠它分层）
    var playFill = Color.white
    var playIcon = Color(hex: 0x111114)
    var bottomShade = Color.black.opacity(0.35)

    static let night = Palette(name: "night", bg: Color(hex: 0x07080A), panelTop: Color(hex: 0x17181D), panelBottom: Color(hex: 0x0E0F12),
                               capsuleTop: Color(hex: 0x1B1C22), capsuleBottom: Color(hex: 0x111216))
    static let graphite = Palette(name: "graphite", bg: Color(hex: 0x1A1B1F), panelTop: Color(hex: 0x292A30), panelBottom: Color(hex: 0x1F2025),
                                  capsuleTop: Color(hex: 0x2E2F36), capsuleBottom: Color(hex: 0x232429), glowWarm: 0.08, glowCool: 0.08)
    static let navy = Palette(name: "navy", bg: Color(hex: 0x0B1330), panelTop: Color(hex: 0x19234A), panelBottom: Color(hex: 0x111A3A),
                              capsuleTop: Color(hex: 0x1E2952), capsuleBottom: Color(hex: 0x141D40), glowWarm: 0.10, glowCool: 0.26)
    static let ember = Palette(name: "ember", bg: Color(hex: 0x1C110C), panelTop: Color(hex: 0x2D1E17), panelBottom: Color(hex: 0x21150F),
                               capsuleTop: Color(hex: 0x33231B), capsuleBottom: Color(hex: 0x261912), glowWarm: 0.26, glowCool: 0.07)
    /// 用户自己挑的底色：按亮度决定深浅文字，卡片和胶囊在底色上提亮一点。
    static func custom(_ c: Color) -> Palette {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
        let lum = 0.2126 * n.redComponent + 0.7152 * n.greenComponent + 0.0722 * n.blueComponent
        func mix(_ t: CGFloat, _ with: NSColor) -> Color { Color(nsColor: n.blended(withFraction: t, of: with) ?? n) }
        let key = String(format: "custom-%.3f-%.3f-%.3f", n.redComponent, n.greenComponent, n.blueComponent)
        if lum > 0.55 {
            return Palette(name: key, isLight: true, bg: Color(nsColor: n),
                           text: Color(hex: 0x1D1D1F), text2: Color(hex: 0x5E5E63), text3: Color(hex: 0x8E8E93),
                           panelTop: mix(0.7, .white), panelBottom: mix(0.55, .white),
                           capsuleTop: mix(0.7, .white), capsuleBottom: mix(0.5, .white),
                           ink: Color(hex: 0x1D1D1F), inkScale: 0.6, warn: Color(hex: 0xB86A00),
                           glowWarm: 0.10, glowCool: 0.10, albumGlow: 0.7, shadow: 0.3, panelShadow: 0.08,
                           playFill: Color(hex: 0x1D1D1F), playIcon: .white, bottomShade: .clear)
        }
        return Palette(name: key, bg: Color(nsColor: n),
                       panelTop: mix(0.10, .white), panelBottom: mix(0.05, .white),
                       capsuleTop: mix(0.13, .white), capsuleBottom: mix(0.07, .white),
                       glowWarm: 0.10, glowCool: 0.10)
    }

    static let light = Palette(name: "light", isLight: true, bg: Color(hex: 0xF2F1EE),
                               text: Color(hex: 0x1D1D1F), text2: Color(hex: 0x6E6E73), text3: Color(hex: 0xA1A1A6),
                               panelTop: Color(hex: 0xFFFFFF), panelBottom: Color(hex: 0xFBFBFA),
                               capsuleTop: Color(hex: 0xFFFFFF), capsuleBottom: Color(hex: 0xF5F5F4),
                               ink: Color(hex: 0x1D1D1F), inkScale: 0.6, warn: Color(hex: 0xC27400),
                               glowWarm: 0.13, glowCool: 0.11, albumGlow: 0.7, shadow: 0.3, panelShadow: 0.07,
                               playFill: Color(hex: 0x1D1D1F), playIcon: .white, bottomShade: .clear)
}

/// 视觉常量：v2 定稿（design/directions/DIRECTIONS.md）。字号只从这里取；颜色随配色走。
enum T {
    nonisolated(unsafe) static var palette = Palette.night
    /// 设置里的「主文字颜色」，只在深色配色下生效；浅色配色用它自己的深色文字。
    nonisolated(unsafe) static var customText = Color(hex: 0xF5F5F7)

    static var bg: Color { palette.bg }
    static var text: Color { palette.isLight ? palette.text : customText }
    static var text2: Color { palette.text2 }
    static var text3: Color { palette.text3 }
    /// 音乐页铺了封面色，次要文字用半透明的主文字色，灰色压在彩色上会发脏。
    static var textOnCover: Color { text.opacity(palette.isLight ? 0.62 : 0.68) }
    static var warn: Color { palette.warn }
    static var panelTop: Color { palette.panelTop }
    static var panelBottom: Color { palette.panelBottom }
    static let like = Color(hex: 0xFF375F)

    /// 轨道、描边、半透明底用的墨色；opacity 按深色主题写，浅色主题自动减淡。
    static func ink(_ opacity: Double) -> Color { palette.ink.opacity(opacity * palette.inkScale) }
    static func shadow(_ opacity: Double) -> Color { Color.black.opacity(opacity * palette.shadow) }
    /// 彩色大数字：深色主题上浅下深的渐变；浅色主题用实色，免得浅的那头看不清。
    static func numberColors(_ c1: Color, _ c2: Color) -> [Color] { palette.isLight ? [c1, c1] : [c2, c1] }
    /// 封面取色压成深色（白色播放键上的图标用），太浅的颜色也能看清。
    static func deep(_ c: Color) -> Color {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return Color(hex: 0x111114) }
        return Color(nsColor: n.blended(withFraction: 0.55, of: .black) ?? n)
    }
    /// 消费总额的颜色按金额分档：1000 以下用主文字色，往上紫、红、金、橙，5000 以上彩虹。
    static func moneyColors(_ usd: Double) -> [Color] {
        switch usd {
        case ..<1000: return [text, text]
        case ..<2000: return [Color(hex: 0xC9A2FF), Color(hex: 0x8A5CFF)]
        case ..<3000: return [Color(hex: 0xFF8A9B), Color(hex: 0xFF3B5C)]
        case ..<4000: return [Color(hex: 0xFFE68A), Color(hex: 0xF2B200)]
        case ..<5000: return [Color(hex: 0xFFB56B), Color(hex: 0xFF6A00)]
        default: return palette.isLight ? rainbowDeep : rainbow
        }
    }

    /// 彩虹：色相走一圈但饱和度压低、相邻色接近，像极光而不是七色条。浅色背景用深一点的一套。
    static let rainbow: [Color] = [
        Color(hex: 0xFF7A85), Color(hex: 0xFFB16B), Color(hex: 0xFFE07A), Color(hex: 0x8FE3A9),
        Color(hex: 0x6CC6FF), Color(hex: 0xB59BFF), Color(hex: 0xFF8FC8),
    ]
    static let rainbowDeep: [Color] = [
        Color(hex: 0xF2455A), Color(hex: 0xF28C28), Color(hex: 0xE0B400), Color(hex: 0x2FB46B),
        Color(hex: 0x2E8FE6), Color(hex: 0x8A5CF5), Color(hex: 0xE84D9B),
    ]

    /// 圆底上的图标用黑还是白。
    static func readable(on c: Color) -> Color {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return Color(hex: 0x111114) }
        let lum = 0.2126 * n.redComponent + 0.7152 * n.greenComponent + 0.0722 * n.blueComponent
        return lum > 0.6 ? Color(hex: 0x111114) : .white
    }
    static func unitColor(_ c1: Color, _ c2: Color) -> Color { (palette.isLight ? c1 : c2).opacity(0.8) }
    /// 封面取出来的颜色在浅色背景上可能太浅（进度条、波形图标），浅色主题下按亮度压暗。
    static func onBackground(_ c: Color) -> Color {
        guard palette.isLight, let n = NSColor(c).usingColorSpace(.sRGB) else { return c }
        let lum = 0.2126 * n.redComponent + 0.7152 * n.greenComponent + 0.0722 * n.blueComponent
        guard lum > 0.55 else { return c }
        return Color(nsColor: n.blended(withFraction: min(0.4, lum - 0.55), of: .black) ?? n)
    }

    enum Size {
        static let min: CGFloat = 24        // 全界面最小字号
        static let meta: CGFloat = 24
        static let clock: CGFloat = 46       // 左上角时间
        static let clockDate: CGFloat = 30   // 左上角日期
        static let artist: CGFloat = 30
        static let lyricLine: CGFloat = 30
        static let lyricNext: CGFloat = 26
        static let name: CGFloat = 30
        static let pageTitle: CGFloat = 46      // 和音乐页左上角的时间一样大，切页时左上角不跳
        static let provider: CGFloat = 32
        static let planBadge: CGFloat = 27     // 来源名旁边的订阅档位小牌
        static let title: CGFloat = 60
        static let trackTitle: CGFloat = 72     // 音乐页歌名（可点，点了进歌词模式）
        static let trackArtist: CGFloat = 36
        static let bigNumber: CGFloat = 64
        static let quotaLabel: CGFloat = 34     // 额度图例：宽卡片里的项目名
        static let quotaNumber: CGFloat = 76    // 额度图例：宽卡片里的大数字
        static let quotaHero: CGFloat = 112     // 一张卡片只有一项时，圆环中间的数字
        static let quotaHeroUnit: CGFloat = 38
        static let costNumber: CGFloat = 52     // 消费页图例里的金额
        static let costHero: CGFloat = 72       // 消费页圆环中间的总金额（不带 $）
        static let costAmount: CGFloat = 36     // 消费页图例里每个模型的金额
        static let unit: CGFloat = 28
        static let lyricCurrent: CGFloat = 56
        static let lyricOther: CGFloat = 38
        static let lyricTranslation: CGFloat = 32
        static let lyricsTitle: CGFloat = 34
        static let lyricsArtist: CGFloat = 26
        static let idleClock: CGFloat = 150
        static let idleDate: CGFloat = 34
        static let hit: CGFloat = 72        // 最小热区
    }
}

/// 额度各项的圆环颜色：Claude 暖色系，Codex 冷色系。
enum QuotaColors {
    static func colors(for id: String) -> (Color, Color) {
        switch id {
        case "claude.fiveHour": return (Color(hex: 0xFF9500), Color(hex: 0xFFC862))
        case "claude.weekly": return (Color(hex: 0xFF5A36), Color(hex: 0xFF9A6E))
        case "codex.weekly": return (Color(hex: 0x2F7BFF), Color(hex: 0x64D2FF))
        case "codex.fiveHour": return (Color(hex: 0x1FCF94), Color(hex: 0x7CF2C8))
        case "codex.codeReview": return (Color(hex: 0x14B8C8), Color(hex: 0x7EE8F0))
        case "codex.credits": return (Color(hex: 0xE8B64C), Color(hex: 0xF7D98A))
        default:
            if id.hasPrefix("claude.") { return (Color(hex: 0xFF2D6F), Color(hex: 0xFF7AA2)) }
            return (Color(hex: 0x3AA0FF), Color(hex: 0x9AD4FF))
        }
    }
}
