import Foundation
import Combine

/// 扫 ~/.claude/projects 与 ~/.codex/sessions 下的会话记录，按天、按模型汇总成美元。
/// 记录很大（一个月几个 GB），所以按文件做增量：缓存每个文件解析到的字节位置和汇总行，
/// 下次只读新追加的部分；缓存存在 ~/Library/Application Support/Reverie/cost-cache.json。
/// 只看最近 35 天改过的文件（够覆盖「本月」）。
final class CostStore: ObservableObject {
    @Published private(set) var summary: CostSummary?
    @Published private(set) var scanning = false
    @Published private(set) var updatedAt: Date?

    private(set) var period: CostPeriod = .week
    private var cache = Cache()
    private var timer: Timer?
    private var inFlight = false
    private var lastScan: Date?
    private var loggedUnpriced: Set<String> = []
    private let queue = DispatchQueue(label: "reverie.cost", qos: .utility)

    private struct FileState: Codable {
        var size: Int
        var mtime: Double
        var parsed: Int              // 已解析到的字节位置（只到最后一个换行）
        var rows: [CostRow]
        var seen: [String] = []      // Claude：最近的消息 key，跨块去重
        var model: String? = nil     // Codex：最近一次 turn_context 的模型
    }
    private struct Cache: Codable {
        var version = 2
        var pricing = Pricing.version
        var files: [String: FileState] = [:]
    }

    static let roots: [(CostProvider, String)] = [
        (.claude, NSHomeDirectory() + "/.claude/projects"),
        (.codex, NSHomeDirectory() + "/.codex/sessions"),
    ]
    static let cachePath = NSHomeDirectory() + "/Library/Application Support/Reverie/cost-cache.json"
    static let lookbackDays = 35

    func start(period: CostPeriod) {
        self.period = period
        queue.async { [weak self] in
            guard let self else { return }
            let loaded = Self.loadCache()
            DispatchQueue.main.async { self.cache = loaded; self.publish(); self.rescan() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.rescan() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func setPeriod(_ p: CostPeriod) {
        guard p != period else { return }
        period = p
        publish()
    }

    /// 翻到消费页时离上次扫描超过 2 分钟就再扫一次。
    func rescanIfOld() {
        if let t = lastScan, Date().timeIntervalSince(t) < 120 { return }
        rescan()
    }

    func rescan() {
        guard !inFlight else { return }
        inFlight = true
        scanning = summary == nil
        lastScan = Date()
        let snapshot = cache
        queue.async { [weak self] in
            let (next, unpriced) = Self.scan(from: snapshot)
            Self.saveCache(next)
            DispatchQueue.main.async {
                guard let self else { return }
                self.cache = next
                self.inFlight = false
                self.scanning = false
                self.updatedAt = Date()
                for m in unpriced.subtracting(self.loggedUnpriced) { Self.log("no price for model \(m); skipped") }
                self.loggedUnpriced.formUnion(unpriced)
                self.publish()
            }
        }
    }

    private func publish() {
        guard !cache.files.isEmpty else { return }
        let rows = cache.files.values.flatMap(\.rows)
        summary = CostSummary.build(rows: rows, period: period, now: Date())
    }

    // MARK: 扫描（后台队列）

    private static func scan(from old: Cache) -> (Cache, Set<String>) {
        var cache = old
        if cache.pricing != Pricing.version || cache.version != Cache().version { cache = Cache() }   // 价格表变了，全部重算
        var unpriced: Set<String> = []
        let cutoff = Date().addingTimeInterval(-Double(lookbackDays) * 86_400)
        var live: Set<String> = []
        let fm = FileManager.default
        for (provider, root) in roots {
            guard let en = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                         options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in en where url.pathExtension == "jsonl" {
                guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = attrs.contentModificationDate, let size = attrs.fileSize, mtime >= cutoff else { continue }
                let path = url.path
                live.insert(path)
                var state = cache.files[path] ?? FileState(size: 0, mtime: 0, parsed: 0, rows: [])
                if state.size == size && state.mtime == mtime.timeIntervalSince1970 { continue }
                if size < state.parsed { state = FileState(size: 0, mtime: 0, parsed: 0, rows: []) }   // 文件被重写，从头来
                parse(url: url, provider: provider, from: state.parsed, into: &state, unpriced: &unpriced)
                state.size = size
                state.mtime = mtime.timeIntervalSince1970
                cache.files[path] = state
            }
        }
        for path in cache.files.keys where !live.contains(path) { cache.files[path] = nil }   // 太旧或删了的文件不再留
        return (cache, unpriced)
    }

    private static func parse(url: URL, provider: CostProvider, from offset: Int, into state: inout FileState, unpriced: inout Set<String>) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? h.close() }
        var position = offset
        try? h.seek(toOffset: UInt64(offset))
        var pending = Data()
        let chunkSize = 4 << 20
        while true {
            let chunk = (try? h.read(upToCount: chunkSize)) ?? Data()
            if chunk.isEmpty { break }
            pending.append(chunk)
            let (lines, consumed) = pending.splitLines()
            let events: [CostEvent]
            switch provider {
            case .claude: events = CostParse.claude(lines: lines, seen: &state.seen)
            case .codex: events = CostParse.codex(lines: lines, model: &state.model)
            }
            let rows = CostParse.rows(events, unpriced: &unpriced)
            merge(rows, into: &state.rows)
            pending.removeSubrange(0..<consumed)
            position += consumed
            if chunk.count < chunkSize { break }
        }
        state.parsed = position
    }

    private static func merge(_ rows: [CostRow], into target: inout [CostRow]) {
        for r in rows {
            if let i = target.firstIndex(where: { $0.day == r.day && $0.provider == r.provider && $0.model == r.model }) {
                target[i].input += r.input; target[i].cacheWrite += r.cacheWrite; target[i].cacheRead += r.cacheRead
                target[i].output += r.output; target[i].usd += r.usd; target[i].requests += r.requests
            } else {
                target.append(r)
            }
        }
    }

    // MARK: 缓存文件

    private static func loadCache() -> Cache {
        guard let data = FileManager.default.contents(atPath: cachePath),
              let c = try? JSONDecoder().decode(Cache.self, from: data) else { return Cache() }
        return c
    }

    private static func saveCache(_ c: Cache) {
        let dir = (cachePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(c) { try? data.write(to: URL(fileURLWithPath: cachePath), options: .atomic) }
    }

    private static func log(_ e: String) {
        let dir = NSHomeDirectory() + "/Library/Logs/Reverie"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let line = ISO8601DateFormatter().string(from: Date()) + " " + e + "\n"
        let path = dir + "/cost.log"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }
}
