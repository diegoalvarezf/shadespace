import AppKit

struct NowPlayingSnapshot: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var positionSec: Double
    var durationSec: Double
    var artworkURL: URL?

    func progress(at date: Date, since snapshotDate: Date) -> Double {
        guard durationSec > 0 else { return 0 }
        let pos = isPlaying ? positionSec + date.timeIntervalSince(snapshotDate) : positionSec
        return min(max(pos / durationSec, 0), 1)
    }
}

actor SpotifyController {
    func snapshot() async -> NowPlayingSnapshot? {
        let script = """
        tell application "Spotify"
            if it is not running then return ""
            if player state is stopped then return ""
            set t to name of current track
            set ar to artist of current track
            set pl to (player state is playing)
            set pos to player position
            set dur to duration of current track
            set art to artwork url of current track
            return t & "|||" & ar & "|||" & (pl as text) & "|||" & (pos as text) & "|||" & (dur as text) & "|||" & art
        end tell
        """
        guard let raw = await run(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count == 6 else { return nil }

        let dur = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        let pos = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0

        return NowPlayingSnapshot(
            title: parts[0],
            artist: parts[1],
            isPlaying: parts[2].trimmingCharacters(in: .whitespaces) == "true",
            positionSec: pos,
            durationSec: dur / 1000,
            artworkURL: URL(string: parts[5].trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    func playPause() async { await run("tell application \"Spotify\" to playpause") }
    func next() async { await run("tell application \"Spotify\" to next track") }
    func previous() async { await run("tell application \"Spotify\" to previous track") }

    @discardableResult
    private func run(_ source: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
                cont.resume(returning: err == nil ? result?.stringValue : nil)
            }
        }
    }
}
