import Foundation

func runPlaybackReducerTests() {
    let netease = "com.netease.163music"
    let music = "com.apple.Music"
    let safari = "com.apple.Safari"
    let song: [String: Any] = [
        "bundleIdentifier": netease, "title": "Song", "artist": "Artist",
        "album": "Album", "duration": 180.0, "elapsedTime": 20.0,
        "playing": true, "playbackRate": 1.0
    ]
    let browser: [String: Any] = [
        "bundleIdentifier": "com.apple.WebKit.WebContent",
        "parentApplicationBundleIdentifier": safari,
        "title": "Video", "playing": true, "elapsedTime": 5.0
    ]
    func stream(_ payload: [String: Any], diff: Bool = true) -> [String: Any] {
        ["type": "data", "diff": diff, "payload": payload]
    }
    func track(_ result: ReduceResult) -> TrackState {
        guard case .track(let value) = result.state else {
            expectTrue(false, "expected track, got \(result.state)")
            fatalError("unreachable")
        }
        return value
    }

    var reducer = PlaybackReducer(allowed: [netease, music])
    expectEqual(reducer.state, .idle, "initial state")
    let first = reducer.reduceGet(song, now: 100)
    let oldIdentity = track(first).identity
    expectTrue(first.identityChanged, "idle to track changes identity")
    expectTrue(reducer.canControl(oldIdentity), "current track can be controlled")
    let filtered = reducer.reduceStream(line: stream(browser, diff: false), now: 101)
    expectEqual(filtered.state, .otherApp(bundleID: safari), "parent app is filtered")
    expectTrue(filtered.identityChanged, "track to other app changes identity")
    expectFalse(reducer.canControl(oldIdentity), "filtered source invalidates control")

    _ = reducer.reduceGet(song, now: 100)
    var musicSong = song
    musicSong["bundleIdentifier"] = music
    let sourceSwitch = reducer.reduceGet(musicSong, now: 101)
    expectTrue(sourceSwitch.identityChanged, "same title and artist at another source is a new track")
    expectEqual(track(sourceSwitch).identity.source, music, "identity includes source")
    let artistSwitch = reducer.reduceStream(line: stream(["artist": "Another artist"]), now: 102)
    expectTrue(artistSwitch.identityChanged, "fallback identity includes artist")
    expectEqual(track(artistSwitch).elapsedAtSync, 0, "new identity does not inherit raw old elapsed")
    expectFalse(reducer.canControl(track(sourceSwitch).identity), "stale click is rejected after song switch")
    expectTrue(reducer.canControl(track(artistSwitch).identity), "new identity can control")

    for null in [nil, NSNull()] as [Any?] {
        _ = reducer.reduceGet(song, now: 100)
        let cleared = reducer.reduceGet(null, now: 101)
        expectEqual(cleared.state, .idle, "get null clears track")
        expectTrue(cleared.identityChanged, "track to idle changes identity")
        expectFalse(reducer.canControl(oldIdentity), "idle cannot control old track")
        let orphanDiff = reducer.reduceStream(line: stream(["playing": true]), now: 102)
        expectEqual(orphanDiff.state, .idle, "null clears raw identity too")
        expectFalse(orphanDiff.identityChanged, "idle stays idle")
    }
    _ = reducer.reduceGet(song, now: 100)
    expectEqual(reducer.reduceStream(line: stream([:], diff: false), now: 101).state,
                .idle, "empty full stream clears state")
    _ = reducer.reduceGet(song, now: 100)
    expectEqual(reducer.reduceStream(line: stream(["title": NSNull()]), now: 101).state,
                .idle, "null removes title")
    expectEqual(reducer.setAllowed([], now: 102).state, .idle, "allowlist cannot restore a removed title")
    _ = reducer.reduceGet(song, now: 100)
    expectEqual(reducer.reduceGet(["title": "No source"], now: 101).state,
                .idle, "get fully replaces old source")
    expectEqual(reducer.reduceGet(["bundleIdentifier": music, "title": ""], now: 102).state,
                .idle, "empty title is idle")

    _ = reducer.reduceGet(song, now: 100)
    let pause = reducer.reduceStream(line: stream(["playing": false]), now: 110)
    expectEqual(track(pause).elapsedAtSync, 30, "pause interpolates old playing progress")
    expectEqual(track(pause).syncWall, 110, "pause anchors at now")
    expectFalse(pause.identityChanged, "pause keeps identity")
    expectEqual(track(pause).currentElapsed(now: 120), 30, "paused progress stays fixed")
    let resume = reducer.reduceStream(line: stream(["playing": true]), now: 120)
    expectEqual(track(resume).elapsedAtSync, 30, "resume preserves paused progress")
    expectEqual(track(resume).currentElapsed(now: 125), 35, "resume continues interpolation")
    let unchanged = reducer.reduceStream(line: stream(["playing": true]), now: 125)
    expectEqual(track(unchanged).syncWall, 120, "unchanged diff preserves anchor")
    let rate = reducer.reduceStream(line: stream(["playbackRate": 2.0]), now: 125)
    expectEqual(track(rate).currentElapsed(now: 130), 45, "new rate applies after update, not retroactively")
    expectFalse(rate.identityChanged, "rate is not identity")

    var timedSong = song
    timedSong["timestamp"] = "1970-01-01T00:01:40.500Z"
    let timed = reducer.reduceGet(timedSong, now: 110)
    expectEqual(track(timed).syncWall, 100.5, "fractional ISO timestamp")
    let wholeTimestamp = reducer.reduceStream(
        line: stream(["elapsedTime": 30.0, "timestamp": "1970-01-01T00:01:50Z"]), now: 115)
    expectEqual(track(wholeTimestamp).syncWall, 110, "whole second ISO timestamp")
    let invalidTimestamp = reducer.reduceStream(
        line: stream(["elapsedTime": 40.0, "timestamp": "invalid"]), now: 120)
    expectEqual(track(invalidTimestamp).syncWall, 120, "invalid timestamp uses now")
    let absentTimestamp = reducer.reduceStream(line: stream(["elapsedTime": 45.0]), now: 125)
    expectEqual(track(absentTimestamp).syncWall, 125, "elapsed without timestamp does not reuse old timestamp")

    reducer = PlaybackReducer(allowed: [netease])
    _ = reducer.reduceGet(browser, now: 100)
    let unfiltered = reducer.setAllowed([], now: 110)
    expectTrue(unfiltered.identityChanged, "otherApp to track is a transition")
    expectEqual(track(unfiltered).sourceBundleID, safari, "empty allowlist restores raw browser track")
    expectEqual(track(unfiltered).currentElapsed(now: 110), 15, "filtered track keeps timing anchor")
    expectEqual(reducer.allowed, [], "allowlist is updated")
    expectFalse(reducer.setAllowed([], now: 120).identityChanged, "same allowlist does not change identity")
    expectEqual(reducer.setAllowed([netease], now: 120).state, .otherApp(bundleID: safari), "refilter browser")

    reducer = PlaybackReducer(allowed: [])
    var coverSong = song
    coverSong["artworkData"] = "cover"
    expectEqual(reducer.reduceGet(coverSong, now: 100).artworkBase64, "cover", "get carries fresh artwork")
    expectEqual(reducer.reduceStream(line: stream(["playing": false]), now: 101).artworkBase64,
                nil, "diff does not replay cached artwork")
    expectEqual(reducer.setAllowed([netease], now: 102).artworkBase64, nil, "allowlist does not replay artwork")
    expectEqual(reducer.reduceStream(line: stream(["artworkData": "new"]), now: 103).artworkBase64,
                "new", "artwork-only diff emits artwork")
    expectEqual(reducer.reduceStream(line: stream(["artworkData": NSNull()]), now: 104).artworkBase64,
                nil, "artwork removal emits no artwork")

    var identifiedSong = song
    identifiedSong["contentItemIdentifier"] = "content"
    identifiedSong["uniqueIdentifier"] = "unique"
    expectEqual(track(reducer.reduceGet(identifiedSong, now: 100)).identity.key,
                "content", "content item identifier takes precedence")
    let metadata = reducer.reduceStream(line: stream(["artist": "Corrected artist", "album": NSNull()]), now: 105)
    expectFalse(metadata.identityChanged, "stable identifier survives metadata edits")
    expectEqual(track(metadata).album, "", "optional metadata null removes value")
    expectEqual(track(metadata).elapsedAtSync, 20, "metadata-only diff keeps elapsed anchor")
    expectEqual(track(metadata).syncWall, 100, "metadata-only diff keeps clock anchor")
    expectEqual(track(reducer.reduceStream(line: stream(["contentItemIdentifier": NSNull()]), now: 106)).identity.key,
                "unique", "deleted primary identifier falls back to unique identifier")
    let changedID = reducer.reduceStream(line: stream(["uniqueIdentifier": "next", "elapsedTime": 3.0]), now: 107)
    expectTrue(changedID.identityChanged, "identifier change is a new track")
    expectEqual(track(changedID).elapsedAtSync, 3, "new identity uses fresh elapsed")
    expectEqual(track(changedID).syncWall, 107, "new identity clock uses now")
    var clamp = track(changedID)
    expectEqual(clamp.currentElapsed(now: 1000), 180, "progress clamps to duration")
    expectEqual(clamp.currentElapsed(now: 0), 0, "progress clamps to zero")
    clamp.duration = 0
    expectEqual(clamp.currentElapsed(now: 110), 6, "unknown duration does not cap progress")
    clamp.playing = false
    expectEqual(clamp.currentElapsed(now: 1000), 3, "paused track does not interpolate")

    _ = reducer.reduceGet(song, now: 100)
    expectFalse(reducer.reduceStream(line: stream(["duration": 180.4]), now: 101).identityChanged,
                "fallback rounds duration")
    expectTrue(reducer.reduceStream(line: stream(["duration": 181.0]), now: 102).identityChanged,
               "fallback includes rounded duration")
    expectTrue(reducer.reduceStream(line: stream(["album": "Other album"]), now: 103).identityChanged,
               "fallback includes album")
    let beforeInvalid = reducer.state
    let invalid = reducer.reduceStream(line: ["type": "error"], now: 104)
    expectEqual(invalid.state, beforeInvalid, "non-data stream events are ignored")
    expectFalse(invalid.identityChanged, "ignored event preserves identity")
    print("PlaybackReducerTests passed")
}
