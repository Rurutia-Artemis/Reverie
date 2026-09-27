import SwiftUI
import AppKit

// MARK: - 表面

struct Panel: View {
    var radius: CGFloat = 32
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [T.panelTop, T.panelBottom], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [T.ink(0.13), T.ink(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(T.palette.panelShadow), radius: 18, y: 6)
    }
}

struct CapsulePanel: View {
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [T.palette.capsuleTop, T.palette.capsuleBottom], startPoint: .top, endPoint: .bottom))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [T.ink(0.14), T.ink(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// 按下即反馈：缩小一点、变暗一点。
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 顶栏

/// 右上角：音乐 / 额度 / 设置合成一组。平时隐藏，鼠标移到右上角才出现（chromeVisible 由 AppDelegate 的悬停区控制）。
struct PageSwitch: View {
    let active: Int
    let onSelect: (Int) -> Void
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(["音乐", "额度", "消费"].enumerated()), id: \.offset) { i, name in
                Button { onSelect(i) } label: {
                    tx(name, T.Size.meta, bold: i == active)
                        .foregroundStyle(i == active ? T.text : T.text2)
                        .padding(.horizontal, 22).padding(.vertical, 7)
                        .background(Capsule().fill(i == active ? T.ink(0.14) : .clear))
                        .contentShape(Rectangle().inset(by: -16))     // 热区扩到 72 高
                }
                .buttonStyle(PressStyle())
            }
            Rectangle().fill(T.ink(0.12)).frame(width: 1, height: 26).padding(.horizontal, 6)
            // 设置：窗口开在主屏。退出：彻底退出 Reverie（launchd 不会再拉起，下次开机才回来）。
            Button { onSelect(9) } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(T.text2)
                    .frame(width: 40, height: 38)
                    .contentShape(Rectangle().inset(by: -16))
            }
            .buttonStyle(PressStyle())
            Button { onSelect(8) } label: {
                Image(systemName: "power").font(.system(size: 20, weight: .bold)).foregroundStyle(T.text2)
                    .frame(width: 40, height: 38)
                    .contentShape(Rectangle().inset(by: -16))
            }
            .buttonStyle(PressStyle())
            .padding(.trailing, 4)
        }
        .padding(5)
        .background(CapsulePanel())
    }
}

/// 页面是否显示右上角那组按钮；fixture 出图时默认显示。
private struct ChromeVisibleKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var chromeVisible: Bool {
        get { self[ChromeVisibleKey.self] }
        set { self[ChromeVisibleKey.self] = newValue }
    }
}

struct TopBar<Left: View>: View {
    let active: Int
    let onSelect: (Int) -> Void
    @ViewBuilder var left: Left
    @Environment(\.chromeVisible) private var chromeVisible
    var body: some View {
        HStack(alignment: .center) {
            left
            Spacer()
            PageSwitch(active: active, onSelect: onSelect)
                .opacity(chromeVisible ? 1 : 0)
                .offset(y: chromeVisible ? 0 : -8)
                .allowsHitTesting(chromeVisible)
                .animation(.easeOut(duration: 0.2), value: chromeVisible)
        }
        .padding(.horizontal, 56)
        .frame(height: 56)
        .padding(.top, 24)
    }
}

struct ClockLabel: View {
    let now: Date
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            num(TimeText.clock(now), T.Size.clock, weight: .heavy).foregroundStyle(T.text)
            tx(TimeText.date(now), T.Size.clockDate, bold: false).foregroundStyle(T.textOnCover)
        }
    }
}

// MARK: - 封面与氛围光

struct CoverView: View {
    let art: NSImage?
    let side: CGFloat
    var radius: CGFloat = 32
    var glow: Color = .clear
    var dimmed = false
    var body: some View {
        Group {
            if let art {
                Image(nsImage: art).resizable().interpolation(.high).scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [T.panelTop, T.panelBottom], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note").font(.system(size: side * 0.26, weight: .semibold)).foregroundStyle(T.ink(0.18))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(T.ink(0.10), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.black.opacity(dimmed ? 0.42 : 0)))
        .shadow(color: T.shadow(0.6), radius: 24, y: 18)
        .shadow(color: glow.opacity(0.28), radius: 60, y: 10)
    }
}

/// 音乐页背景：有封面时用封面模糊图铺满（颜色从封面往外延展）；没有封面时退回氛围光。
/// 深色背景下按封面亮度盖一层黑，浅色背景下盖一层白，保证文字看得清。
struct CoverBackground: View {
    let backdrop: CoverBackdrop?
    let palette: AlbumPalette
    var center = UnitPoint(x: 0.25, y: 0.56)
    var body: some View {
        if let backdrop {
            ZStack {
                T.bg
                Image(nsImage: backdrop.image).resizable().interpolation(.high).scaledToFill()
                    .frame(width: 1280, height: 720).clipped()
                if T.palette.isLight {
                    Color.white.opacity(min(0.72, max(0.45, 0.8 - backdrop.luminance * 0.4)))
                } else {
                    Color.black.opacity(min(0.62, max(0.22, 0.12 + backdrop.luminance * 0.7)))
                    LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .center, endPoint: .bottom)
                }
            }
        } else {
            AlbumGlow(palette: palette, center: center)
        }
    }
}

/// 封面颜色洇出来的氛围光，只在封面周围。
struct AlbumGlow: View {
    let palette: AlbumPalette
    var center = UnitPoint(x: 0.25, y: 0.56)
    var body: some View {
        ZStack {
            T.bg
            RadialGradient(colors: [palette.glow.opacity(0.30 * T.palette.albumGlow), palette.glow.opacity(0.08 * T.palette.albumGlow), .clear], center: center, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [palette.glow2.opacity(0.35 * T.palette.albumGlow), .clear], center: UnitPoint(x: center.x - 0.12, y: center.y - 0.42), startRadius: 0, endRadius: 520)
            LinearGradient(colors: [.clear, T.palette.bottomShade], startPoint: .center, endPoint: .bottom)
        }
    }
}

// MARK: - 播放控制

/// 上一首 / 下一首：不加底，只有图标，热区 76。
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 76
    var icon: CGFloat = 34
    var enabled = true
    var tint: Color? = nil          // 亮起时的颜色（例如歌词模式里的歌词按钮）
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: icon, weight: .semibold)).foregroundStyle((tint ?? T.text).opacity(enabled ? 0.92 : 0.3))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// 播放 / 暂停：深色背景下白底、图标用封面的深色；浅色背景下黑底白图标。
struct PlayButton: View {
    var size: CGFloat = 96
    let playing: Bool
    var accent: Color = Color(hex: 0x111114)      // 深色背景下图标用封面的深色，和白底搭
    var enabled = true
    let action: () -> Void
    var body: some View {
        let fill = T.palette.playFill
        let icon = T.palette.isLight ? T.palette.playIcon : T.deep(accent)
        Button(action: action) {
            ZStack {
                Circle().fill(fill)
                    .shadow(color: T.shadow(0.35), radius: 14, y: 6)
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(icon)
                    .offset(x: playing ? 0 : size * 0.035)     // 三角形光学居中
            }
            .frame(width: size, height: size)
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// 红心：不加底。喜欢时实心红、带一点红光；不喜欢时空心；来源不支持时很淡且不可点。
struct LikeButton: View {
    var size: CGFloat = 76
    let liked: Bool?
    var enabled = true
    let action: () -> Void
    var body: some View {
        let on = liked == true
        Button(action: action) {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(on ? T.like : T.text2)
                .shadow(color: on ? T.like.opacity(0.55) : .clear, radius: 14)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .opacity(liked == nil || !enabled ? 0.25 : 1)
        }
        .buttonStyle(PressStyle())
        .disabled(liked == nil || !enabled)
    }
}

/// 上一首、播放、下一首。按钮都做大（副屏上常点）：普通页 108 / 132，歌词模式 88 / 104。
struct TransportControls: View {
    let vm: MusicVM
    let actions: MusicActions
    var large = true
    var body: some View {
        HStack(spacing: large ? 22 : 12) {
            IconButton(symbol: "backward.fill", size: large ? 108 : 88, icon: large ? 46 : 38, action: actions.prev)
            PlayButton(size: large ? 132 : 104, playing: vm.playing, accent: vm.palette.glow, action: actions.playPause)
            IconButton(symbol: "forward.fill", size: large ? 108 : 88, icon: large ? 46 : 38, action: actions.next)
        }
    }
}

struct ProgressBar: View {
    let vm: MusicVM
    var height: CGFloat = 8
    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { g in
                let x = g.size.width * vm.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(T.ink(0.22))
                    Capsule().fill(T.palette.playFill.opacity(0.95))
                        .frame(width: max(height, x))
                    Circle().fill(.white).frame(width: 18, height: 18)
                        .shadow(color: T.shadow(0.5), radius: 4, y: 2)
                        .offset(x: x - 9)
                }
            }
            .frame(height: height)
            HStack {
                num(fmtTime(vm.elapsed), T.Size.meta, weight: .semibold)
                Spacer()
                num("-" + fmtTime(max(0, vm.duration - vm.elapsed)), T.Size.meta, weight: .semibold)
            }
            .foregroundStyle(T.textOnCover)
        }
    }
}

// MARK: - 额度

struct QuotaRing: View {
    let card: QuotaCard
    let diameter: CGFloat
    let line: CGFloat
    let now: Date
    let showUsed: Bool
    var body: some View {
        let (c1, c2) = QuotaColors.colors(for: card.id)
        let frac = ((showUsed ? card.used : card.remaining) ?? 0) / 100
        let r = diameter / 2
        ZStack {
            if card.remaining == nil {
                Circle().stroke(c1.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 10]))
            } else {
                Circle().stroke(c1.opacity(T.palette.isLight ? 0.26 : 0.16), lineWidth: line)
                Circle().trim(from: 0, to: max(0.001, frac))
                    .stroke(AngularGradient(colors: [c1, c2], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.001, frac))),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: c1.opacity(0.45), radius: 10)
                let a = (-90 + 360 * frac) * .pi / 180
                Circle().fill(c2).frame(width: line, height: line)
                    .shadow(color: T.shadow(0.55), radius: 5, x: 3 * cos(a + .pi / 2), y: 3 * sin(a + .pi / 2))
                    .offset(x: r * cos(a), y: r * sin(a))
                // 「按时间应剩多少」不再画白点（没人看得懂），偏快只靠图例里的小牌。
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

struct LegendRow: View {
    let card: QuotaCard
    let now: Date
    let showUsed: Bool
    /// 窄卡片或行多时用小一号；宽卡片里项目名和数字都放大，数字和左边两行字上下居中。
    var compact = false
    var body: some View {
        let (c1, c2) = QuotaColors.colors(for: card.id)
        let label = compact ? T.Size.name : T.Size.quotaLabel
        let number = compact ? T.Size.bigNumber : T.Size.quotaNumber
        let bar: CGFloat = compact ? 72 : 88
        switch card.value {
        case .missing:
            HStack(spacing: 16) {
                Capsule().fill(c1.opacity(0.35)).frame(width: 8, height: bar - 16)
                VStack(alignment: .leading, spacing: 2) {
                    tx(card.title, label).foregroundStyle(T.text2).lineLimit(1).fixedSize()
                    tx("暂无数据", T.Size.meta, bold: false).foregroundStyle(T.text3).fixedSize()
                }
                Spacer(minLength: 0)
            }
        case .balance(let amount, let unit):
            HStack(alignment: .center, spacing: 16) {
                Capsule().fill(LinearGradient(colors: [c1, c2], startPoint: .top, endPoint: .bottom)).frame(width: 8, height: bar - 16)
                VStack(alignment: .leading, spacing: 2) {
                    tx(card.title, label).foregroundStyle(T.text).lineLimit(1)
                    tx(unit, T.Size.meta, bold: false).foregroundStyle(T.text2)
                }
                Spacer(minLength: 8)
                num(amount == amount.rounded() ? String(Int(amount)) : String(format: "%.1f", amount), number, weight: .heavy)
                    .foregroundStyle(LinearGradient(colors: T.numberColors(c1, c2), startPoint: .top, endPoint: .bottom)).fixedSize()
            }
        case .percent where compact:
            // 小卡片：项目名和数字同一行、按基线对齐，重置时间在下面一行（v2 定稿的排法）。
            let value = (showUsed ? card.used : card.remaining) ?? 0
            HStack(alignment: .center, spacing: 16) {
                Capsule().fill(LinearGradient(colors: [c1, c2], startPoint: .top, endPoint: .bottom)).frame(width: 8, height: 78)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline) {
                        tx(card.title, T.Size.name).foregroundStyle(T.text).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            num("\(Int(value.rounded()))", T.Size.bigNumber, weight: .heavy)
                            num("%", T.Size.unit).foregroundStyle(T.unitColor(c1, c2))
                        }
                        .foregroundStyle(LinearGradient(colors: T.numberColors(c1, c2), startPoint: .top, endPoint: .bottom))
                        .fixedSize()
                    }
                    .frame(height: 58)
                    HStack(spacing: 10) {
                        tx(TimeText.reset(card.resetsAt, now: now), T.Size.meta, bold: false).foregroundStyle(T.text2)
                            .lineLimit(1).minimumScaleFactor(0.7)   // 空间不够时缩字，不许把卡片撑宽
                        if card.pace(now: now)?.fast == true { FastBadge() }
                    }
                }
            }
        case .percent:
            let value = (showUsed ? card.used : card.remaining) ?? 0
            HStack(alignment: .center, spacing: 16) {
                Capsule().fill(LinearGradient(colors: [c1, c2], startPoint: .top, endPoint: .bottom)).frame(width: 8, height: bar)
                VStack(alignment: .leading, spacing: 6) {
                    tx(card.title, label).foregroundStyle(T.text).lineLimit(1).minimumScaleFactor(0.75)
                    HStack(spacing: 10) {
                        tx(TimeText.reset(card.resetsAt, now: now), T.Size.meta, bold: false).foregroundStyle(T.text2)
                            .lineLimit(1).minimumScaleFactor(0.7)   // 空间不够时缩字，不许把卡片撑宽
                        if card.pace(now: now)?.fast == true { FastBadge() }
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    num("\(Int(value.rounded()))", number, weight: .heavy)
                    num("%", T.Size.unit).foregroundStyle(T.unitColor(c1, c2))
                }
                .foregroundStyle(LinearGradient(colors: T.numberColors(c1, c2), startPoint: .top, endPoint: .bottom))
                .fixedSize()
            }
        }
    }
}

struct FastBadge: View {
    var body: some View {
        tx("偏快", T.Size.meta).foregroundStyle(Color(hex: 0x1A1206)).fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 1)
            .background(Capsule().fill(Color(hex: 0xFFC04D)))
    }
}

/// 一张卡片只有一项时：只放一个大圆环，数字在正中间，别的都不写（重置时间在卡片下面的周期条里）。
struct QuotaHero: View {
    let card: QuotaCard
    let now: Date
    let showUsed: Bool
    var diameter: CGFloat = 292
    var line: CGFloat = 32
    var body: some View {
        let (c1, c2) = QuotaColors.colors(for: card.id)
        ZStack {
            QuotaRing(card: card, diameter: diameter, line: line, now: now, showUsed: showUsed)
            if let value = showUsed ? card.used : card.remaining {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    num("\(Int(value.rounded()))", T.Size.quotaHero, weight: .heavy)
                    num("%", T.Size.quotaHeroUnit).foregroundStyle(T.unitColor(c1, c2))
                }
                .foregroundStyle(LinearGradient(colors: T.numberColors(c1, c2), startPoint: .top, endPoint: .bottom))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: diameter - line * 2 - 16)
            } else {
                tx("暂无数据", T.Size.meta, bold: false).foregroundStyle(T.text3)
            }
        }
        .frame(width: diameter + line, height: diameter + line)
    }
}

/// 订阅档位的小牌子（Max / Pro …），用来源自己的配色。
struct PlanBadge: View {
    let text: String
    let provider: String
    var body: some View {
        let (c1, c2) = provider == "Claude" ? (Color(hex: 0xFF5A36), Color(hex: 0xFF9A6E)) : (Color(hex: 0x2F7BFF), Color(hex: 0x64D2FF))
        num(text, T.Size.planBadge, weight: .heavy)
            .foregroundStyle(T.readable(on: c2))
            .padding(.horizontal, 16).padding(.vertical, 5)
            .background(Capsule().fill(LinearGradient(colors: [c2, c1], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .shadow(color: c1.opacity(0.35), radius: 8)
    }
}

/// 额度卡片下面的周期进度：这个来源最长的那个窗口（通常是每周）已经过了多少，快到重置时间一眼能看出来。
struct CycleBar: View {
    let provider: String
    let cards: [QuotaCard]
    let now: Date
    var body: some View {
        if let card = Self.longest(cards, now: now), case .percent(_, let w?, let r?) = card.value {
            let elapsed = min(1, max(0, 1 - r.timeIntervalSince(now) / (w * 60)))
            let soon = elapsed >= 0.85
            let (c1, c2) = QuotaColors.colors(for: card.id)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    tx((9000...12000).contains(w) ? "本周已过" : ((240...360).contains(w) ? "这 5 小时已过" : "本周期已过"), T.Size.meta)
                        .foregroundStyle(T.text)
                    num("\(Int((elapsed * 100).rounded()))%", T.Size.meta, weight: .bold)
                        .foregroundStyle(LinearGradient(colors: T.numberColors(c1, c2), startPoint: .top, endPoint: .bottom))
                    Spacer(minLength: 8)
                    tx((soon ? "快重置了 · " : "") + "还剩 " + TimeText.left(until: r, now: now), T.Size.meta, bold: false)
                        .foregroundStyle(soon ? T.warn : T.text2).lineLimit(1)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(T.ink(0.10))
                        Capsule().fill(LinearGradient(colors: [c1, c2], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(12, g.size.width * elapsed))
                            .shadow(color: c1.opacity(0.45), radius: 8)
                    }
                }
                .frame(height: 22)
            }
        }
    }

    /// 有重置时间、还没过期的项里，窗口最长的那个。
    static func longest(_ cards: [QuotaCard], now: Date) -> QuotaCard? {
        cards.filter { c in
            if case .percent(_, let w?, let r?) = c.value { return w > 0 && r > now }
            return false
        }
        .max { a, b in
            guard case .percent(_, let wa?, _) = a.value, case .percent(_, let wb?, _) = b.value else { return false }
            return wa < wb
        }
    }
}
