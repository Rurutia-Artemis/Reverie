// Reverie 视觉样稿 v2：在甲「夜读」上加深。
// 用法：
//   Directions render <outdir>   每张出 1x 与 2x 两张 PNG
//   Directions show               铺到 Wokyis 上看：左键下一张，右键上一张，Esc 退出
import SwiftUI
import AppKit

// MARK: - Fixture（固定时钟：2026-09-25 周五 10:00）

struct Track {
    let title = "海边的第七个夏天"
    let artist = "林间 Lin Jian"
    let album = "Slow Tide"
    let source = "网易云音乐"
    let elapsed: Double = 94
    let duration: Double = 246
    let liked = true
    var progress: Double { elapsed / duration }
    let lyrics = ["潮水退去的时候", "我还站在原来的地方", "风把第七个夏天吹得很远", "远到听不见你的回答", "只剩下海和灯塔"]
    let currentLine = 2
}

struct Quota: Identifiable {
    let id = UUID()
    let provider: String
    let name: String
    let used: Double?            // nil = 暂无数据
    let windowMin: Double
    let resetsInMin: Double
    let resetAt: String          // 时间线上的标签
    let resetText: String
    let c1: Color                // 圆环渐变起点
    let c2: Color                // 圆环渐变终点
    var remaining: Double? { used.map { 100 - $0 } }
    var expectedRemaining: Double { max(0, min(1, resetsInMin / windowMin)) * 100 }
    var fast: Bool { guard let r = remaining else { return false }; return expectedRemaining - r > 5 }
}

extension Color {
    init(hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: a)
    }
}

let track = Track()
let claude: [Quota] = [
    Quota(provider: "Claude", name: "5 小时", used: 25, windowMin: 300, resetsInMin: 102, resetAt: "11:42",
          resetText: "1:42 后重置", c1: Color(hex: 0xFF9500), c2: Color(hex: 0xFFC862)),
    Quota(provider: "Claude", name: "每周", used: 40, windowMin: 10080, resetsInMin: 3060, resetAt: "周日 13:00",
          resetText: "周日 13:00", c1: Color(hex: 0xFF5A36), c2: Color(hex: 0xFF9A6E)),
    Quota(provider: "Claude", name: "Fable 每周", used: 78, windowMin: 10080, resetsInMin: 3060, resetAt: "周日 13:00",
          resetText: "周日 13:00", c1: Color(hex: 0xFF2D6F), c2: Color(hex: 0xFF7AA2)),
]
let codex: [Quota] = [
    Quota(provider: "Codex", name: "每周", used: 31, windowMin: 10080, resetsInMin: 5230, resetAt: "周二 01:10",
          resetText: "周二 01:10", c1: Color(hex: 0x2F7BFF), c2: Color(hex: 0x64D2FF)),
    Quota(provider: "Codex", name: "5 小时", used: nil, windowMin: 300, resetsInMin: 0, resetAt: "",
          resetText: "暂无数据", c1: Color(hex: 0x1FCF94), c2: Color(hex: 0x7CF2C8)),
]

func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

// MARK: - Tokens

enum T {
    static let bg = Color(hex: 0x07080A)
    static let text = Color(hex: 0xF5F5F7)
    static let text2 = Color(hex: 0x9C9CA3)
    static let text3 = Color(hex: 0x6B6B72)
    static let coral = Color(hex: 0xFF8A5B)
    static let sand = Color(hex: 0xF7C99B)
    static let teal = Color(hex: 0x2E6E7A)
    static let like = Color(hex: 0xFF375F)
    static let warn = Color(hex: 0xFFC04D)
    static func r(_ s: CGFloat, _ w: Font.Weight = .bold) -> Font { .system(size: s, weight: w, design: .rounded) }
    static func yuan(_ s: CGFloat, bold: Bool = true) -> Font { .custom(bold ? "STYuanti-SC-Bold" : "STYuanti-SC-Regular", size: s) }
}

func isCJK(_ c: Character) -> Bool {
    c.unicodeScalars.contains { (0x2E80...0x9FFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value) }
}

// 中文用圆体，拉丁与数字用 SF Pro Rounded。
func tx(_ s: String, _ size: CGFloat, bold: Bool = true, weight: Font.Weight? = nil, cjkTracking: CGFloat = 0) -> Text {
    var out = AttributedString()
    var run = ""
    var runCJK: Bool? = nil
    func flush() {
        guard !run.isEmpty, let c = runCJK else { return }
        var a = AttributedString(run)
        a.font = c ? T.yuan(size, bold: bold) : T.r(size, weight ?? (bold ? .bold : .semibold))
        if c { a.tracking = cjkTracking }
        out += a
        run = ""
    }
    for ch in s {
        let c = isCJK(ch)
        if runCJK == nil { runCJK = c }
        if c != runCJK { flush(); runCJK = c }
        run.append(ch)
    }
    flush()
    return Text(out)
}

// MARK: - Surfaces

struct Panel: View {
    var radius: CGFloat = 32
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x17181D), Color(hex: 0x0E0F12)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

struct CapsulePanel: View {
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(hex: 0x1B1C22), Color(hex: 0x111216)], startPoint: .top, endPoint: .bottom))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

struct PageSwitch: View {
    let active: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(["音乐", "额度"].enumerated()), id: \.offset) { i, name in
                tx(name, 24, bold: i == active)
                    .foregroundStyle(i == active ? T.text : T.text2)
                    .padding(.horizontal, 22).padding(.vertical, 7)
                    .background(Capsule().fill(i == active ? Color.white.opacity(0.14) : .clear))
            }
        }
        .padding(5)
        .background(CapsulePanel())
    }
}

struct TopBar<Left: View>: View {
    let active: Int
    @ViewBuilder var left: Left
    var body: some View {
        HStack(alignment: .center) {
            left
            Spacer()
            PageSwitch(active: active)
        }
        .padding(.horizontal, 56)
        .frame(height: 56)
        .padding(.top, 24)
    }
}

struct ClockLabel: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("10:00").font(T.r(30, .bold)).monospacedDigit().foregroundStyle(T.text)
            tx("9月25日 周五", 24, bold: false).foregroundStyle(T.text2)
        }
    }
}

// 程序画的封面：海边日落。
struct CoverArt: View {
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

struct Cover: View {
    let side: CGFloat
    var radius: CGFloat = 32
    var body: some View {
        CoverArt()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 24, y: 18)
            .shadow(color: T.coral.opacity(0.28), radius: 60, y: 10)
    }
}

// 封面颜色洇出来的氛围光，只在封面周围，不铺满全屏。
struct AlbumGlow: View {
    var center = UnitPoint(x: 0.25, y: 0.56)
    var body: some View {
        ZStack {
            T.bg
            RadialGradient(colors: [T.coral.opacity(0.30), T.coral.opacity(0.08), .clear], center: center, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [T.teal.opacity(0.35), .clear], center: UnitPoint(x: center.x - 0.12, y: center.y - 0.42), startRadius: 0, endRadius: 520)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
        }
        .frame(width: 1280, height: 720)
    }
}

// MARK: - 播放控制

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 84
    var icon: CGFloat = 34
    var body: some View {
        Image(systemName: symbol).font(.system(size: icon, weight: .bold)).foregroundStyle(T.text)
            .frame(width: size, height: size)
    }
}

struct PlayButton: View {
    var size: CGFloat = 92
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.white, Color(hex: 0xE4E4E8)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
            Image(systemName: "pause.fill").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(Color(hex: 0x111114))
        }
        .frame(width: size, height: size)
    }
}

struct LikeButton: View {
    var size: CGFloat = 92
    var body: some View {
        ZStack {
            Circle().fill(T.like.opacity(0.16)).overlay(Circle().strokeBorder(T.like.opacity(0.35), lineWidth: 1))
                .shadow(color: T.like.opacity(0.35), radius: 18)
            Image(systemName: "heart.fill").font(.system(size: size * 0.40, weight: .bold)).foregroundStyle(T.like)
        }
        .frame(width: size, height: size)
    }
}

struct ProgressBar: View {
    var height: CGFloat = 8
    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { g in
                let x = g.size.width * track.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(LinearGradient(colors: [T.coral, T.sand], startPoint: .leading, endPoint: .trailing))
                        .frame(width: x)
                        .shadow(color: T.coral.opacity(0.6), radius: 8)
                    Circle().fill(.white).frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                        .offset(x: x - 9)
                }
            }
            .frame(height: height)
            HStack {
                Text(fmt(track.elapsed)); Spacer(); Text("-" + fmt(track.duration - track.elapsed))
            }
            .font(T.r(24, .semibold).monospacedDigit()).foregroundStyle(T.text2)
        }
    }
}

// MARK: - 音乐页

struct MusicPage: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            AlbumGlow()
            TopBar(active: 0) { ClockLabel() }
            HStack(alignment: .top, spacing: 56) {
                Cover(side: 528)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Circle().fill(Color(hex: 0xE83A3A)).frame(width: 12, height: 12)
                        tx(track.source, 24, bold: false).foregroundStyle(T.text2)
                        Text("·").font(T.r(24)).foregroundStyle(T.text3)
                        tx("正在播放", 24, bold: false).foregroundStyle(T.text2)
                    }
                    tx(track.title, 60, cjkTracking: -1.5)
                        .foregroundStyle(T.text).lineLimit(2).padding(.top, 20)
                    HStack(spacing: 0) {
                        tx(track.artist, 30).foregroundStyle(Color(hex: 0xD8D8DD))
                        tx("  ·  " + track.album, 30, bold: false).foregroundStyle(T.text2)
                    }
                    .lineLimit(1).padding(.top, 12)
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            Image(systemName: "waveform").font(.system(size: 26, weight: .bold)).foregroundStyle(T.coral)
                            tx(track.lyrics[track.currentLine], 30).foregroundStyle(T.text.opacity(0.92))
                        }
                        tx(track.lyrics[track.currentLine + 1], 26, bold: false).foregroundStyle(T.text3)
                            .padding(.leading, 44)
                    }
                    ProgressBar().padding(.top, 30)
                    HStack(spacing: 0) {
                        HStack(spacing: 10) {
                            IconButton(symbol: "backward.fill")
                            PlayButton()
                            IconButton(symbol: "forward.fill")
                        }
                        .padding(8)
                        .background(CapsulePanel())
                        Spacer()
                        LikeButton()
                    }
                    .padding(.top, 26)
                }
                .frame(width: 560, height: 528, alignment: .leading)
            }
            .padding(.leading, 56).padding(.top, 128)
        }
        .frame(width: 1280, height: 720)
    }
}

// 歌词模式：封面缩小，歌词做主角，控制收到底部一条。
struct LyricsPage: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            AlbumGlow(center: UnitPoint(x: 0.18, y: 0.45))
            TopBar(active: 0) { ClockLabel() }
            HStack(alignment: .top, spacing: 64) {
                VStack(alignment: .leading, spacing: 0) {
                    Cover(side: 360, radius: 26)
                    tx(track.title, 34, cjkTracking: -0.5).foregroundStyle(T.text).lineLimit(1).padding(.top, 30)
                    tx(track.artist, 26, bold: false).foregroundStyle(T.text2).lineLimit(1).padding(.top, 8)
                }
                .frame(width: 360, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(track.lyrics.enumerated()), id: \.offset) { i, line in
                        let d = abs(i - track.currentLine)
                        if d == 0 {
                            tx(line, 50, cjkTracking: -1).foregroundStyle(T.text)
                                .shadow(color: T.coral.opacity(0.35), radius: 16)
                                .frame(height: 92, alignment: .leading)
                        } else {
                            tx(line, 32, bold: false).foregroundStyle(T.text.opacity(d == 1 ? 0.42 : 0.2))
                                .frame(height: 64, alignment: .leading)
                        }
                    }
                }
                .frame(width: 744, height: 440, alignment: .leading)
                .padding(.top, 8)
            }
            .padding(.leading, 56).padding(.top, 128)
            // 底部细栏：进度 + 控制
            HStack(spacing: 28) {
                ProgressBar(height: 6).frame(width: 520)
                Spacer()
                HStack(spacing: 6) {
                    IconButton(symbol: "backward.fill", size: 72, icon: 28)
                    PlayButton(size: 72)
                    IconButton(symbol: "forward.fill", size: 72, icon: 28)
                }
                .padding(6).background(CapsulePanel())
                LikeButton(size: 72)
            }
            .padding(.horizontal, 56)
            .frame(width: 1280)
            .offset(y: 610)
        }
        .frame(width: 1280, height: 720)
    }
}

// MARK: - 额度页

struct Ring: View {
    let q: Quota
    let diameter: CGFloat
    let line: CGFloat
    var body: some View {
        let frac = (q.remaining ?? 0) / 100
        let r = diameter / 2
        ZStack {
            if q.remaining == nil {
                Circle().stroke(q.c1.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 10]))
            } else {
                Circle().stroke(q.c1.opacity(0.16), lineWidth: line)
                Circle().trim(from: 0, to: frac)
                    .stroke(AngularGradient(colors: [q.c1, q.c2], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * frac)),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: q.c1.opacity(0.45), radius: 10)
                // 末端圆头的投影，模仿活动圆环的立体端点
                let a = (-90 + 360 * frac) * .pi / 180
                Circle().fill(q.c2).frame(width: line, height: line)
                    .shadow(color: .black.opacity(0.55), radius: 5, x: 3 * cos(a + .pi / 2), y: 3 * sin(a + .pi / 2))
                    .offset(x: r * cos(a), y: r * sin(a))
                // 白点：按时间应该剩下的位置
                let p = (-90 + 360 * q.expectedRemaining / 100) * .pi / 180
                Circle().fill(.white).frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .offset(x: r * cos(p), y: r * sin(p))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

struct LegendRow: View {
    let q: Quota
    var body: some View {
        if q.remaining == nil {
            HStack(spacing: 16) {
                Capsule().fill(q.c1.opacity(0.35)).frame(width: 8, height: 36)
                tx(q.name, 30).foregroundStyle(T.text2).fixedSize()
                Spacer()
                tx(q.resetText, 24, bold: false).foregroundStyle(T.text3).fixedSize()
            }
        } else {
            full
        }
    }
    var full: some View {
        HStack(alignment: .center, spacing: 16) {
            Capsule().fill(LinearGradient(colors: [q.c1, q.c2], startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: 78)
                .opacity(q.remaining == nil ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline) {
                    tx(q.name, 30).foregroundStyle(q.remaining == nil ? T.text2 : T.text).fixedSize()
                    Spacer(minLength: 8)
                    if let rem = q.remaining {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(Int(rem))").font(T.r(64, .heavy)).monospacedDigit()
                            Text("%").font(T.r(28, .bold)).foregroundStyle(q.c2.opacity(0.8))
                        }
                        .foregroundStyle(LinearGradient(colors: [q.c2, q.c1], startPoint: .top, endPoint: .bottom))
                        .fixedSize()
                    }
                }
                .frame(height: 58)
                HStack(spacing: 10) {
                    tx(q.resetText, 24, bold: false).foregroundStyle(T.text2).fixedSize()
                    if q.fast {
                        tx("偏快", 24).foregroundStyle(Color(hex: 0x1A1206)).fixedSize()
                            .padding(.horizontal, 12).padding(.vertical, 1)
                            .background(Capsule().fill(T.warn))
                    }
                }
            }
        }
    }
}

struct ProviderHeader: View {
    let name: String
    let note: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(T.r(32, .heavy)).foregroundStyle(T.text)
            Spacer()
            tx(note, 24, bold: false).foregroundStyle(T.text2)
        }
    }
}

struct Timeline: View {
    // 现在 → 4 天后（5760 分钟），按周五 10:00 起算
    let span: Double = 5760
    let days: [(String, Double)] = [("周六", 840), ("周日", 2280), ("周一", 3720), ("周二", 5160)]
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x: (Double) -> CGFloat = { m in CGFloat(m / span) * w }
            ZStack(alignment: .topLeading) {
                // 轴
                Capsule().fill(.white.opacity(0.10)).frame(width: w, height: 4).offset(y: 44)
                // 日界
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    Rectangle().fill(.white.opacity(0.16)).frame(width: 2, height: 16).offset(x: x(d.1 - 840 + 840), y: 38)
                    tx(d.0, 24, bold: false).foregroundStyle(T.text3).fixedSize()
                        .offset(x: x(d.1) + 10, y: 56)
                }
                tx("现在", 24).foregroundStyle(T.text2).fixedSize().offset(x: 0, y: 56)
                // 重置点
                marker(x(102), [claude[0]], label: "11:42", above: true)
                marker(x(3060), [claude[1], claude[2]], label: "周日 13:00", above: true)
                marker(x(5230), [codex[0]], label: "周二 01:10", above: true)
            }
        }
        .frame(height: 90)
    }
    @ViewBuilder func marker(_ x: CGFloat, _ qs: [Quota], label: String, above: Bool) -> some View {
        HStack(spacing: -6) {
            ForEach(qs) { q in
                Circle().fill(LinearGradient(colors: [q.c2, q.c1], startPoint: .top, endPoint: .bottom))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(T.bg, lineWidth: 3))
            }
        }
        .offset(x: x - 10, y: 36)
        Text(label).font(T.r(24, .semibold)).foregroundStyle(T.text).fixedSize()
            .offset(x: x - 10, y: 0)
    }
}

struct QuotaPage: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                T.bg
                RadialGradient(colors: [Color(hex: 0xFF6A3D, 0.14), .clear], center: UnitPoint(x: 0.22, y: 0.45), startRadius: 0, endRadius: 560)
                RadialGradient(colors: [Color(hex: 0x2F7BFF, 0.14), .clear], center: UnitPoint(x: 0.80, y: 0.45), startRadius: 0, endRadius: 480)
            }
            TopBar(active: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    tx("额度", 34).foregroundStyle(T.text)
                    tx("更新于 2 分钟前", 24, bold: false).foregroundStyle(T.text2)
                    HStack(spacing: 8) {
                        Circle().fill(T.warn).frame(width: 10, height: 10)
                        tx("Fable 每周用得偏快", 24, bold: false).foregroundStyle(T.warn)
                    }
                    .padding(.leading, 8)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                // Claude：三环
                VStack(alignment: .leading, spacing: 0) {
                    ProviderHeader(name: "Claude", note: "最近一次重置 1:42 后")
                    HStack(alignment: .center, spacing: 30) {
                        ZStack {
                            Ring(q: claude[1], diameter: 290, line: 28)
                            Ring(q: claude[2], diameter: 222, line: 28)
                            Ring(q: claude[0], diameter: 154, line: 28)
                        }
                        .frame(width: 318, height: 318)
                        VStack(spacing: 18) {
                            LegendRow(q: claude[0])
                            LegendRow(q: claude[1])
                            LegendRow(q: claude[2])
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(28)
                .frame(width: 744, height: 452, alignment: .topLeading)
                .background(Panel())
                // Codex：双环
                VStack(alignment: .leading, spacing: 0) {
                    ProviderHeader(name: "Codex", note: "周二重置")
                    HStack {
                        Spacer()
                        ZStack {
                            Ring(q: codex[0], diameter: 160, line: 26)
                            Ring(q: codex[1], diameter: 98, line: 26)
                        }
                        .frame(width: 176, height: 176)
                        Spacer()
                    }
                    .padding(.top, 10)
                    VStack(spacing: 10) {
                        LegendRow(q: codex[0])
                        LegendRow(q: codex[1])
                    }
                    .padding(.top, 12)
                }
                .padding(28)
                .frame(width: 404, height: 452, alignment: .topLeading)
                .background(Panel())
            }
            .padding(.leading, 56).padding(.top, 104)
            // 重置时间线
            Timeline()
                .frame(width: 1080)
                .padding(.leading, 90).padding(.top, 596)
        }
        .frame(width: 1280, height: 720)
    }
}

// MARK: - Gallery

struct Slide {
    let key: String
    let label: String
    let view: AnyView
}

let slides: [Slide] = [
    Slide(key: "v2-music", label: "音乐页", view: AnyView(MusicPage())),
    Slide(key: "v2-lyrics", label: "音乐页 · 歌词模式", view: AnyView(LyricsPage())),
    Slide(key: "v2-quota", label: "额度页", view: AnyView(QuotaPage())),
]

final class GalleryModel: ObservableObject {
    @Published var index = 0
    @Published var showLabel = true
    private var hide: DispatchWorkItem?
    func step(_ d: Int) { index = (index + d + slides.count) % slides.count; flash() }
    func flash() {
        showLabel = true
        hide?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.showLabel = false }
        hide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: w)
    }
}

struct GalleryView: View {
    @ObservedObject var m: GalleryModel
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            slides[m.index].view
            if m.showLabel {
                Text("\(slides[m.index].label)  \(m.index + 1)/\(slides.count)")
                    .font(.custom("PingFangSC-Semibold", size: 26)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .padding(20)
            }
        }
        .frame(width: 1280, height: 720)
        .contentShape(Rectangle())
        .onTapGesture { m.step(1) }
    }
}

final class FirstMouseView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func mouseDown(with event: NSEvent) { NSApp.activate(); super.mouseDown(with: event) }
}

final class ShowDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = GalleryModel()
    func applicationDidFinishLaunching(_ n: Notification) {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == "Wokyis" }) else {
            print("没找到 Wokyis 副屏"); NSApp.terminate(nil); return
        }
        window = KeyWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: true)
        window.contentView = FirstMouseView(rootView: GalleryView(m: model))
        window.orderFrontRegardless()
        model.flash()
        NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .keyDown]) { [weak self] e in
            if e.type == .rightMouseDown { self?.model.step(-1); return nil }
            switch e.keyCode {
            case 53, 12: NSApp.terminate(nil); return nil            // Esc, Q
            case 123: self?.model.step(-1); return nil                // ←
            case 124, 49: self?.model.step(1); return nil             // →, 空格
            default: return e
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2400) { NSApp.terminate(nil) }
    }
}

@main
struct DirectionsMain {
    static let delegate = ShowDelegate()
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count >= 3, args[1] == "render" {
            let dir = URL(fileURLWithPath: args[2])
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for s in slides {
                for scale in [1.0, 2.0] {
                    let r = ImageRenderer(content: s.view.frame(width: 1280, height: 720))
                    r.scale = scale
                    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { print("失败 \(s.key)"); continue }
                    let name = "\(s.key)@\(Int(scale))x.png"
                    try? png.write(to: dir.appendingPathComponent(name))
                    print("写入 \(name)")
                }
            }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
