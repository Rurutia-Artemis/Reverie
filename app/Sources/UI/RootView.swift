import SwiftUI
import AppKit

/// 副屏上的根视图：只看设置（翻页、歌词模式）；两页各自订阅自己的数据、按需刷新。
struct RootView: View {
    @ObservedObject var settings: SettingsStore
    let music: NowPlayingStore
    let quota: QuotaStore
    let cost: CostStore
    var fixedNow: Date? = nil
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
    @ObservedObject var chrome = ChromeState()

    static let canvas = CGSize(width: 1280, height: 720)

    var body: some View {
        // 界面按 1280×720 排版，显示时等比缩放到面板大小；比例不同的屏上下或左右留底色。
        GeometryReader { g in
            let s = min(g.size.width / Self.canvas.width, g.size.height / Self.canvas.height)
            ZStack {
                T.bg
                canvasBody
                    .frame(width: Self.canvas.width, height: Self.canvas.height)
                    .scaleEffect(s)
                    .frame(width: g.size.width, height: g.size.height)
            }
        }
        .id(settings.renderKey)
    }

    private var canvasBody: some View {
        ZStack {
            if settings.page == .music {
                MusicHost(settings: settings, music: music, fixedNow: fixedNow, onSelect: select)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -40)), removal: .opacity.combined(with: .offset(x: -40))))
            } else if settings.page == .quota {
                QuotaHost(settings: settings, quota: quota, fixedNow: fixedNow, onSelect: select)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 40)), removal: .opacity.combined(with: .offset(x: 40))))
            } else {
                CostHost(settings: settings, cost: cost, fixedNow: fixedNow, onSelect: select)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 40)), removal: .opacity.combined(with: .offset(x: 40))))
            }
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .background(T.bg)
        .animation(.easeOut(duration: 0.25), value: settings.page)
        .environment(\.chromeVisible, chrome.visible)
    }

    private func select(_ i: Int) {
        if i == 9 { openSettings(); return }
        if i == 8 { quit(); return }
        withAnimation(.easeOut(duration: 0.25)) { settings.page = Page(rawValue: i) ?? .music }
    }
}

/// 音乐页：每秒刷新一次（时钟、进度、歌词）。
private struct MusicHost: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var music: NowPlayingStore
    let fixedNow: Date?
    let onSelect: (Int) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let vm = music.vm(now: fixedNow ?? ctx.date)
            ZStack {
                MusicPage(vm: vm, lyricsMode: settings.lyricsMode, actions: actions(for: vm), onSelectPage: onSelect,
                          showTranslation: settings.lyricsTranslation)
                if let t = music.toast {
                    VStack {
                        Spacer()
                        tx(t, T.Size.meta).foregroundStyle(T.text)
                            .padding(.horizontal, 26).padding(.vertical, 12)
                            .background(CapsulePanel())
                            .padding(.bottom, 26)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: music.toast)
            .animation(.easeInOut(duration: 0.3), value: settings.lyricsMode)
        }
    }

    /// 按钮带着「界面上显示的这首歌」，和当前播放对不上就不执行。
    private func actions(for vm: MusicVM) -> MusicActions {
        let id = vm.identity
        return MusicActions(prev: { music.prev(expected: id) }, playPause: { music.playPause(expected: id) },
                            next: { music.next(expected: id) }, like: { music.toggleLike(expected: id) },
                            toggleLyrics: {
                                // 没找到歌词时切过去也只能看到原页面，给个提示。
                                if vm.lyrics.isEmpty && !settings.lyricsMode { music.showToast("这首歌没有找到歌词") }
                                else { settings.lyricsMode.toggle() }
                            })
    }
}

/// 额度页：倒计时与「更新于」按分钟变化，20 秒刷新一次就够。
private struct QuotaHost: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var quota: QuotaStore
    let fixedNow: Date?
    let onSelect: (Int) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            QuotaPage(vm: quota.vm(selected: settings.quotaSelected, titles: settings.quotaTitles,
                                   showUsed: settings.quotaShowUsed, now: fixedNow ?? ctx.date),
                      onSelectPage: onSelect)
        }
    }
}

/// 消费页：数字按天变化，一分钟刷一次就够。
private struct CostHost: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var cost: CostStore
    let fixedNow: Date?
    let onSelect: (Int) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = fixedNow ?? ctx.date
            var vm = cost.summary.map { CostVM.from($0, updatedAt: cost.updatedAt, now: now) } ?? CostVM()
            let _ = { vm.scanning = cost.scanning; vm.period = settings.costPeriod }()
            CostPage(vm: vm, onSelectPage: onSelect, onPeriod: { settings.costPeriod = $0 })
        }
    }
}
