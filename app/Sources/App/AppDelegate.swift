import SwiftUI
import AppKit
import Combine
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = SettingsStore()
    lazy var music = NowPlayingStore(allowed: settings.allowedSources)
    let quota = QuotaStore()
    let cost = CostStore()
    let app = AppModel()

    private var panel: SubscreenPanel!
    private var machine = WindowStateMachine()
    private var target: DisplayInfo?
    private var evictor: WindowEvictor?
    private var statusItem: NSStatusItem?
    private let settingsWindow = SettingsWindowController()
    private var hotKey: HotKey?
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var selfCheck: Timer?
    private var swipeX: CGFloat = 0
    private var sigterm: DispatchSourceSignal?
    private var appearanceObservation: NSKeyValueObservation?
    private var autoSwitchedToQuota = false
    private let edgeGuard = DockEdgeGuardView()
    private let hoverZone = HoverZoneView()
    private let chrome = ChromeState()

    func applicationDidFinishLaunching(_ n: Notification) {
        let env = ProcessInfo.processInfo.environment
        if let out = env["REVERIE_SNAPSHOT"] { liveSnapshot(to: out, env: env); return }

        // 收到 SIGTERM（部署脚本、launchctl bootout）时走正常退出，停掉 stream 子进程。
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { NSApp.terminate(nil) }
        term.resume()
        sigterm = term

        guard SingleInstance.acquire() else {
            NSLog("Reverie 已在运行，这个副本退出")
            exit(0)
        }

        panel = SubscreenPanel()
        panel.contentView = FirstMouseHostingView(rootView: RootView(settings: settings, music: music, quota: quota, cost: cost,
                                                                     openSettings: { [weak self] in self?.openSettings() },
                                                                     quit: { NSApp.terminate(nil) },
                                                                     chrome: chrome))
        if let host = panel.contentView {
            edgeGuard.frame = host.bounds
            edgeGuard.autoresizingMask = [.width, .height]
            edgeGuard.targetBoundsCG = { [weak self] in self?.target.map { CGDisplayBounds($0.id) } }
            edgeGuard.isActive = { [weak self] in self?.settings.evictorEnabled ?? false }
            host.addSubview(edgeGuard)
            hoverZone.frame = host.bounds
            hoverZone.autoresizingMask = [.width, .height]
            hoverZone.onChange = { [weak self] on in self?.chrome.visible = on }
            host.addSubview(hoverZone)
        }
        music.start()
        quota.onItemsSeen = { [weak self] items in self?.mergeSeen(items) }
        quota.setInterval(minutes: settings.quotaRefreshMinutes)
        quota.start()
        cost.start(period: settings.costPeriod)

        app.repin = { [weak self] in self?.send(.repin) }
        app.displaysChanged = { [weak self] in self?.refreshTarget() }
        installStatusItem()
        installEvictor()
        installObservers()
        refreshTarget()

        selfCheck = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.runSelfCheck() }
        hotKey = HotKey(keyCode: HotKey.defaultKeyCode, modifiers: HotKey.defaultModifiers) { [weak self] in self?.togglePage() }

        // 「跟随系统」背景：系统切深色 / 浅色时跟着换。
        settings.systemIsDark = Self.systemIsDark()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.settings.systemIsDark = Self.systemIsDark() }
        }
        settings.$allowedSources.dropFirst().sink { [weak self] in self?.music.setAllowed($0) }.store(in: &bag)
        quota.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatusIcon() }.store(in: &bag)
        settings.$quotaRefreshMinutes.dropFirst().sink { [weak self] m in self?.quota.setInterval(minutes: m) }.store(in: &bag)
        // 没在放歌时自动翻到额度页（设置里打开才生效）；又开始放歌时翻回来，只翻回自己翻过去的那次。
        music.$state.map { $0 == .idle }.removeDuplicates()
            .debounce(for: .seconds(8), scheduler: RunLoop.main)
            .sink { [weak self] idle in self?.idleChanged(idle) }.store(in: &bag)
        // 翻到额度页时数据旧了就马上取一次。
        settings.$page.sink { [weak self] p in
            if p == .quota { self?.quota.refreshIfOld() }
            if p == .cost { self?.cost.rescanIfOld() }
        }.store(in: &bag)
        settings.$costPeriod.dropFirst().sink { [weak self] p in self?.cost.setPeriod(p) }.store(in: &bag)
        quota.planOverrides = [.claude: settings.claudePlanLabel, .codex: settings.codexPlanLabel]
        settings.$claudePlanLabel.dropFirst().sink { [weak self] v in self?.quota.planOverrides[.claude] = v }.store(in: &bag)
        settings.$codexPlanLabel.dropFirst().sink { [weak self] v in self?.quota.planOverrides[.codex] = v }.store(in: &bag)
        // 关掉「接管副屏」= 只观察不挪：副屏上有别的窗口时让出，不会把它盖住。
        settings.$evictorEnabled.dropFirst().sink { [weak self] on in self?.evictor?.movesWindows = on }.store(in: &bag)
        settings.$targetDisplayUUID.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.refreshTarget() } }.store(in: &bag)
        if env["REVERIE_SETTINGS"] != nil { openSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        music.stop()
        quota.stop()
        cost.stop()
        evictor?.stop()
    }

    // MARK: 窗口状态

    private func send(_ e: WindowEvent) {
        for a in machine.handle(e) {
            switch a {
            case .show(let frame):
                panel.setFrame(frame, display: true)
                panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
                panel.orderFrontRegardless()
            case .hide:
                panel.orderOut(nil)
            case .rescan:
                evictor?.scanNow()
            case .status(let s):
                app.status = s
                updateStatusIcon()
            }
        }
    }

    private func refreshTarget() {
        let displays = Displays.all()
        app.displays = displays
        let t = TargetResolver.resolve(displays: displays, preferredUUID: settings.targetDisplayUUID, preferredName: Config.targetScreenName)
        if settings.targetDisplayUUID == nil, let t { settings.targetDisplayUUID = t.uuid }   // 首次运行记住这块屏
        target = t
        app.targetName = t?.name
        send(.displaysChanged(target: t))
        edgeGuard.refresh()
    }

    private func scheduleReposition() {
        for delay in [0.1, 0.8, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshTarget() }
        }
    }

    private func runSelfCheck() {
        guard case .takeover(let f) = machine.mode else { return }
        send(.selfCheck(frameOK: panel.frame == f, visible: panel.isVisible && panel.occlusionState.contains(.visible)))
        let trusted = AXIsProcessTrusted()
        if trusted != app.axTrusted { app.axTrusted = trusted; updateStatusIcon() }
    }

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.scheduleReposition() })
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleReposition() })
        }
        // 副屏上两指横滑翻页。
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            guard let self, e.window === self.panel, e.hasPreciseScrollingDeltas else { return e }
            if e.phase == .began { self.swipeX = 0 }
            self.swipeX += e.scrollingDeltaX
            if abs(self.swipeX) > 80 {
                let next: Page = self.swipeX < 0 ? self.settings.page.next : self.settings.page.previous
                self.swipeX = 0
                if next != self.settings.page { withAnimation(.easeOut(duration: 0.25)) { self.settings.page = next } }
            }
            if e.phase == .ended || e.phase == .cancelled { self.swipeX = 0 }
            return e
        }) { monitors.append(m) }
    }

    private func installEvictor() {
        let ev = WindowEvictor(targetBoundsCG: { [weak self] in
            guard let id = self?.target?.id else { return nil }
            return CGDisplayBounds(id)
        }, mainVisibleCG: { Displays.primaryVisibleCG() })
        ev.onStuckChanged = { [weak self] stuck in
            var names: [String] = []
            for s in stuck where !names.contains(s.appName) { names.append(s.appName) }
            self?.send(.stuckChanged(apps: names))
        }
        ev.movesWindows = settings.evictorEnabled
        ev.start()
        evictor = ev
    }

    private func idleChanged(_ idle: Bool) {
        guard settings.idleShowsQuota else { autoSwitchedToQuota = false; return }
        if idle, settings.page == .music {
            autoSwitchedToQuota = true
            withAnimation(.easeOut(duration: 0.25)) { settings.page = .quota }
        } else if !idle, autoSwitchedToQuota {
            autoSwitchedToQuota = false
            if settings.page == .quota { withAnimation(.easeOut(duration: 0.25)) { settings.page = .music } }
        }
    }

    /// 菜单栏图标：和应用图标一样的「海上日落」线稿（模板图，跟着菜单栏深浅变色）。
    private static let menuBarGlyph: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            NSColor.black.set()
            // 半个太阳落在海平线上
            let sun = NSBezierPath()
            sun.appendArc(withCenter: NSPoint(x: 9, y: 8.2), radius: 5.2, startAngle: 0, endAngle: 180)
            sun.close()
            sun.fill()
            // 海平线和两道倒影
            for (y, w) in [(6.4, 16.0), (3.9, 9.0), (1.6, 4.5)] as [(CGFloat, CGFloat)] {
                let line = NSBezierPath(roundedRect: NSRect(x: 9 - w / 2, y: y - 0.8, width: w, height: 1.6), xRadius: 0.8, yRadius: 0.8)
                line.fill()
            }
            return true
        }
        img.accessibilityDescription = "Reverie"
        return img
    }()

    private static func systemIsDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: 页面

    private func togglePage() {
        withAnimation(.easeOut(duration: 0.25)) { settings.page = settings.page.next }
    }

    private func mergeSeen(_ items: [QuotaItem]) {
        let seen = QuotaSelection.mergeSeen(settings.quotaSeen, with: items)
        if seen != settings.quotaSeen { settings.quotaSeen = seen }
        var titles = settings.quotaTitles
        for i in items { titles[i.id] = i.title }
        if titles != settings.quotaTitles { settings.quotaTitles = titles }
    }

    // MARK: 菜单栏

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let alert = app.status != nil || !app.axTrusted || quota.needsLogin(.claude) || quota.needsLogin(.codex)
        let img = alert ? NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Reverie") : Self.menuBarGlyph
        img?.isTemplate = true
        statusItem?.button?.image = img
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let s = app.status {
            let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i)
        }
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "打开「辅助功能」授权…", action: #selector(openAccessibility), keyEquivalent: "").target = self
        }
        if quota.needsLogin(.claude) {
            menu.addItem(withTitle: "Claude Code 需要重新登录…", action: #selector(loginClaude), keyEquivalent: "").target = self
        }
        if quota.needsLogin(.codex) {
            menu.addItem(withTitle: "Codex 需要重新登录…", action: #selector(loginCodex), keyEquivalent: "").target = self
        }
        if menu.items.count > 0 { menu.addItem(.separator()) }
        let musicItem = menu.addItem(withTitle: "音乐", action: #selector(showMusic), keyEquivalent: "")
        musicItem.target = self; musicItem.state = settings.page == .music ? .on : .off
        let quotaItem = menu.addItem(withTitle: "额度", action: #selector(showQuota), keyEquivalent: "")
        quotaItem.target = self; quotaItem.state = settings.page == .quota ? .on : .off
        let costItem = menu.addItem(withTitle: "消费", action: #selector(showCost), keyEquivalent: "")
        costItem.target = self; costItem.state = settings.page == .cost ? .on : .off
        let lyrics = menu.addItem(withTitle: "歌词模式", action: #selector(toggleLyrics), keyEquivalent: "")
        lyrics.target = self; lyrics.state = settings.lyricsMode ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "重新固定到副屏", action: #selector(repin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Reverie", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func showMusic() { withAnimation { settings.page = .music } }
    @objc private func showQuota() { withAnimation { settings.page = .quota } }
    @objc private func showCost() { withAnimation { settings.page = .cost } }
    @objc private func toggleLyrics() { settings.lyricsMode.toggle() }
    @objc private func repin() { refreshTarget(); send(.repin) }
    @objc private func openSettings() { settingsWindow.show(settings: settings, app: app, quota: quota, cost: cost) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func loginClaude() { if LoginLauncher.open(.claude) { quota.refreshSoon() } }
    @objc private func loginCodex() { if LoginLauncher.open(.codex) { quota.refreshSoon() } }
    @objc private func openAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 实时快照（调试用：不拿锁、不起 stream、不上屏）

    private func liveSnapshot(to out: String, env: [String: String]) {
        if let t = env["REVERIE_THEME"].flatMap(Backdrop.init(rawValue:)) { T.palette = t.resolved(systemIsDark: true, custom: Color(hex: UInt32(env["REVERIE_CUSTOM"] ?? "", radix: 16) ?? 0x1B2A4A)) }   // 不写设置
        if env["REVERIE_PAGE"] == "quota" { settings.page = .quota }
        if env["REVERIE_PAGE"] == "music" { settings.page = .music }
        if env["REVERIE_PAGE"] == "cost" { settings.page = .cost }
        if env["REVERIE_LYRICS"] != nil { settings.lyricsMode = true }
        music.start(liveStream: false)
        quota.start()
        cost.start(period: settings.costPeriod)
        // 消费页第一次要扫完本机记录才有数，最多等 3 分钟。
        let deadline = Date().addingTimeInterval(180)
        @MainActor func render() {
            if settings.page == .cost, cost.summary == nil, Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { render() }
                return
            }
            // REVERIE_SNAPSHOT_SIZE=1920x1080 按别的分辨率出图，看缩放和留边。
            let parts = (env["REVERIE_SNAPSHOT_SIZE"] ?? "1280x720").split(separator: "x").compactMap { Double($0) }
            let size = parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 1280, height: 720)
            let r = ImageRenderer(content: RootView(settings: settings, music: music, quota: quota, cost: cost, fixedNow: Date())
                .frame(width: size.width, height: size.height))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out))
                print("snapshot written to \(out)")
            }
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { render() }
    }
}
