// reverie:logic 纯逻辑，单元测试会编进来，不许依赖 SwiftUI / AppKit。
import Foundation

// MARK: - Helpers
func fmtTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s.rounded())
    return String(format: "%d:%02d", t / 60, t % 60)
}

// Parse an LRC string into time-sorted (seconds, text) lines.
func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
    var out: [(Double, String)] = []
    for raw in lrc.split(separator: "\n") {
        let line = String(raw)
        var stamps: [Double] = []
        var rest = line
        while rest.first == "[" {
            guard let close = rest.firstIndex(of: "]") else { break }
            let tag = String(rest[rest.index(after: rest.startIndex)..<close])
            let parts = tag.split(separator: ":")
            if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                stamps.append(m * 60 + s)
            }
            rest = String(rest[rest.index(after: close)...])
        }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !stamps.isEmpty, !text.isEmpty else { continue }
        for t in stamps { out.append((t, text)) }
    }
    return out.sorted { $0.0 < $1.0 }
}

/// 网易云歌词开头常有「作词 : xx」「作曲 : xx」这类署名行，不当歌词显示。
/// 只认「署名词 + 冒号」开头的行，正文里带冒号的歌词不受影响。
func isCreditLine(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard let colon = t.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
    let head = t[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
    let credits = ["作词", "作曲", "编曲", "制作人", "制作", "监制", "混音", "母带", "录音", "和声", "吉他", "贝斯", "鼓", "键盘",
                   "弦乐", "出品", "发行", "企划", "统筹", "op", "sp", "lyricist", "lyrics", "composer", "arranger", "producer",
                   "作詞", "作曲者", "編曲", "词", "曲"]
    return credits.contains(head)
}

/// 歌词去掉署名行，再按时间对上翻译（网易云 tlyric 的时间戳和原文一致，差 0.3 秒内算同一句）。
func buildLyrics(lrc: String, translation: String?) -> [(time: Double, text: String, translation: String?)] {
    let lines = parseLRC(lrc).filter { !isCreditLine($0.text) }
    let trans = translation.map(parseLRC)?.filter { !isCreditLine($0.text) } ?? []
    var j = 0
    return lines.map { line in
        while j < trans.count && trans[j].time < line.time - 0.3 { j += 1 }
        if j < trans.count && abs(trans[j].time - line.time) <= 0.3 {
            let t = trans[j].text
            j += 1
            return (line.time, line.text, t == line.text ? nil : t)
        }
        return (line.time, line.text, nil)
    }
}
