import SwiftUI
import AppKit

/// 音乐页：播放中 / 暂停 / 未播放 / 其它应用在播放；lyricsMode 为真时换成歌词模式。
struct MusicPage: View {
    let vm: MusicVM
    let lyricsMode: Bool
    let actions: MusicActions
    let onSelectPage: (Int) -> Void
    var showTranslation = false

    var body: some View {
        switch vm.phase {
        case .track:
            if lyricsMode && !vm.lyrics.isEmpty { lyricsBody } else { trackBody }
        case .idle:
            idleBody(hint: "在网易云音乐或 Apple Music 播放后显示")
        case .otherApp(let name):
            idleBody(hint: "\(name) 正在播放", note: "副屏只显示允许的播放来源，可在设置里更改")
        }
    }

    // MARK: 播放中

    private var trackBody: some View {
        ZStack(alignment: .topLeading) {
            CoverBackground(backdrop: vm.backdrop, palette: vm.palette)
            TopBar(active: 0, onSelect: onSelectPage) { ClockLabel(now: vm.now) }
            HStack(alignment: .top, spacing: 56) {
                CoverView(art: vm.artwork, side: 528, glow: vm.palette.glow, dimmed: !vm.playing)
                VStack(spacing: 0) {
                    // 歌名 + 歌手，整块可点：点一下进歌词模式。顶到封面上沿，歌手名长的话折成两行。
                    Button(action: actions.toggleLyrics) {
                        VStack(alignment: .leading, spacing: 14) {
                            // 方圆体的英文偏宽，英文字距收一点，长英文歌名第一行能多放一个词。
                            tx(vm.title, T.Size.trackTitle, cjkTracking: -2, latinTracking: -1.2)
                                .foregroundStyle(T.text).lineLimit(2).minimumScaleFactor(0.6)
                                .fixedSize(horizontal: false, vertical: true)
                            tx(vm.artist, T.Size.trackArtist, bold: false).foregroundStyle(T.textOnCover).lineLimit(2).lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 6)
                    Spacer(minLength: 16)
                    ProgressBar(vm: vm, height: 10)
                    // 播放控制居中；左边歌词、右边红心，两边对称。
                    HStack(spacing: 0) {
                        IconButton(symbol: "text.quote", size: 88, icon: 36, enabled: !vm.lyrics.isEmpty, action: actions.toggleLyrics)
                            .padding(.leading, -24)
                        Spacer(minLength: 0)
                        TransportControls(vm: vm, actions: actions)
                        Spacer(minLength: 0)
                        LikeButton(size: 108, liked: vm.liked, action: actions.like)
                            .padding(.trailing, -28)
                    }
                    .padding(.top, 14)
                }
                .frame(width: 584, height: 528)
            }
            .padding(.leading, 56).padding(.top, 128)
        }
        .frame(width: 1280, height: 720)
    }

    // MARK: 歌词模式

    private var lyricsBody: some View {
        ZStack(alignment: .topLeading) {
            CoverBackground(backdrop: vm.backdrop, palette: vm.palette, center: UnitPoint(x: 0.18, y: 0.45))
            TopBar(active: 0, onSelect: onSelectPage) { ClockLabel(now: vm.now) }
            HStack(alignment: .top, spacing: 64) {
                Button(action: actions.toggleLyrics) {
                    VStack(alignment: .leading, spacing: 0) {
                        CoverView(art: vm.artwork, side: 360, radius: 26, glow: vm.palette.glow, dimmed: !vm.playing)
                        tx(vm.title, T.Size.lyricsTitle, cjkTracking: -0.5).foregroundStyle(T.text).lineLimit(1).padding(.top, 30)
                        tx(vm.artist, T.Size.lyricsArtist, bold: false).foregroundStyle(T.textOnCover).lineLimit(1).padding(.top, 8)
                    }
                    .frame(width: 360, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                lyricColumn
                    .frame(width: 744, height: 440, alignment: .leading)
                    .padding(.top, 8)
            }
            .padding(.leading, 56).padding(.top, 128)
            HStack(spacing: 28) {
                ProgressBar(vm: vm, height: 6).frame(width: 520)
                Spacer()
                // 歌词按钮在这里是亮的，再点一下回到普通页（点封面也行）。
                IconButton(symbol: "text.quote", size: 88, icon: 36, tint: T.onBackground(vm.palette.progressStart), action: actions.toggleLyrics)
                TransportControls(vm: vm, actions: actions, large: false)
                LikeButton(size: 100, liked: vm.liked, action: actions.like)
            }
            .padding(.horizontal, 56)
            .frame(width: 1280)
            .offset(y: 600)
        }
        .frame(width: 1280, height: 720)
    }

    /// 固定行高、偏移居中（不用 ScrollView，离屏快照才画得出来）。
    private var lyricColumn: some View {
        let idx = vm.currentLine ?? 0
        let lines = (-2...2).map { d -> (Int, String?) in
            let i = idx + d
            return (d, vm.lyrics.indices.contains(i) ? vm.lyrics[i].text : nil)
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(lines, id: \.0) { d, text in
                if d == 0 {
                    let translation = showTranslation && vm.lyrics.indices.contains(idx) ? vm.lyrics[idx].translation : nil
                    VStack(alignment: .leading, spacing: 4) {
                        tx(text ?? "", T.Size.lyricCurrent, cjkTracking: -1).foregroundStyle(T.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .shadow(color: vm.palette.glow.opacity(0.35), radius: 16)
                        if let translation {
                            tx(translation, T.Size.lyricNext, bold: false).foregroundStyle(T.text2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .frame(height: translation == nil ? 92 : 132, alignment: .leading)
                } else {
                    tx(text ?? "", T.Size.lyricOther, bold: false).foregroundStyle(T.text.opacity(abs(d) == 1 ? 0.42 : 0.2))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(height: 64, alignment: .leading)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: idx)
    }

    // MARK: 未播放 / 其它应用在播放

    private func idleBody(hint: String, note: String? = nil) -> some View {
        ZStack(alignment: .topLeading) {
            AlbumGlow(palette: .neutral, center: UnitPoint(x: 0.5, y: 0.5))
            TopBar(active: 0, onSelect: onSelectPage) {
                tx("音乐", T.Size.pageTitle).foregroundStyle(T.text)
            }
            VStack(spacing: 0) {
                num(TimeText.clock(vm.now), T.Size.idleClock, weight: .heavy).foregroundStyle(T.text)
                tx(TimeText.date(vm.now), T.Size.idleDate, bold: false).foregroundStyle(T.text2).padding(.top, 4)
                HStack(spacing: 12) {
                    Image(systemName: "music.note").font(.system(size: 26, weight: .bold)).foregroundStyle(T.text2)
                    tx(hint, T.Size.artist, bold: false).foregroundStyle(T.text.opacity(0.8))
                }
                .padding(.top, 44)
                if let note {
                    tx(note, T.Size.meta, bold: false).foregroundStyle(T.text3).padding(.top, 12)
                }
            }
            .frame(width: 1280, height: 720)
        }
        .frame(width: 1280, height: 720)
    }
}
