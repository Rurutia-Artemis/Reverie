import SwiftUI
import AppKit

/// 额度页：按来源分块，每块同心环 + 图例；底部重置时间线。最多 6 项，每个来源最多 4 项。
struct QuotaPage: View {
    let vm: QuotaVM
    let onSelectPage: (Int) -> Void

    static let tileHeight: CGFloat = 452
    static let contentWidth: CGFloat = 1168

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                T.bg
                RadialGradient(colors: [Color(hex: 0xFF6A3D, T.palette.glowWarm), .clear], center: UnitPoint(x: 0.22, y: 0.45), startRadius: 0, endRadius: 560)
                RadialGradient(colors: [Color(hex: 0x2F7BFF, T.palette.glowCool), .clear], center: UnitPoint(x: 0.80, y: 0.45), startRadius: 0, endRadius: 480)
            }
            TopBar(active: 1, onSelect: onSelectPage) { header }
            content
        }
        .frame(width: 1280, height: 720)
    }

    // MARK: 页头

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            tx("额度", T.Size.pageTitle).foregroundStyle(T.text)
            if let m = vm.updatedMinutes {
                tx("更新于 " + TimeText.ago(m), T.Size.meta, bold: false).foregroundStyle(T.text2)
            }
            if let alert {
                HStack(spacing: 8) {
                    Circle().fill(T.warn).frame(width: 10, height: 10)
                    tx(alert, T.Size.meta, bold: false).foregroundStyle(T.warn).lineLimit(1)
                }
                .padding(.leading, 8)
            }
        }
    }

    /// 页头只放一条提醒：数据过期。
    private var alert: String? {
        if let (p, m) = vm.stale.sorted(by: { $0.value > $1.value }).first {
            return m < 0 ? "\(p) 数据更新时间未知" : "\(p) 数据停在 \(TimeText.ago(m))"
        }
        return nil      // 「偏快」只在图例里标一次
    }

    // MARK: 内容

    @ViewBuilder private var content: some View {
        switch vm.status {
        case .unavailable(let reason):
            message(icon: "exclamationmark.circle", text: reason)
        case .ok:
            if vm.cards.isEmpty {
                message(icon: "slider.horizontal.3", text: "在设置里选择要显示的额度")
            } else {
                tiles.padding(.top, 104)
                    .padding(.leading, 56)
            }
        }
    }

    private func message(icon: String, text: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon).font(.system(size: 44, weight: .semibold)).foregroundStyle(T.text2)
            tx(text, T.Size.artist, bold: false).foregroundStyle(T.text.opacity(0.85)).multilineTextAlignment(.center).lineSpacing(10)
        }
        .frame(width: 1280, height: 720)
    }

    /// 一个来源一列：上面是卡片，下面是它的周期进度条，宽度对齐。
    private func column(_ g: (provider: String, cards: [QuotaCard]), layout: ProviderTile.Layout, width: CGFloat) -> some View {
        VStack(spacing: 30) {
            ProviderTile(provider: g.provider, cards: g.cards, layout: layout, vm: vm)
            CycleBar(provider: g.provider, cards: g.cards, now: vm.now).padding(.horizontal, 8)
        }
        .frame(width: width)
    }

    private var groups: [(provider: String, cards: [QuotaCard])] {
        var out: [(String, [QuotaCard])] = []
        for c in vm.cards {
            if let i = out.firstIndex(where: { $0.0 == c.provider }) { out[i].1.append(c) } else { out.append((c.provider, [c])) }
        }
        return out.map { ($0.0, Array($0.1.prefix(4))) }
    }

    @ViewBuilder private var tiles: some View {
        let g = groups
        if g.count == 1 {
            column(g[0], layout: .wide(outer: 296), width: Self.contentWidth)
        } else {
            let a = g[0], b = g[1]
            let big = a.cards.count >= b.cards.count ? 0 : 1
            let small = g[1 - big]
            if small.cards.count <= 2 && g[big].cards.count > small.cards.count {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(0..<2, id: \.self) { i in
                        if i == big {
                            column(g[i], layout: .wide(outer: 296), width: 744)
                        } else {
                            column(g[i], layout: .narrow, width: 404)
                        }
                    }
                }
            } else {
                let outer: CGFloat = max(a.cards.count, b.cards.count) <= 2 ? 230 : 170
                HStack(alignment: .top, spacing: 20) {
                    column(a, layout: .wide(outer: outer), width: 574)
                    column(b, layout: .wide(outer: outer), width: 574)
                }
            }
        }
    }
}

struct ProviderTile: View {
    enum Layout { case wide(outer: CGFloat), narrow }
    let provider: String
    let cards: [QuotaCard]
    let layout: Layout
    let vm: QuotaVM

    private var ringCards: [QuotaCard] { cards.filter(\.isRing) }
    private var staleMinutes: Int? { vm.stale[provider] }
    /// 窄卡片只有一项：用大圆环铺满，重置时间写在圆环下面，标题行右边不再重复。
    private var isHero: Bool {
        if case .narrow = layout { return cards.count == 1 && ringCards.count == 1 }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 12) {
                    num(provider, T.Size.provider, weight: .heavy).foregroundStyle(T.text)
                    if let plan = vm.plans[provider] { PlanBadge(text: plan, provider: provider) }
                }
                Spacer()
                if let problem = vm.problems[provider] {
                    tx(problem, T.Size.meta, bold: false).foregroundStyle(T.warn)
                } else if let m = staleMinutes {
                    tx(m < 0 ? "更新时间未知" : "数据停在 " + TimeText.ago(m), T.Size.meta, bold: false).foregroundStyle(T.warn)
                } else if isHero {
                    tx(cards[0].title, T.Size.meta, bold: false).foregroundStyle(T.text2)
                } else if let note {
                    tx(note, T.Size.meta, bold: false).foregroundStyle(T.text2)
                }
            }
            switch layout {
            case .wide(let outer):
                HStack(alignment: .center, spacing: 30) {   // 和标题行之间留 padding，别让圆环贴着 Max 小牌
                    if !ringCards.isEmpty {
                        rings(outer: outer, line: outer >= 260 ? 30 : (outer >= 220 ? 28 : 20), step: outer >= 260 ? 72 : (outer >= 220 ? 62 : 44))
                            .frame(width: outer + 30, height: outer + 30)
                    }
                    VStack(spacing: cards.count > 3 ? 8 : 18) {
                        ForEach(cards) { LegendRow(card: $0, now: vm.now, showUsed: vm.showUsed, compact: outer < 260 || cards.count > 3) }
                    }
                    .frame(maxWidth: 460)
                }
                .frame(maxHeight: .infinity)          // 行少时上下居中，不留半截空白
                .padding(.top, 12)
            case .narrow where cards.count == 1 && ringCards.count == 1:
                QuotaHero(card: cards[0], now: vm.now, showUsed: vm.showUsed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 12)
            case .narrow:
                if !ringCards.isEmpty {
                    HStack {
                        Spacer()
                        rings(outer: 160, line: 26, step: 62).frame(width: 176, height: 176)
                        Spacer()
                    }
                    .padding(.top, 10)
                }
                VStack(spacing: 10) {
                    ForEach(cards) { LegendRow(card: $0, now: vm.now, showUsed: vm.showUsed, compact: true) }
                }
                .padding(.top, 12)
            }
        }
        .padding(28)
        .frame(height: QuotaPage.tileHeight, alignment: .topLeading)
        .background(Panel())
        .saturation(staleMinutes == nil ? 1 : 0.35)
        .opacity(staleMinutes == nil ? 1 : 0.8)
    }

    private func rings(outer: CGFloat, line: CGFloat, step: CGFloat) -> some View {
        ZStack {
            ForEach(Array(ringOrder.enumerated()), id: \.element.id) { i, c in
                QuotaRing(card: c, diameter: outer - CGFloat(i) * step, line: line, now: vm.now, showUsed: vm.showUsed)
            }
        }
    }

    /// 外圈放窗口最长的（每周），内圈放最短的（5 小时）；按模型的放中间。
    private var ringOrder: [QuotaCard] {
        func rank(_ c: QuotaCard) -> Int {
            if c.id.hasSuffix(".weekly") { return 0 }
            if c.id.hasSuffix(".fiveHour") { return 9 }
            return 5
        }
        return ringCards.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// 标题右边不再重复图例里已有的重置时间。
    private var note: String? { nil }
}
