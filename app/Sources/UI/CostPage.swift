import SwiftUI
import AppKit

/// 消费页的数据：按 API 价格把本机 Claude Code / Codex 记录里的 token 折成美元。
struct CostVM {
    struct Model: Identifiable {
        let id: String
        let name: String
        let usd: Double
        let tokens: Int
        let colors: (Color, Color)
    }
    struct Provider: Identifiable {
        var id: String { name }
        let name: String
        let models: [Model]          // 按金额从大到小，最多 4 项，其余并成「其他」
        let daily: [Double]          // 周期内每天，从早到今天
        var total: Double { models.reduce(0) { $0 + $1.usd } }
    }
    var providers: [Provider] = []
    var period: CostPeriod = .week
    var dayLabels: [String] = []     // 与 daily 一一对应；空字符串不写字
    var updatedMinutes: Int? = nil
    var scanning = false
    var now = Date()

    /// 由统计结果生成界面数据：模型按金额取前 4，多的并成「其他」；颜色按名次分配。
    static func from(_ s: CostSummary, updatedAt: Date?, now: Date) -> CostVM {
        var vm = CostVM()
        vm.now = now
        vm.period = s.period
        vm.updatedMinutes = updatedAt.map { max(0, Int(now.timeIntervalSince($0) / 60)) }
        vm.dayLabels = labels(for: s.days, period: s.period)
        for p in s.providers {
            let palette = p.provider == .claude ? warm : cool
            var models: [Model] = []
            let top = p.models.prefix(p.models.count > 4 ? 3 : 4)
            for (i, m) in top.enumerated() {
                models.append(Model(id: m.model, name: Pricing.displayName(m.model), usd: m.usd, tokens: m.tokens, colors: palette[i]))
            }
            if p.models.count > 4 {
                let rest = p.models.dropFirst(3)
                models.append(Model(id: "other", name: "其他 \(rest.count) 个", usd: rest.reduce(0) { $0 + $1.usd },
                                    tokens: rest.reduce(0) { $0 + $1.tokens }, colors: palette[3]))
            }
            vm.providers.append(Provider(name: p.provider == .claude ? "Claude" : "Codex", models: models, daily: p.daily))
        }
        return vm
    }

    static let warm: [(Color, Color)] = [
        (Color(hex: 0xFF5A36), Color(hex: 0xFF9A6E)), (Color(hex: 0xFF9500), Color(hex: 0xFFC862)),
        (Color(hex: 0xFF2D6F), Color(hex: 0xFF7AA2)), (Color(hex: 0xE0785A), Color(hex: 0xF4B299)),
    ]
    static let cool: [(Color, Color)] = [
        (Color(hex: 0x2F7BFF), Color(hex: 0x64D2FF)), (Color(hex: 0x5E5CE6), Color(hex: 0xA5A3FF)),
        (Color(hex: 0x1FCF94), Color(hex: 0x7CF2C8)), (Color(hex: 0x14B8C8), Color(hex: 0x7EE8F0)),
    ]

    static func labels(for days: [Int], period: CostPeriod) -> [String] {
        days.enumerated().map { i, d in
            let last = i == days.count - 1
            if last { return "今天" }
            let day = d % 100
            switch period {
            case .week:
                var c = Calendar(identifier: .gregorian); c.timeZone = CostParse.tokyo
                let date = c.date(from: DateComponents(year: d / 10000, month: d / 100 % 100, day: day)) ?? Date()
                return TimeText.weekday(date)
            case .month:
                return (day == 1 || day % 5 == 0) ? "\(day) 日" : ""
            }
        }
    }
}

enum Money {
    /// $412 / $96.3 / $4.20：大数取整，小数保留一到两位。
    static func text(_ v: Double) -> String { "$" + bare(v) }
    /// 不带 $ 的写法（圆环中间用）。
    static func bare(_ v: Double) -> String {
        if v >= 100 { return String(Int(v.rounded())) }
        if v >= 10 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.2fB", Double(n) / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

/// 消费页：和额度页同一套版式——两张卡片（左宽右窄）、环形图 + 图例，下面每张卡片一条按天的花费。
struct CostPage: View {
    let vm: CostVM
    let onSelectPage: (Int) -> Void
    var onPeriod: (CostPeriod) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                T.bg
                RadialGradient(colors: [Color(hex: 0xFF6A3D, T.palette.glowWarm), .clear], center: UnitPoint(x: 0.22, y: 0.45), startRadius: 0, endRadius: 560)
                RadialGradient(colors: [Color(hex: 0x2F7BFF, T.palette.glowCool), .clear], center: UnitPoint(x: 0.80, y: 0.45), startRadius: 0, endRadius: 480)
            }
            TopBar(active: 2, onSelect: onSelectPage) { header }
            content
        }
        .frame(width: 1280, height: 720)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            tx("消费", T.Size.pageTitle).foregroundStyle(T.text)
            PeriodSwitch(active: vm.period, onSelect: onPeriod)
            tx("按 API 价格折算", T.Size.meta, bold: false).foregroundStyle(T.text2)
            if let m = vm.updatedMinutes {
                tx("· 更新于 " + TimeText.ago(m), T.Size.meta, bold: false).foregroundStyle(T.text2)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if vm.providers.isEmpty {
            VStack(spacing: 18) {
                Image(systemName: vm.scanning ? "hourglass" : "doc.text.magnifyingglass").font(.system(size: 44, weight: .semibold)).foregroundStyle(T.text2)
                tx(vm.scanning ? "正在统计本机的使用记录，第一次要几十秒…" : "本机没有找到 Claude Code 或 Codex 的使用记录",
                   T.Size.artist, bold: false).foregroundStyle(T.text.opacity(0.85)).multilineTextAlignment(.center).lineSpacing(10)
            }
            .frame(width: 1280, height: 720)
        } else {
            // 两张卡片各占一半。
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(vm.providers.prefix(2).enumerated()), id: \.offset) { _, p in
                    VStack(spacing: 26) {
                        CostTile(provider: p)
                        DailyBars(values: p.daily, labels: vm.dayLabels, colors: p.models.first?.colors ?? (Color(hex: 0x8E8E93), Color(hex: 0xC7C7CC)))
                            .padding(.horizontal, 8)
                    }
                    .frame(width: 574)
                }
            }
            .padding(.leading, 56).padding(.top, 104)
        }
    }
}

/// 「7 天 / 本月」切换，和右上角页面切换同一种胶囊。
struct PeriodSwitch: View {
    let active: CostPeriod
    let onSelect: (CostPeriod) -> Void
    var body: some View {
        HStack(spacing: 4) {
            ForEach(CostPeriod.allCases) { p in
                Button { onSelect(p) } label: {
                    tx(p.title, T.Size.meta, bold: p == active)
                        .foregroundStyle(p == active ? T.text : T.text2)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .background(Capsule().fill(p == active ? T.ink(0.14) : .clear))
                        .contentShape(Rectangle().inset(by: -16))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(4)
        .background(CapsulePanel())
    }
}

struct CostTile: View {
    let provider: CostVM.Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                num(provider.name, T.Size.provider, weight: .heavy).foregroundStyle(T.text)
                Spacer()
                tx(provider.models.isEmpty ? "这段时间没用" : "\(provider.models.count) 个模型", T.Size.meta, bold: false).foregroundStyle(T.text2)
            }
            HStack(alignment: .center, spacing: 24) {
                CostDonut(provider: provider, diameter: 208, line: 24, number: T.Size.costHero)
                    .frame(width: 228, height: 228)
                VStack(spacing: 10) {
                    ForEach(provider.models) { CostLegendRow(model: $0, total: provider.total) }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 10)
        }
        .padding(.vertical, 28).padding(.horizontal, 24)
        .frame(height: QuotaPage.tileHeight, alignment: .topLeading)
        .background(Panel())
    }
}

/// 分段环：每个模型一段，段间留一点缝；中间只放总金额。
struct CostDonut: View {
    let provider: CostVM.Provider
    let diameter: CGFloat
    let line: CGFloat
    let number: CGFloat

    var body: some View {
        let total = max(provider.total, 0.0001)
        let gap = provider.models.count > 1 ? 0.012 : 0
        var start = 0.0
        let segs: [(CostVM.Model, Double, Double)] = provider.models.map { m in
            let frac = m.usd / total
            defer { start += frac }
            return (m, start, start + frac)
        }
        ZStack {
            Circle().stroke(T.ink(0.06), lineWidth: line)
            ForEach(segs, id: \.0.id) { m, a, b in
                Circle().trim(from: a + gap / 2, to: max(a + gap / 2 + 0.001, b - gap / 2))
                    .stroke(LinearGradient(colors: [m.colors.1, m.colors.0], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: m.colors.0.opacity(0.35), radius: 8)
            }
            // 总金额不带 $，颜色按金额分档（5000 以上彩虹）。
            let colors = T.moneyColors(provider.total)
            let rainbow = colors.count > 2
            num(Money.bare(provider.total), number, weight: .heavy)
                .foregroundStyle(LinearGradient(colors: colors, startPoint: rainbow ? .topLeading : .top, endPoint: rainbow ? .bottomTrailing : .bottom))
                .shadow(color: (rainbow ? Color(hex: 0xFFD3A8) : colors[1]).opacity(provider.total >= 1000 ? (rainbow ? 0.5 : 0.35) : 0), radius: rainbow ? 16 : 12)
                .lineLimit(1).minimumScaleFactor(0.55)
                .frame(width: diameter - line * 2 - 10)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// 图例一行：模型名占满一整行，下面一行左边是占比和 token 数、右边是金额，名字不会被挤成省略号。
struct CostLegendRow: View {
    let model: CostVM.Model
    let total: Double

    var body: some View {
        let share = total > 0 ? Int((model.usd / total * 100).rounded()) : 0
        HStack(alignment: .center, spacing: 14) {
            Capsule().fill(LinearGradient(colors: [model.colors.0, model.colors.1], startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: 60)
            VStack(alignment: .leading, spacing: 0) {
                tx(model.name, T.Size.name).foregroundStyle(T.text).lineLimit(1).minimumScaleFactor(0.8)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    tx("\(share)% · \(Money.tokens(model.tokens))", T.Size.meta, bold: false).foregroundStyle(T.text2).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    num(Money.text(model.usd), T.Size.costAmount, weight: .heavy)
                        .foregroundStyle(LinearGradient(colors: T.numberColors(model.colors.0, model.colors.1), startPoint: .top, endPoint: .bottom))
                        .fixedSize()
                }
            }
        }
    }
}

/// 周期内每天花了多少：今天那根满色并标金额，之前的淡一点；本月模式条多，只在 1、5、10… 日写字。
struct DailyBars: View {
    let values: [Double]
    let labels: [String]
    let colors: (Color, Color)

    var body: some View {
        let top = max(values.max() ?? 1, 0.0001)
        let many = values.count > 10
        HStack(alignment: .bottom, spacing: many ? 4 : 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let today = i == values.count - 1
                let label = i < labels.count ? labels[i] : ""
                VStack(spacing: 6) {
                    if today {
                        num(Money.text(v), T.Size.meta, weight: .bold).foregroundStyle(T.text).fixedSize()
                    }
                    UnevenRoundedRectangle(topLeadingRadius: many ? 4 : 7, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: many ? 4 : 7, style: .continuous)
                        .fill(LinearGradient(colors: [colors.1, colors.0], startPoint: .top, endPoint: .bottom))
                        .opacity(today ? 1 : 0.42)
                        .frame(width: many ? nil : 30, height: max(6, 62 * v / top))
                        .frame(maxWidth: many ? .infinity : nil)
                        .shadow(color: today ? colors.0.opacity(0.45) : .clear, radius: 8)
                    tx(label.isEmpty ? " " : label, T.Size.meta, bold: today).foregroundStyle(today ? T.text : T.text3).fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 118, alignment: .bottom)
    }
}
