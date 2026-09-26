import Foundation

func runSourceFilteringTests() {
    let childProcessPayload: [String: Any] = [
        "bundleIdentifier": "com.apple.WebKit.WebContent",
        "parentApplicationBundleIdentifier": "com.apple.Safari"
    ]
    expectEqual(
        SourceFilterLogic.bundleIdentifier(from: childProcessPayload),
        "com.apple.Safari",
        "parent bundle id should identify the user-facing app"
    )

    let directAppPayload: [String: Any] = ["bundleIdentifier": "com.netease.163music"]
    expectEqual(
        SourceFilterLogic.bundleIdentifier(from: directAppPayload),
        "com.netease.163music",
        "bundle id should be used when parent bundle id is absent"
    )

    expectTrue(
        SourceFilterLogic.allows(sourceBundleID: "com.apple.Safari", selectedBundleID: ""),
        "empty selection should allow every source"
    )
    expectTrue(
        SourceFilterLogic.allows(sourceBundleID: "com.netease.163music", selectedBundleID: "com.netease.163music"),
        "matching fixed source should be allowed"
    )
    expectFalse(
        SourceFilterLogic.allows(sourceBundleID: "com.apple.Safari", selectedBundleID: "com.netease.163music"),
        "non-matching source should be blocked"
    )
    expectFalse(
        SourceFilterLogic.allows(sourceBundleID: "", selectedBundleID: "com.netease.163music"),
        "unknown source should be blocked when a fixed source is selected"
    )

    expectEqual(
        SourceFilterLogic.resolvedSelection(
            storedBundleID: nil,
            hasExplicitSelection: false,
            defaultBundleID: "com.netease.163music"
        ),
        "com.netease.163music",
        "fresh installs should default to the music app source"
    )
    expectEqual(
        SourceFilterLogic.resolvedSelection(
            storedBundleID: "",
            hasExplicitSelection: false,
            defaultBundleID: "com.netease.163music"
        ),
        "com.netease.163music",
        "legacy empty selections should migrate to the music app source"
    )
    expectEqual(
        SourceFilterLogic.resolvedSelection(
            storedBundleID: "",
            hasExplicitSelection: true,
            defaultBundleID: "com.netease.163music"
        ),
        "",
        "explicit all-app selections should stay all-app"
    )

    let pinnedMusic = "com.netease.163music"
    let wrappedBrowserStreamEvent: [String: Any] = [
        "type": "data",
        "diff": false,
        "payload": [
            "bundleIdentifier": "com.apple.Safari",
            "title": "Browser video"
        ]
    ]
    expectFalse(
        SourceFilterLogic.shouldMerge(
            payload: wrappedBrowserStreamEvent,
            currentSourceBundleID: pinnedMusic,
            selectedBundleID: pinnedMusic
        ),
        "wrapped stream events from non-fixed sources should be blocked"
    )
    expectFalse(
        SourceFilterLogic.shouldMerge(
            payload: ["title": "Video playing in browser"],
            currentSourceBundleID: pinnedMusic,
            selectedBundleID: pinnedMusic
        ),
        "source-less media identity updates should not bypass a fixed source"
    )
    expectFalse(
        SourceFilterLogic.shouldMerge(
            payload: ["elapsedTime": 42.0, "playing": true],
            currentSourceBundleID: pinnedMusic,
            selectedBundleID: pinnedMusic
        ),
        "source-less progress updates should not bypass a fixed source"
    )
    expectFalse(
        SourceFilterLogic.shouldMerge(
            payload: ["elapsedTime": 42.0, "playing": true],
            currentSourceBundleID: "com.apple.Safari",
            selectedBundleID: pinnedMusic
        ),
        "source-less updates from a non-fixed current source should be blocked"
    )
    expectFalse(
        SourceFilterLogic.shouldMerge(
            payload: ["bundleIdentifier": "com.apple.Safari", "title": "Browser video"],
            currentSourceBundleID: pinnedMusic,
            selectedBundleID: pinnedMusic
        ),
        "explicit non-matching source should be blocked"
    )
    print("SourceFilteringTests passed")
}
