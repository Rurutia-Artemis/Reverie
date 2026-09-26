import Foundation

enum LikeError: Error, Equatable {
    case notAuthorized, notRunning, noTrack, mismatch, script(Int)
}

enum AppleMusicLike {
    static func readFavorited() -> Result<Bool, LikeError> {
        execute(toggle: false, expected: nil)
    }

    /// 只有当前曲目的歌名与歌手和界面显示的一致才切换，否则返回 .mismatch。
    static func toggleFavorited(expectedTitle: String, expectedArtist: String) -> Result<Bool, LikeError> {
        execute(toggle: true, expected: (expectedTitle, expectedArtist))
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func execute(toggle: Bool, expected: (String, String)?) -> Result<Bool, LikeError> {
        let guardLine = expected.map { "if (name of currentTrack) is not \(quoted($0.0)) or (artist of currentTrack) is not \(quoted($0.1)) then return -3" } ?? ""
        // The running check must precede all commands sent to Music.
        let source = """
        if application "Music" is running then
            tell application "Music"
                if player state is stopped then return -2
                try
                    set currentTrack to current track
                    if currentTrack is missing value then return -2
                on error errorMessage number errorNumber
                    if errorNumber is -1728 then return -2
                    error errorMessage number errorNumber
                end try
                \(guardLine)
                \(toggle ? "set favorited of currentTrack to not (favorited of currentTrack)" : "")
                if favorited of currentTrack then return 1
                return 0
            end tell
        else
            return -1
        end if
        """
        guard let script = NSAppleScript(source: source) else { return .failure(.script(-2740)) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -2700
            return .failure(code == -1743 ? .notAuthorized : .script(code))
        }
        switch result.int32Value {
        case -1: return .failure(.notRunning)
        case -2: return .failure(.noTrack)
        case -3: return .failure(.mismatch)
        case 0: return .success(false)
        case 1: return .success(true)
        default: return .failure(.script(-1700))
        }
    }
}
