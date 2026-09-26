import SwiftUI
import AppKit
import ApplicationServices

/// 主屏上的设置窗口；副屏上不放任何需要打字或弹系统面板的控件。
final class SettingsWindowController {
    private var window: NSWindow?

    func show(settings: SettingsStore, app: AppModel, quota: QuotaStore, cost: CostStore) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Reverie 设置"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings, app: app, quota: quota, cost: cost))
            window = w
        }
        // 固定开在主屏（菜单栏所在的那块）。
        if let s = Displays.screen(for: Displays.primaryID()), let w = window {
            let v = s.visibleFrame
            w.setFrameOrigin(NSPoint(x: v.midX - w.frame.width / 2, y: v.midY - w.frame.height / 2))
        }
        app.refreshSystemState()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 副屏、授权、自启这些系统状态，给设置窗口和菜单栏看。
final class AppModel: ObservableObject {
    @Published var status: String? = nil
    @Published var displays: [DisplayInfo] = []
    @Published var targetName: String? = nil
    @Published var axTrusted = AXIsProcessTrusted()
    @Published var autostartOn = false
    var repin: () -> Void = {}
    var displaysChanged: () -> Void = {}

    func refreshSystemState() {
        axTrusted = AXIsProcessTrusted()
        DispatchQueue.global().async {
            let on = Autostart.isOn
            DispatchQueue.main.async { self.autostartOn = on }
        }
    }
}

/// 设置分栏（左边一列，和系统设置一样的样子）。
enum SettingsPane: String, CaseIterable, Identifiable {
    case account, appearance, music, quota, screen, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .account: return "账号"
        case .appearance: return "外观"
        case .music: return "音乐"
        case .quota: return "额度"
        case .screen: return "副屏"
        case .general: return "通用"
        }
    }
    var symbol: String {
        switch self {
        case .account: return "person.crop.circle.fill"
        case .appearance: return "paintpalette.fill"
        case .music: return "music.note"
        case .quota: return "chart.pie.fill"
        case .screen: return "rectangle.on.rectangle"
        case .general: return "gearshape.fill"
        }
    }
    var color: Color {
        switch self {
        case .account: return Color(hex: 0x0A84FF)
        case .appearance: return Color(hex: 0xBF5AF2)
        case .music: return Color(hex: 0xFF375F)
        case .quota: return Color(hex: 0xFF9F0A)
        case .screen: return Color(hex: 0x30B0C7)
        case .general: return Color(hex: 0x8E8E93)
        }
    }
}

/// 系统设置风格的小图标：彩色圆角方块 + 白色符号。
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)))
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var app: AppModel
    @ObservedObject var quota: QuotaStore
    @ObservedObject var cost: CostStore

    @State private var pane: SettingsPane = SettingsPane(rawValue: ProcessInfo.processInfo.environment["REVERIE_SETTINGS"] ?? "") ?? .account
    @State private var loginFailed: String? = nil

    private let knownSources: [(String, String)] = [
        (SourceCatalog.neteaseBundleID, "网易云音乐"),
        (SourceFilterLogic.appleMusicBundleID, "Apple Music"),
        ("com.spotify.client", "Spotify"),
        ("com.tencent.QQMusicMac", "QQ 音乐"),
    ]

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon).resizable().frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reverie").font(.title2.weight(.bold))
                        Text("副屏音乐与额度").font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                }
                .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 14)
                List(SettingsPane.allCases, selection: $pane) { p in
                    Label { Text(p.title) } icon: { SettingsIcon(symbol: p.symbol, color: p.color) }
                        .padding(.vertical, 3)
                        .tag(p)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text(pane.title).font(.title2.weight(.semibold))
                    .padding(.leading, 28).padding(.top, 22)
                Form { paneContent }
                    .formStyle(.grouped)
            }
            .navigationTitle(pane.title)
        }
        .frame(width: 820, height: 600)
        .alert("没有找到命令行", isPresented: Binding(get: { loginFailed != nil }, set: { if !$0 { loginFailed = nil } })) {
            Button("好") { loginFailed = nil }
        } message: {
            Text("本机没找到 \(loginFailed ?? "") 的命令行，装好之后再点「重新登录」。")
        }
    }

    @ViewBuilder private var paneContent: some View {
        switch pane {
        case .account: accountPane
        case .appearance: appearancePane
        case .music: musicPane
        case .quota: quotaPane
        case .screen: screenPane
        case .general: generalPane
        }
    }

    // MARK: 账号

    @ViewBuilder private var accountPane: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                VStack(spacing: 14) {
                    accountRow(.claude, name: "Claude Code", now: ctx.date)
                    Divider()
                    accountRow(.codex, name: "Codex", now: ctx.date)
                }
                .padding(.vertical, 4)
            }
        } footer: {
            Text("额度直接从本机的 Claude Code 和 Codex 命令行读取。「重新登录」会在「终端」里打开登录命令，按提示在浏览器里完成就行，Reverie 随后自动刷新。")
        }
        Section {
            TextField("Claude 档位标签", text: $settings.claudePlanLabel, prompt: Text("自动（例如 Max 20x）"))
            TextField("Codex 档位标签", text: $settings.codexPlanLabel, prompt: Text("自动（例如 Pro）"))
        } header: {
            Text("订阅档位")
        } footer: {
            Text("额度页来源名旁边的小牌。留空就用自动取到的：Claude 的档位来自命令行、倍数来自钥匙串里 Claude Code 存的凭证项（只取档位字段），Codex 来自命令行。自动取不到或想改写法时在这里填。")
        }
        Section {
            Picker("刷新间隔", selection: $settings.quotaRefreshMinutes) {
                ForEach([2, 5, 10, 15], id: \.self) { Text("\($0) 分钟").tag($0) }
            }
            LabeledContent("手动刷新") { Button("立即刷新额度") { quota.refresh() } }
        }
    }

    // MARK: 外观

    @ViewBuilder private var appearancePane: some View {
        Section("背景") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                ForEach(Backdrop.allCases) { b in
                    BackdropSwatch(backdrop: b, palette: b.resolved(systemIsDark: true, custom: settings.customBackdrop),
                                   selected: settings.backdrop == b) { settings.backdrop = b }
                }
            }
            .padding(.vertical, 6)
            if settings.backdrop == .custom {
                HStack(spacing: 10) {
                    ColorPicker("底色", selection: $settings.customBackdrop, supportsOpacity: false)
                    Spacer()
                    // 几个常用底色，点一下就换。
                    ForEach([0x0F2A22, 0x2A0F18, 0x14224A, 0x2B2140, 0xF3EBDD, 0xE4ECF4], id: \.self) { h in
                        Button { settings.customBackdrop = Color(hex: UInt32(h)) } label: {
                            Circle().fill(Color(hex: UInt32(h))).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        Section("字体") {
            Picker("字体", selection: $settings.fontScheme) {
                ForEach(FontScheme.allCases) { Text($0.title).tag($0) }
            }
            if settings.fontScheme == .alimama {
                if VariableFont.isAvailable {
                    LabeledContent("粗细") {
                        Slider(value: $settings.fontWeightAdjust, in: -3...3, step: 1) { EmptyView() }
                            minimumValueLabel: { Text("细") } maximumValueLabel: { Text("粗") }
                    }
                    LabeledContent("圆角") {
                        Slider(value: $settings.fontBevel, in: 1...100) { EmptyView() }
                            minimumValueLabel: { Text("方") } maximumValueLabel: { Text("圆") }
                    }
                } else {
                    Text("没找到字体文件，暂时用系统圆体显示。").foregroundStyle(.secondary)
                }
            }
            Picker("日文字体", selection: $settings.japaneseFont) {
                ForEach(FontChoices.japanese, id: \.self) { Text($0).tag($0) }
            }
        }
        Section {
            HStack {
                ColorPicker("主文字颜色", selection: $settings.textColor, supportsOpacity: false)
                Button("恢复默认") { settings.textColor = Color(hex: 0xF5F5F7) }
            }
            .disabled(T.palette.isLight)
        } footer: {
            if T.palette.isLight { Text("浅色背景固定用深色文字，主文字颜色只在深色背景下生效。") }
        }
    }

    // MARK: 音乐

    @ViewBuilder private var musicPane: some View {
        Section("歌词与页面") {
            Toggle("显示歌词翻译（外文歌有翻译时，显示在当前这句下面）", isOn: $settings.lyricsTranslation)
            Toggle("没在放歌时自动切到额度页，开始放歌后切回来", isOn: $settings.idleShowsQuota)
        }
        Section {
            Toggle("所有应用（跟随网页视频等任何播放源）", isOn: Binding(
                get: { settings.allowedSources.isEmpty },
                set: { settings.allowedSources = $0 ? [] : [SourceCatalog.neteaseBundleID, SourceFilterLogic.appleMusicBundleID] }))
            if !settings.allowedSources.isEmpty {
                ForEach(knownSources, id: \.0) { id, name in
                    Toggle(name, isOn: Binding(
                        get: { settings.allowedSources.contains(id) },
                        set: { on in
                            if on { settings.allowedSources.append(id) } else { settings.allowedSources.removeAll { $0 == id } }
                            if settings.allowedSources.isEmpty { settings.allowedSources = [id] }   // 至少留一个
                        }))
                }
            }
        } header: {
            Text("播放来源")
        } footer: {
            Text("副屏只显示这里允许的应用正在播放的内容。")
        }
    }

    // MARK: 额度

    @ViewBuilder private var quotaPane: some View {
        Section {
            Picker("大数字显示", selection: $settings.quotaShowUsed) {
                Text("剩余").tag(false)
                Text("已用").tag(true)
            }
            .pickerStyle(.segmented)
        }
        Section {
            ForEach(settings.quotaSeen, id: \.self) { id in quotaRow(id) }
        } header: {
            Text("显示项")
        } footer: {
            Text("最多同时显示 \(QuotaSelection.maxItems) 项，每个来源最多 4 项。")
        }
        Section {
            Picker("统计周期", selection: $settings.costPeriod) {
                ForEach(CostPeriod.allCases) { Text($0.longTitle).tag($0) }
            }
            LabeledContent("重新统计") { Button("重新扫描本机记录") { cost.rescan() } }
        } header: {
            Text("消费页")
        } footer: {
            Text("按 API 价格把本机 Claude Code 与 Codex 记录里的 token 折成美元，是「按 API 计费会花多少」，订阅实际付的是月费。网页版 claude.ai 的聊天不在本机记录里，算不进去。")
        }
    }

    // MARK: 副屏

    @ViewBuilder private var screenPane: some View {
        Section {
            LabeledContent("状态", value: app.status ?? (app.targetName.map { "已接管 \($0)" } ?? "—"))
            Picker("目标屏幕", selection: Binding(
                get: { settings.targetDisplayUUID ?? "" },
                set: { settings.targetDisplayUUID = $0.isEmpty ? nil : $0; app.displaysChanged() })) {
                Text("自动（最小的那块非主屏）").tag("")
                ForEach(app.displays.filter { !$0.isPrimary }, id: \.uuid) { d in
                    Text("\(d.name)  \(Int(d.frame.width))×\(Int(d.frame.height))").tag(d.uuid)
                }
            }
            Toggle("接管副屏（落到副屏的其它窗口自动挪回主屏）", isOn: $settings.evictorEnabled)
            LabeledContent("位置不对时") { Button("重新固定到副屏") { app.repin() } }
        }
        if !app.axTrusted {
            Section {
                HStack {
                    Text("挪窗口和网易云红心需要「辅助功能」授权").foregroundStyle(.orange)
                    Spacer()
                    Button("打开设置") { openAccessibility() }
                }
            }
        }
    }

    // MARK: 通用

    @ViewBuilder private var generalPane: some View {
        Section {
            Toggle("开机自动启动", isOn: Binding(
                get: { app.autostartOn },
                set: { on in
                    DispatchQueue.global().async {
                        Autostart.set(on)
                        DispatchQueue.main.async { app.refreshSystemState() }
                    }
                }))
            LabeledContent("切换音乐 / 额度", value: "⌃⌥⌘R，或鼠标移到副屏右上角")
        }
        Section {
            Text("字体「阿里妈妈方圆体」版权归阿里妈妈（淘宝（中国）软件有限公司）所有，按其免费商用许可内嵌使用。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func accountRow(_ p: QuotaProvider, name: String, now: Date) -> some View {
        let status = quota.statusText(p, now: now)
        let bad = quota.snapshot?.problems[p] != nil
        HStack(spacing: 12) {
            SettingsIcon(symbol: p == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right",
                         color: p == .claude ? Color(hex: 0xD97757) : Color(hex: 0x0A84FF), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium))
                HStack(spacing: 5) {
                    Circle().fill(bad ? Color.orange : Color.green).frame(width: 7, height: 7)
                    Text(status).font(.caption).foregroundStyle(bad ? .orange : .secondary)
                }
            }
            Spacer()
            Button(quota.needsLogin(p) ? "登录…" : "重新登录…") {
                if LoginLauncher.open(p) { quota.refreshSoon() } else { loginFailed = name }
            }
        }
    }

    @ViewBuilder private func quotaRow(_ id: String) -> some View {
        let selected = settings.quotaSelected.contains(id)
        let full = settings.quotaSelected.count >= QuotaSelection.maxItems
        let provider = id.hasPrefix("claude.") ? "Claude" : "Codex"
        let sameProvider = settings.quotaSelected.filter { $0.hasPrefix(provider.lowercased() + ".") }.count
        let blocked = !selected && (full || sameProvider >= 4)
        HStack {
            Toggle(isOn: Binding(
                get: { selected },
                set: { _ in
                    if let next = QuotaSelection.toggling(id, in: settings.quotaSelected) { settings.quotaSelected = next }
                })) {
                Text("\(provider) · \(settings.quotaTitles[id] ?? QuotaStore.fallbackTitle(id))")
            }
            .disabled(blocked)
            Spacer()
            if blocked {
                Text(full ? "最多同时显示 6 项" : "每个来源最多 4 项").font(.caption).foregroundStyle(.secondary)
            }
            if selected, let i = settings.quotaSelected.firstIndex(of: id) {
                Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0).buttonStyle(.borderless)
                Button { move(i, 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(i == settings.quotaSelected.count - 1).buttonStyle(.borderless)
            }
        }
    }

    private func move(_ i: Int, _ d: Int) {
        var s = settings.quotaSelected
        let j = i + d
        guard s.indices.contains(j) else { return }
        s.swapAt(i, j)
        settings.quotaSelected = s
    }

    private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 背景方案的小样：底色 + 一块卡片 + 两个圆点，选中时描一圈强调色。
struct BackdropSwatch: View {
    let backdrop: Backdrop
    let palette: Palette
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if backdrop == .system {
                        HStack(spacing: 0) { preview(.night); preview(.light) }
                    } else {
                        preview(palette)
                    }
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1))
                Text(backdrop == .night ? "夜读" : (backdrop == .system ? "跟随系统" : backdrop.title))
                    .lineLimit(1)
                    .font(.caption).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func preview(_ p: Palette) -> some View {
        ZStack(alignment: .bottomLeading) {
            p.bg
            RadialGradient(colors: [Color(hex: 0xFF6A3D, p.glowWarm * 2), .clear], center: .init(x: 0.2, y: 0.6), startRadius: 0, endRadius: 60)
            RadialGradient(colors: [Color(hex: 0x2F7BFF, p.glowCool * 2), .clear], center: .init(x: 0.85, y: 0.5), startRadius: 0, endRadius: 50)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [p.panelTop, p.panelBottom], startPoint: .top, endPoint: .bottom))
                .overlay(HStack(spacing: 4) {
                    Circle().fill(Color(hex: 0xFF9500)).frame(width: 9, height: 9)
                    Circle().fill(Color(hex: 0x2F7BFF)).frame(width: 9, height: 9)
                    Capsule().fill(p.text.opacity(0.7)).frame(width: 18, height: 4)
                })
                .frame(width: 54, height: 26)
                .padding(8)
        }
    }
}
