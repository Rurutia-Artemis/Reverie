import SwiftUI
import AppKit

/// 确定性快照用的固定数据：固定时钟、程序画的封面、内存里的设置。
/// fixture 模式不联网、不读网易云数据库、不问 Claude Code / Codex 命令行、不请求权限、不启动适配器与驱逐器、不上屏。
enum FixtureScene: String, CaseIterable {
    case musicPlaying = "music-playing"
    case musicPaused = "music-paused"
    case musicIdle = "music-idle"
    case musicLyrics = "music-lyrics"
    case musicTranslation = "music-translation"
    case musicTranslationLyrics = "music-translation-lyrics"
    case musicOther = "music-other"
    case quotaDesign = "quota-design"
    case quotaLive = "quota-live"
    case quota1 = "quota-1"
    case quota4 = "quota-4"
    case quota6 = "quota-6"
    case quota0 = "quota-0"
    case quotaMissing = "quota-missing"
    case quotaStale = "quota-stale"
    case quotaUnavailable = "quota-unavailable"
    case costDesign = "cost-design"
}

enum Fixtures {
    /// 2026-09-25 周五 10:00 JST
    static let now = Date(timeIntervalSince1970: 1_790_298_000)

    static let palette = AlbumPalette(glow: Color(hex: 0xFF8A5B), glow2: Color(hex: 0x2E6E7A),
                                      progressStart: Color(hex: 0xFF8A5B), progressEnd: Color(hex: 0xF7C99B))

    static let lyrics: [LyricLine] = [
        LyricLine(time: 60, text: "潮水退去的时候"),
        LyricLine(time: 72, text: "我还站在原来的地方"),
        LyricLine(time: 88, text: "风把第七个夏天吹得很远"),
        LyricLine(time: 101, text: "远到听不见你的回答"),
        LyricLine(time: 115, text: "只剩下海和灯塔"),
    ]

    /// 外文歌 + 网易云翻译（歌词是为 fixture 写的，不是真实歌曲）。
    static let translated: [LyricLine] = [
        LyricLine(time: 60, text: "潮が引いていく頃", translation: "潮水退去的时候"),
        LyricLine(time: 72, text: "僕はまだ同じ場所に", translation: "我还站在原来的地方"),
        LyricLine(time: 88, text: "七度目の夏を風が運んでいく", translation: "风把第七个夏天吹得很远"),
        LyricLine(time: 101, text: "君の返事が聞こえないほど遠く", translation: "远到听不见你的回答"),
        LyricLine(time: 115, text: "残ったのは海と灯台だけ", translation: "只剩下海和灯塔"),
    ]

    @MainActor static let cover: NSImage? = {
        let r = ImageRenderer(content: FixtureCoverArt().frame(width: 1024, height: 1024))
        r.scale = 1
        return r.nsImage
    }()

    @MainActor static func music(_ scene: FixtureScene) -> MusicVM {
        var vm = MusicVM()
        vm.now = now
        switch scene {
        case .musicIdle: vm.phase = .idle; return vm
        case .musicOther: vm.phase = .otherApp(name: "Safari"); return vm
        default: break
        }
        vm.phase = .track
        let env = ProcessInfo.processInfo.environment       // 出图时可换歌名、歌手，查长标题排版
        vm.title = env["REVERIE_TITLE"] ?? "海边的第七个夏天"
        vm.artist = env["REVERIE_ARTIST"] ?? "林间 Lin Jian"
        vm.album = "Slow Tide"
        vm.sourceName = "网易云音乐"
        vm.sourceDot = Color(hex: 0xE83A3A)
        vm.elapsed = 94
        vm.duration = 246
        vm.playing = scene != .musicPaused
        vm.liked = true
        // REVERIE_COVER=图片路径 时用真实封面出图（查封面取色和背景）。
        let art = env["REVERIE_COVER"].flatMap { NSImage(contentsOfFile: $0) } ?? cover
        vm.artwork = art
        vm.backdrop = art.flatMap(CoverBackdrop.make)
        if let a = art, env["REVERIE_COVER"] != nil { vm.palette = AlbumPaletteExtractor.extract(a) ?? palette }
        vm.palette = palette
        vm.lyrics = scene == .musicTranslation || scene == .musicTranslationLyrics ? translated : lyrics
        vm.currentLine = 2
        return vm
    }

    private static func pct(_ id: String, _ provider: String, _ title: String, used: Double, window: Double, resetIn minutes: Double) -> QuotaCard {
        QuotaCard(id: id, provider: provider, title: title,
                  value: .percent(used: used, windowMinutes: window, resetsAt: now.addingTimeInterval(minutes * 60)))
    }
    static let claude5h = pct("claude.fiveHour", "Claude", "5 小时", used: 25, window: 300, resetIn: 102)
    static let claudeWeek = pct("claude.weekly", "Claude", "每周", used: 40, window: 10080, resetIn: 3060)
    static let claudeFable = pct("claude.row.fable", "Claude", "Fable 每周", used: 78, window: 10080, resetIn: 3060)
    static let codexWeek = pct("codex.weekly", "Codex", "每周", used: 31, window: 10080, resetIn: 5230)
    static let codex5h = pct("codex.fiveHour", "Codex", "5 小时", used: 52, window: 300, resetIn: 185)
    static let codex5hMissing = QuotaCard(id: "codex.fiveHour", provider: "Codex", title: "5 小时", value: .missing)
    static let codexReview = QuotaCard(id: "codex.codeReview", provider: "Codex", title: "代码审查", value: .percent(used: 35, windowMinutes: nil, resetsAt: nil))
    static let codexCredits = QuotaCard(id: "codex.credits", provider: "Codex", title: "Credits", value: .balance(amount: 0, unit: "credits"))

    /// 消费页设计稿用的示意数字（不是真实花费）。
    static func cost() -> CostVM {
        var vm = CostVM()
        vm.now = now
        vm.updatedMinutes = 2
        vm.period = .week
        // REVERIE_COST_SCALE=3.6 把示意金额整体放大，用来看各档颜色。
        let k = ProcessInfo.processInfo.environment["REVERIE_COST_SCALE"].flatMap(Double.init) ?? 1
        vm.dayLabels = ["周六", "周日", "周一", "周二", "周三", "周四", "今天"]
        vm.providers = [
            .init(name: "Claude", models: [
                .init(id: "opus55", name: "Opus 5.5", usd: 186.4 * k, tokens: 41_200_000, colors: (Color(hex: 0xFF5A36), Color(hex: 0xFF9A6E))),
                .init(id: "sonnet5", name: "Sonnet 5", usd: 92.7 * k, tokens: 58_900_000, colors: (Color(hex: 0xFF9500), Color(hex: 0xFFC862))),
                .init(id: "opus5", name: "Opus 5", usd: 78.3 * k, tokens: 21_600_000, colors: (Color(hex: 0xE0785A), Color(hex: 0xF4B299))),
                .init(id: "fable51", name: "Fable 5.1", usd: 54.9 * k, tokens: 12_400_000, colors: (Color(hex: 0xFF2D6F), Color(hex: 0xFF7AA2))),
            ], daily: [48 * k, 61 * k, 52 * k, 70 * k, 66 * k, 74 * k, 41.3 * k]),
            .init(name: "Codex", models: [
                .init(id: "astra", name: "GPT-6 Astra", usd: 61.2 * k, tokens: 24_300_000, colors: (Color(hex: 0x2F7BFF), Color(hex: 0x64D2FF))),
                .init(id: "luna56", name: "GPT-5.6 Luna", usd: 17.8 * k, tokens: 9_100_000, colors: (Color(hex: 0x5E5CE6), Color(hex: 0xA5A3FF))),
                .init(id: "luna6", name: "GPT-6 Luna", usd: 10.4 * k, tokens: 5_200_000, colors: (Color(hex: 0x1FCF94), Color(hex: 0x7CF2C8))),
                .init(id: "other", name: "其他", usd: 6.9 * k, tokens: 3_800_000, colors: (Color(hex: 0x14B8C8), Color(hex: 0x7EE8F0))),
            ], daily: [9 * k, 16 * k, 12 * k, 18 * k, 14 * k, 17 * k, 10.3 * k]),
        ]
        return vm
    }

    static func quota(_ scene: FixtureScene) -> QuotaVM {
        var vm = QuotaVM()
        vm.now = now
        vm.updatedMinutes = 2
        vm.plans = ["Claude": "Max 20x", "Codex": "Pro"]
        switch scene {
        case .quota1: vm.cards = [claudeWeek]
        case .quotaLive: vm.cards = [claude5h, claudeWeek, claudeFable, codexWeek]   // 2026-09-25 实际：Codex Pro 只有每周
        case .quota4: vm.cards = [claude5h, claudeWeek, codexWeek, codexCredits]
        case .quota6: vm.cards = [claude5h, claudeWeek, claudeFable, codexWeek, codex5h, codexReview]
        case .quota0: vm.cards = []
        case .quotaMissing:
            vm.cards = [claude5h, codex5hMissing]
            vm.problems = ["Codex": "命令行未登录"]
        case .quotaStale:
            vm.cards = [claude5h, claudeWeek, claudeFable, codexWeek, codex5hMissing]
            vm.stale = ["Claude": 570]
        case .quotaUnavailable: vm.status = .unavailable("Claude Code 命令行没有登录，在终端运行 claude auth login\nCodex 额度暂时没取到，稍后自动重试")
        default: vm.cards = [claude5h, claudeWeek, claudeFable, codexWeek, codex5hMissing]
        }
        return vm
    }
}

/// 程序画的封面：海边日落（不用真实专辑图）。
struct FixtureCoverArt: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x173F4B), Color(hex: 0x3D7A80), Color(hex: 0xE9875E), Color(hex: 0xF5CFA0)],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.62))
                Circle().fill(Color(hex: 0xFFE7C2))
                    .frame(width: w * 0.30, height: w * 0.30)
                    .position(x: w * 0.5, y: h * 0.56)
                    .shadow(color: Color(hex: 0xFFD49A, 0.8), radius: w * 0.06)
                VStack(spacing: 0) {
                    Spacer()
                    ZStack(alignment: .top) {
                        LinearGradient(colors: [Color(hex: 0x21505A), Color(hex: 0x0D2830)], startPoint: .top, endPoint: .bottom)
                        VStack(spacing: h * 0.028) {
                            ForEach(0..<6, id: \.self) { i in
                                Capsule().fill(Color(hex: 0xFFD9A8, 0.55 - Double(i) * 0.08))
                                    .frame(width: w * (0.26 - CGFloat(i) * 0.03), height: max(1.5, h * 0.006))
                            }
                        }
                        .padding(.top, h * 0.03)
                    }
                    .frame(height: h * 0.38)
                }
                Text("SLOW TIDE")
                    .font(.system(size: w * 0.045, weight: .semibold, design: .serif))
                    .tracking(w * 0.012)
                    .foregroundStyle(Color(hex: 0xFFF4E4, 0.9))
                    .padding(.top, h * 0.07)
            }
        }
    }
}

enum FixtureRenderer {
    /// 渲染一个场景到 PNG（2x），返回是否成功。
    @MainActor static func render(_ scene: FixtureScene, to path: String, scale: CGFloat = 2) -> Bool {
        let view: AnyView
        switch scene {
        case .musicPlaying, .musicPaused, .musicIdle, .musicOther:
            view = AnyView(MusicPage(vm: Fixtures.music(scene), lyricsMode: false, actions: MusicActions(), onSelectPage: { _ in }))
        case .musicLyrics:
            view = AnyView(MusicPage(vm: Fixtures.music(scene), lyricsMode: true, actions: MusicActions(), onSelectPage: { _ in }))
        case .musicTranslation:
            view = AnyView(MusicPage(vm: Fixtures.music(scene), lyricsMode: false, actions: MusicActions(), onSelectPage: { _ in }, showTranslation: true))
        case .musicTranslationLyrics:
            view = AnyView(MusicPage(vm: Fixtures.music(scene), lyricsMode: true, actions: MusicActions(), onSelectPage: { _ in }, showTranslation: true))
        case .costDesign:
            view = AnyView(CostPage(vm: Fixtures.cost(), onSelectPage: { _ in }))
        default:
            view = AnyView(QuotaPage(vm: Fixtures.quota(scene), onSelectPage: { _ in }))
        }
        // 右上角按钮组平时隐藏；REVERIE_CHROME=1 时画出来。
        let chrome = ProcessInfo.processInfo.environment["REVERIE_CHROME"] == "1"
        let r = ImageRenderer(content: view.frame(width: 1280, height: 720).environment(\.colorScheme, .dark).environment(\.chromeVisible, chrome))
        r.scale = scale
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
