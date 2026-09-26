import Foundation

func runSourceAllowlistTests() {
    let netease = "com.netease.163music"
    let music = SourceFilterLogic.appleMusicBundleID
    let safari = "com.apple.Safari"
    func migrate(_ pinned: String?, configured: Bool = true, stored: [String]? = nil) -> [String] {
        SourceFilterLogic.migrateAllowedSources(storedAllowed: stored, legacyPinned: pinned,
                                               legacyConfigured: configured, netease: netease, appleMusic: music)
    }
    expectEqual(music, "com.apple.Music", "Apple Music bundle id")
    expectEqual(migrate(nil, configured: false), [netease, music], "fresh install defaults")
    expectEqual(migrate(safari, configured: false), [netease, music], "unconfigured legacy value uses defaults")
    expectEqual(migrate(netease), [netease, music], "old NetEase selection adds Apple Music")
    expectEqual(migrate(""), [], "explicit all apps stays unrestricted")
    expectEqual(migrate(nil), [], "configured missing selection is unrestricted")
    expectEqual(migrate(safari), [safari], "other app stays selected")
    expectEqual(migrate(netease, stored: []), [], "stored empty allowlist wins")
    let stored = [safari, "", safari, music]
    expectEqual(migrate(nil, configured: false, stored: stored), stored, "stored allowlist is returned verbatim")
    expectTrue(SourceFilterLogic.allows(sourceBundleID: safari, allowed: []), "empty allowlist allows any app")
    expectTrue(SourceFilterLogic.allows(sourceBundleID: "", allowed: []), "empty allowlist allows empty source")
    expectTrue(SourceFilterLogic.allows(sourceBundleID: music, allowed: [netease, music]), "member is allowed")
    expectFalse(SourceFilterLogic.allows(sourceBundleID: safari, allowed: [netease, music]), "nonmember is blocked")
    expectFalse(SourceFilterLogic.allows(sourceBundleID: "", allowed: [""]), "empty source is blocked by nonempty list")
    print("SourceAllowlistTests passed")
}
