import SwiftUI
import AppKit

/// 网易云公开接口：按「歌名 + 歌手」匹配歌曲，拿 1024px 封面与带时间轴的歌词；
/// 以及从网易云本地 SQLite 缓存读「我喜欢的音乐」。
enum NeteaseService {
    struct Match { let id: Int; let picURL: URL? }

    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 12
        return req
    }

    static func match(title: String, artist: String, completion: @escaping (Match?) -> Void) {
        let query = (title + " " + artist).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://music.163.com/api/cloudsearch/pc?s=\(query)&type=1&limit=5") else { completion(nil); return }
        URLSession.shared.dataTask(with: request(url)) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let songs = (obj["result"] as? [String: Any])?["songs"] as? [[String: Any]], !songs.isEmpty else {
                completion(nil); return
            }
            let lt = title.lowercased(), la = artist.lowercased()
            func artistOf(_ s: [String: Any]) -> String {
                (((s["ar"] as? [[String: Any]]) ?? (s["artists"] as? [[String: Any]]) ?? [])
                    .compactMap { $0["name"] as? String }).joined(separator: "/").lowercased()
            }
            let best = songs.first { ($0["name"] as? String)?.lowercased() == lt && !la.isEmpty && (artistOf($0).contains(la) || la.contains(artistOf($0))) }
                ?? songs.first { ($0["name"] as? String)?.lowercased() == lt }
                ?? songs[0]
            guard let id = best["id"] as? Int else { completion(nil); return }
            var pic = ((best["al"] as? [String: Any]) ?? (best["album"] as? [String: Any]))?["picUrl"] as? String
            if let p = pic, p.hasPrefix("http://") { pic = "https://" + p.dropFirst(7) }
            completion(Match(id: id, picURL: pic.flatMap { URL(string: $0 + "?param=1024y1024") }))
        }.resume()
    }

    static func image(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: request(url)) { data, _, _ in
            completion(data.flatMap { NSImage(data: $0) })
        }.resume()
    }

    static func lyrics(id: Int, completion: @escaping ([LyricLine]) -> Void) {
        guard let url = URL(string: "https://music.163.com/api/song/lyric?id=\(id)&lv=1&kv=1&tv=-1") else { completion([]); return }
        URLSession.shared.dataTask(with: request(url)) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lrc = (obj["lrc"] as? [String: Any])?["lyric"] as? String else { completion([]); return }
            let tlrc = (obj["tlyric"] as? [String: Any])?["lyric"] as? String
            completion(buildLyrics(lrc: lrc, translation: tlrc).map { LyricLine(time: $0.time, text: $0.text, translation: $0.translation) })
        }.resume()
    }

    /// 「我喜欢的音乐」的歌曲 id（网易云本地明文缓存，无需登录）。读不到返回 nil。
    static func likedSongIDs() -> Set<String>? {
        let base = NSHomeDirectory() + "/Library/Containers/com.netease.163music/Data/Documents/storage/sqlite_storage.sqlite3"
        let fm = FileManager.default
        guard fm.fileExists(atPath: base) else { return nil }
        let tmp = NSTemporaryDirectory() + "reverie_ne_store.sqlite3"
        for ext in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: tmp + ext)
            try? fm.copyItem(atPath: base + ext, toPath: tmp + ext)
        }
        func q(_ sql: String) -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            p.arguments = [tmp, sql]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return "" }
            let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let pid = q("SELECT id FROM historyPlaylists WHERE jsonStr LIKE '%喜欢的音乐\"%' LIMIT 1;")
        guard !pid.isEmpty, pid.allSatisfy(\.isNumber) else { return nil }
        let json = q("SELECT jsonStr FROM playlistTrackIds WHERE id='\(pid)';")
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["trackIds"] as? [[String: Any]] else { return nil }
        let ids = Set(arr.compactMap { ($0["id"] as? String) ?? ($0["id"] as? Int).map(String.init) })
        return ids.isEmpty ? nil : ids
    }
}

/// 从封面取氛围光与进度条颜色：按饱和度与亮度加权挑主导色，避开平均色发灰。
enum AlbumPaletteExtractor {
    static func extract(_ image: NSImage) -> AlbumPalette? {
        let side = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var buckets = [(w: Double, h: Double, s: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        for x in 0..<side { for y in 0..<side {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let w = Double(s) * Double(b) * Double(b) + 0.001
            let i = min(11, Int(h * 12))
            buckets[i].w += w; buckets[i].h += Double(h) * w; buckets[i].s += Double(s) * w; buckets[i].b += Double(b) * w
        }}
        let ranked = buckets.enumerated().filter { $0.element.w > 0.01 }.sorted { $0.element.w > $1.element.w }
        guard let top = ranked.first?.element, top.w > 0.3 else { return nil }   // 灰阶封面：用中性色
        func color(_ k: (w: Double, h: Double, s: Double, b: Double), sat: Double, bri: Double) -> Color {
            Color(hue: k.h / k.w, saturation: min(1, max(0.35, k.s / k.w * sat)), brightness: bri)
        }
        let second = ranked.dropFirst().first { abs($0.offset - ranked[0].offset) >= 2 }?.element ?? top
        return AlbumPalette(glow: color(top, sat: 1.1, bri: 0.95),
                            glow2: color(second, sat: 0.9, bri: 0.5),
                            progressStart: color(top, sat: 1.0, bri: 1.0),
                            progressEnd: color(top, sat: 0.45, bri: 1.0))
    }
}
