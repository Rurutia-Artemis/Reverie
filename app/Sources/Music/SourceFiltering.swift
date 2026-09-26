// reverie:logic 纯逻辑，单元测试会编进来，不许依赖 SwiftUI / AppKit。
import Foundation

struct SourceApp: Hashable, Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

enum SourceFilterLogic {
    static func mediaPayload(from message: [String: Any]) -> [String: Any] {
        if let payload = message["payload"] as? [String: Any] {
            return payload
        }
        return message
    }

    static func bundleIdentifier(from payload: [String: Any]) -> String {
        let media = mediaPayload(from: payload)
        let parent = trimmed(media["parentApplicationBundleIdentifier"])
        if !parent.isEmpty { return parent }
        return trimmed(media["bundleIdentifier"])
    }

    static func allows(sourceBundleID: String, selectedBundleID: String) -> Bool {
        let selected = selectedBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return true }
        return sourceBundleID == selected
    }

    static func resolvedSelection(storedBundleID: String?, hasExplicitSelection: Bool, defaultBundleID: String) -> String {
        let stored = storedBundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty || hasExplicitSelection { return stored }
        return defaultBundleID
    }

    static func shouldMerge(payload: [String: Any], currentSourceBundleID: String, selectedBundleID: String) -> Bool {
        let selected = selectedBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return true }

        let media = mediaPayload(from: payload)
        let incomingSource = bundleIdentifier(from: media)
        if !incomingSource.isEmpty {
            return incomingSource == selected
        }

        return false
    }

    private static func trimmed(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

extension SourceFilterLogic {
    static let appleMusicBundleID = "com.apple.Music"

    static func allows(sourceBundleID: String, allowed: Set<String>) -> Bool {
        allowed.isEmpty || (!sourceBundleID.isEmpty && allowed.contains(sourceBundleID))
    }

    /// 旧的「固定一个来源」设置迁移成允许名单。storedAllowed 非 nil 时原样返回。
    static func migrateAllowedSources(storedAllowed: [String]?, legacyPinned: String?, legacyConfigured: Bool,
                                      netease: String, appleMusic: String) -> [String] {
        if let storedAllowed { return storedAllowed }
        let pinned = legacyPinned?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacyConfigured || pinned == netease { return [netease, appleMusic] }
        return pinned.isEmpty ? [] : [pinned]
    }
}
