import SwiftUI
import AppKit
import Darwin

/// 播放数据：读 mediaremote-adapter 的 stream 与定期 get，经 PlaybackReducer 归并；
/// 换歌时查网易云高清封面与歌词；红心按来源分别处理（网易云 / Apple Music）。
final class NowPlayingStore: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var artwork: NSImage?
    @Published private(set) var palette: AlbumPalette = .neutral
    @Published private(set) var backdrop: CoverBackdrop?
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var liked: Bool? = nil
    @Published var toast: String? = nil

    private var reducer: PlaybackReducer
    private var identity: TrackIdentity?
    private var neteaseID: Int?
    private var neteaseLiked: Set<String> = []
    private var process: Process?
    private var streamPipe: Pipe?
    private var stoppingStream = false
    private var buffer = Data()
    private var lastStreamData = Date.distantPast
    private var timers: [Timer] = []
    private var pollInFlight = false
    private var toastWork: DispatchWorkItem?

    /// liveStream = false 时只轮询 get（快照调试用，不碰别的实例的 stream）。
    init(allowed: [String]) {
        reducer = PlaybackReducer(allowed: Set(allowed))
    }

    func start(liveStream: Bool = true) {
        poll(withArtwork: true)
        if liveStream { startProcess() }
        // stream 活跃时跳过兜底轮询；否则每 5 秒 get 一次。
        timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastStreamData) > 10 else { return }
            self.poll(withArtwork: false)
        })
        refreshLikes()
        timers.append(Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refreshLikes() })
    }

    func stop() {
        timers.forEach { $0.invalidate() }; timers = []
        stoppingStream = true
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        streamPipe = nil
        buffer.removeAll()
    }

    func setAllowed(_ allowed: [String]) {
        apply(reducer.setAllowed(Set(allowed), now: Date().timeIntervalSince1970))
    }

    // MARK: 界面数据

    func vm(now: Date) -> MusicVM {
        var vm = MusicVM()
        vm.now = now
        switch state {
        case .idle:
            vm.phase = .idle
        case .otherApp(let bundleID):
            vm.phase = .otherApp(name: SourceCatalog.displayName(for: bundleID))
        case .track(let t):
            vm.phase = .track
            vm.identity = t.identity
            vm.title = t.title
            vm.artist = t.artist
            vm.album = t.album
            vm.sourceName = SourceCatalog.displayName(for: t.sourceBundleID)
            vm.sourceDot = t.sourceBundleID == SourceFilterLogic.appleMusicBundleID ? Color(hex: 0xFA2D48)
                : t.sourceBundleID == SourceCatalog.neteaseBundleID ? Color(hex: 0xE83A3A) : Color(hex: 0x8E8E93)
            vm.elapsed = t.currentElapsed(now: now.timeIntervalSince1970)
            vm.duration = t.duration
            vm.playing = t.playing
            vm.liked = liked
            vm.artwork = artwork
            vm.palette = palette
            vm.backdrop = backdrop
            vm.lyrics = lyrics
            if !lyrics.isEmpty {
                var idx = 0
                for (i, l) in lyrics.enumerated() { if l.time <= vm.elapsed + 0.2 { idx = i } else { break } }
                vm.currentLine = idx
            }
        }
        return vm
    }

    // MARK: 操作（点击时再核对一次当前歌曲，避免控制到别的来源）

    /// expected 是界面上显示的那首歌；和当前播放对不上（刚换歌、换了来源）就不发命令。
    func playPause(expected: TrackIdentity?) {
        guard let e = expected, reducer.canControl(e) else { return }
        Controls.togglePlay()
    }
    func next(expected: TrackIdentity?) { guard let e = expected, reducer.canControl(e) else { return }; Controls.next() }
    func prev(expected: TrackIdentity?) { guard let e = expected, reducer.canControl(e) else { return }; Controls.previous() }

    func toggleLike(expected: TrackIdentity?) {
        guard let expected, case .track(let t) = state, reducer.canControl(expected) else { return }
        switch t.sourceBundleID {
        case SourceCatalog.neteaseBundleID:
            let wasLiked = liked == true
            DispatchQueue.global().async { [weak self] in
                let r = Controls.likeResult()
                DispatchQueue.main.async {
                    guard let self, self.identity == expected else { return }
                    if r.notAuthorized || !r.ok {
                        self.showToast("请在「辅助功能」里给 Reverie 授权")
                        Controls.promptAccessibility()
                        return
                    }
                    if let nid = self.neteaseID.map(String.init) {
                        if wasLiked { self.neteaseLiked.remove(nid) } else { self.neteaseLiked.insert(nid) }
                    }
                    self.liked = !wasLiked
                    self.showToast(wasLiked ? "已取消喜欢" : "已添加到我喜欢的音乐")
                }
            }
        case SourceFilterLogic.appleMusicBundleID:
            let title = t.title, artist = t.artist
            DispatchQueue.global().async { [weak self] in
                // 脚本里再核对一次当前曲目，换歌了就不改。
                let r = AppleMusicLike.toggleFavorited(expectedTitle: title, expectedArtist: artist)
                DispatchQueue.main.async {
                    guard let self, self.identity == expected else { return }
                    switch r {
                    case .success(let v): self.liked = v; self.showToast(v ? "已喜欢" : "已取消喜欢")
                    case .failure(.notAuthorized): self.showToast("请在「自动化」里允许 Reverie 控制「音乐」")
                    case .failure(.mismatch): self.showToast("歌曲已切换，没有改动")
                    case .failure: self.showToast("没能切换喜欢状态")
                    }
                }
            }
        default:
            break
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: w)
    }

    // MARK: 归并结果

    private func apply(_ r: ReduceResult) {
        state = r.state
        if case .track(let t) = r.state {
            if r.identityChanged || identity != t.identity {
                identity = t.identity
                artwork = nil
                palette = .neutral
            backdrop = nil
                backdrop = nil
                lyrics = []
                neteaseID = nil
                liked = likeSupported(t.sourceBundleID) ? false : nil
                fetchResources(for: t)
            }
        } else if r.identityChanged {
            identity = nil
            artwork = nil
            palette = .neutral
            lyrics = []
            liked = nil
        }
        if let b64 = r.artworkBase64, let raw = Data(base64Encoded: b64), let img = NSImage(data: raw), identity != nil {
            // 系统给的是缩略图；高清图到了会覆盖它。
            if artwork == nil || (artwork?.size.width ?? 0) < img.size.width { setArtwork(img) }
        }
    }

    private func likeSupported(_ bundleID: String) -> Bool {
        bundleID == SourceCatalog.neteaseBundleID || bundleID == SourceFilterLogic.appleMusicBundleID
    }

    private func setArtwork(_ img: NSImage) {
        artwork = img
        let token = identity
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = AlbumPaletteExtractor.extract(img) ?? .neutral
            let b = CoverBackdrop.make(from: img)
            DispatchQueue.main.async { if self?.identity == token { self?.palette = p; self?.backdrop = b } }
        }
    }

    private func fetchResources(for t: TrackState) {
        let token = t.identity
        NeteaseService.match(title: t.title, artist: t.artist) { [weak self] m in
            guard let m else { return }
            DispatchQueue.main.async {
                guard let self, self.identity == token else { return }
                self.neteaseID = m.id
                if t.sourceBundleID == SourceCatalog.neteaseBundleID { self.liked = self.neteaseLiked.contains(String(m.id)) }
            }
            NeteaseService.lyrics(id: m.id) { lines in
                DispatchQueue.main.async { if self?.identity == token { self?.lyrics = lines } }
            }
            if let url = m.picURL {
                NeteaseService.image(url) { img in
                    guard let img else { return }
                    DispatchQueue.main.async { if self?.identity == token { self?.setArtwork(img) } }
                }
            }
        }
        if t.sourceBundleID == SourceFilterLogic.appleMusicBundleID { refreshAppleMusicLike() }
    }

    private func refreshLikes() {
        DispatchQueue.global().async { [weak self] in
            let ids = NeteaseService.likedSongIDs()
            DispatchQueue.main.async {
                guard let self else { return }
                if let ids { self.neteaseLiked = ids }
                if case .track(let t) = self.state, t.sourceBundleID == SourceCatalog.neteaseBundleID, let nid = self.neteaseID {
                    self.liked = self.neteaseLiked.contains(String(nid))
                }
            }
        }
        if case .track(let t) = state, t.sourceBundleID == SourceFilterLogic.appleMusicBundleID { refreshAppleMusicLike() }
    }

    private func refreshAppleMusicLike() {
        let token = identity
        DispatchQueue.global().async { [weak self] in
            let r = AppleMusicLike.readFavorited()
            DispatchQueue.main.async {
                guard let self, self.identity == token, case .success(let v) = r else { return }
                self.liked = v
            }
        }
    }

    // MARK: 适配器进程

    private func poll(withArtwork: Bool) {
        guard !pollInFlight else { return }        // 同一时间只跑一个 get
        pollInFlight = true
        let started = Date()
        DispatchQueue.global().async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Config.perl)
            p.arguments = [Config.script, Config.framework, "get"] + (withArtwork ? [] : ["--no-artwork"])
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            var data = Data()
            var ok = false
            do {
                try p.run()
                data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                ok = p.terminationStatus == 0
            } catch {}
            // 只有合法的 JSON null 才表示「没在播」；执行失败、空输出、坏 JSON 一律丢弃，保留当前状态。
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parsed: [String: Any]?? = !ok || text.isEmpty ? nil
                : text == "null" ? .some(nil)
                : (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).map { .some($0) } ?? nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.pollInFlight = false
                guard let value = parsed else { return }
                // 查询期间 stream 已经送来更新的状态：这份 get 结果过时，丢弃。
                guard self.lastStreamData < started else { return }
                var r = self.reducer
                let result = r.reduceGet(value, now: Date().timeIntervalSince1970)
                self.reducer = r
                self.apply(result)
            }
        }
    }

    private func startProcess() {
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        streamPipe = nil
        terminateExistingAdapterStreams()
        stoppingStream = false

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Config.perl)
        p.arguments = [Config.script, Config.framework, "stream"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            self?.ingest(d)
        }
        p.terminationHandler = { [weak self, weak p] _ in
            DispatchQueue.main.async {
                guard let self, !self.stoppingStream else { return }
                if let ended = p, self.process !== ended { return }
                self.process = nil
                self.streamPipe = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, !self.stoppingStream else { return }
                    self.startProcess()
                }
            }
        }
        do {
            try p.run()
            process = p
            streamPipe = pipe
        } catch {
            NSLog("spawn failed: \(error)")
        }
    }

    /// 只有拿到单实例锁的进程才会调用：清掉上次崩溃残留的 stream。
    private func terminateExistingAdapterStreams() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        // 认所有 Reverie 自带适配器的 stream（不论从 /Applications 还是开发目录启动的），别的程序的适配器不碰。
        p.arguments = ["-u", String(getuid()), "-f", "/Reverie[^ ]*/mediaremote-adapter/bin/mediaremote-adapter\\.pl .* stream"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }
        let pgrepPID = p.processIdentifier
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let ownPID = getpid()
        let currentChildPID = process?.processIdentifier ?? -1
        for line in (String(data: data, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline) {
            guard let pid = pid_t(line.trimmingCharacters(in: .whitespaces)) else { continue }
            guard pid != ownPID, pid != currentChildPID, pid != pgrepPID else { continue }
            kill(pid, SIGTERM)
        }
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty, let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            DispatchQueue.main.async {
                self.lastStreamData = Date()
                var r = self.reducer
                let result = r.reduceStream(line: obj, now: Date().timeIntervalSince1970)
                self.reducer = r
                self.apply(result)
            }
        }
    }
}

enum SourceCatalog {
    static let neteaseBundleID = "com.netease.163music"

    private static let known: [(bundleID: String, fallbackName: String)] = [
        (neteaseBundleID, "网易云音乐"),
        ("com.apple.Music", "Apple Music"),
        ("com.spotify.client", "Spotify"),
        ("com.tencent.QQMusicMac", "QQ音乐")
    ]
    private static let knownNames = Dictionary(uniqueKeysWithValues: known)

    static func defaultChoices() -> [SourceApp] {
        known.map { SourceApp(bundleID: $0.bundleID, name: $0.fallbackName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func displayName(for bundleID: String, fallback: String? = nil) -> String {
        if let knownName = knownNames[bundleID] {
            return knownName
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return fallback ?? bundleID
    }
}
