// reverie:logic 纯逻辑，单元测试会编进来，不许依赖 SwiftUI / AppKit。
import Foundation

struct TrackIdentity: Hashable {
    let source: String
    let key: String
}

struct TrackState: Equatable {
    var identity: TrackIdentity
    var sourceBundleID: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsedAtSync: Double
    var syncWall: Double
    var playing: Bool
    var playbackRate: Double

    func currentElapsed(now: Double) -> Double {
        let elapsed = playing ? elapsedAtSync + (now - syncWall) * playbackRate : elapsedAtSync
        return min(max(elapsed, 0), duration > 0 ? duration : elapsed)
    }
}

enum PlaybackState: Equatable {
    case idle
    case otherApp(bundleID: String)
    case track(TrackState)
}

struct ReduceResult: Equatable {
    var state: PlaybackState
    var identityChanged: Bool
    var artworkBase64: String?
}

struct PlaybackReducer {
    private(set) var allowed: Set<String>
    private(set) var state: PlaybackState = .idle
    private var raw: [String: Any] = [:]
    // Keep the timing anchor even while the current source is filtered out.
    private var currentTrack: TrackState?

    init(allowed: Set<String>) {
        self.allowed = allowed
    }

    mutating func reduceStream(line: [String: Any], now: Double) -> ReduceResult {
        guard line["type"] as? String == "data",
              let diff = line["diff"] as? Bool,
              let payload = line["payload"] as? [String: Any] else {
            return ReduceResult(state: state, identityChanged: false, artworkBase64: nil)
        }
        return apply(payload, diff: diff, now: now)
    }

    mutating func reduceGet(_ object: Any?, now: Double) -> ReduceResult {
        apply(object as? [String: Any] ?? [:], diff: false, now: now)
    }

    mutating func setAllowed(_ allowed: Set<String>, now: Double) -> ReduceResult {
        self.allowed = allowed
        return publish(artwork: nil)
    }

    func canControl(_ identity: TrackIdentity) -> Bool {
        guard case .track(let track) = state else { return false }
        return track.identity == identity
    }

    private mutating func apply(_ payload: [String: Any], diff: Bool, now: Double) -> ReduceResult {
        if !diff { raw = [:] }
        for (key, value) in payload {
            if value is NSNull { raw.removeValue(forKey: key) }
            else { raw[key] = value }
        }

        guard let bundle = raw["bundleIdentifier"] as? String, !bundle.isEmpty,
              let title = raw["title"] as? String, !title.isEmpty else {
            currentTrack = nil
            return publish(artwork: payload["artworkData"] as? String)
        }
        let source = raw["parentApplicationBundleIdentifier"] as? String ?? bundle
        let artist = raw["artist"] as? String ?? ""
        let album = raw["album"] as? String ?? ""
        let duration = raw["duration"] as? Double ?? 0
        let key = raw["contentItemIdentifier"] as? String
            ?? raw["uniqueIdentifier"] as? String
            ?? "\(title)|\(artist)|\(album)|\(duration.rounded())"
        let identity = TrackIdentity(source: source, key: key)
        var track = TrackState(
            identity: identity, sourceBundleID: source, title: title, artist: artist,
            album: album, duration: duration, elapsedAtSync: 0, syncWall: now,
            playing: raw["playing"] as? Bool ?? false,
            playbackRate: raw["playbackRate"] as? Double ?? 1
        )
        if let elapsed = payload["elapsedTime"] as? Double {
            track.elapsedAtSync = elapsed
            track.syncWall = Self.timestamp(payload["timestamp"]) ?? now
        } else if let previous = currentTrack, previous.identity == identity {
            // 同一首歌的完整状态若没带 elapsedTime，也沿用旧的进度锚点，不归零。
            if diff, payload["elapsedTime"] is NSNull {
                // Explicit removal clears the old anchor as well as the raw key.
                track.elapsedAtSync = 0
            } else if track.playing != previous.playing || track.playbackRate != previous.playbackRate {
                track.elapsedAtSync = previous.currentElapsed(now: now)
            } else {
                track.elapsedAtSync = previous.elapsedAtSync
                track.syncWall = previous.syncWall
            }
        }
        currentTrack = track
        return publish(artwork: payload["artworkData"] as? String)
    }

    private mutating func publish(artwork: String?) -> ReduceResult {
        let next: PlaybackState
        if let track = currentTrack {
            next = SourceFilterLogic.allows(sourceBundleID: track.sourceBundleID, allowed: allowed)
                ? .track(track) : .otherApp(bundleID: track.sourceBundleID)
        } else {
            next = .idle
        }
        let changed: Bool
        switch (state, next) {
        case (.idle, .idle): changed = false
        case (.otherApp(let old), .otherApp(let new)): changed = old != new
        case (.track(let old), .track(let new)): changed = old.identity != new.identity
        default: changed = true
        }
        state = next
        return ReduceResult(state: next, identityChanged: changed, artworkBase64: artwork)
    }

    private static func timestamp(_ value: Any?) -> Double? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)?.timeIntervalSince1970
    }
}
