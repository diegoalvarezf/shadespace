import AppKit

enum PlayerSource: String, CaseIterable {
    case spotify
    case appleMusic

    var bundleIdentifier: String {
        switch self {
        case .spotify:    return "com.spotify.client"
        case .appleMusic: return "com.apple.Music"
        }
    }

    /// Distributed notification each app posts on play/pause/track change/seek.
    var stateNotification: Notification.Name {
        switch self {
        case .spotify:    return Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .appleMusic: return Notification.Name("com.apple.Music.playerInfo")
        }
    }

    var appName: String {
        switch self {
        case .spotify:    return "Spotify"
        case .appleMusic: return "Music"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

enum RepeatMode: Equatable {
    case off, all, one
}

struct NowPlayingTrack: Equatable {
    var source: PlayerSource
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var positionSec: Double
    var durationSec: Double
    var artworkURL: URL?
    var shuffle: Bool
    var repeatMode: RepeatMode

    /// Identity of the song, ignoring playback state.
    var songID: String { "\(source.rawValue)|\(title)|\(artist)|\(album)" }

    /// Position extrapolated from the last snapshot, so the UI never needs a polling timer.
    func position(at date: Date, since snapshotDate: Date) -> Double {
        let pos = isPlaying ? positionSec + date.timeIntervalSince(snapshotDate) : positionSec
        return min(max(pos, 0), durationSec > 0 ? durationSec : pos)
    }

    func progress(at date: Date, since snapshotDate: Date) -> Double {
        guard durationSec > 0 else { return 0 }
        return position(at: date, since: snapshotDate) / durationSec
    }
}

/// Reads and controls Spotify and Apple Music through AppleScript.
/// Scripts only run in response to events (notifications, user actions), never on a timer,
/// and never against an app that isn't running (a `tell` would launch it).
actor MediaPlayerBridge {
    private static let separator = "\u{1F}"

    func snapshot(of source: PlayerSource) async -> NowPlayingTrack? {
        guard source.isRunning else { return nil }
        guard let raw = await run(snapshotScript(for: source)), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: Self.separator)
        guard parts.count == 9 else { return nil }

        let position = Self.number(parts[4])
        var duration = Self.number(parts[5])
        // Spotify reports duration in milliseconds, Music in seconds
        if source == .spotify { duration /= 1000 }

        let repeatMode: RepeatMode
        switch parts[8].trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "all": repeatMode = .all
        case "one":         repeatMode = .one
        default:            repeatMode = .off
        }

        return NowPlayingTrack(
            source: source,
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            isPlaying: parts[3].trimmingCharacters(in: .whitespaces) == "true",
            positionSec: position,
            durationSec: duration,
            artworkURL: source == .spotify ? URL(string: parts[6].trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
            shuffle: parts[7].trimmingCharacters(in: .whitespaces) == "true",
            repeatMode: repeatMode
        )
    }

    /// Apple Music exposes artwork as raw image data instead of a URL.
    func appleMusicArtwork() async -> NSImage? {
        guard PlayerSource.appleMusic.isRunning else { return nil }
        let script = """
        tell application "Music"
            if player state is stopped then return missing value
            if (count of artworks of current track) is 0 then return missing value
            return raw data of artwork 1 of current track
        end tell
        """
        guard let data = await runForData(script) else { return nil }
        return NSImage(data: data)
    }

    func playPause(_ source: PlayerSource) async { await command(source, "playpause") }
    func next(_ source: PlayerSource) async { await command(source, "next track") }
    func previous(_ source: PlayerSource) async { await command(source, "previous track") }

    func seek(_ source: PlayerSource, to seconds: Double) async {
        let value = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(0, seconds))
        await command(source, "set player position to \(value)")
    }

    func setShuffle(_ source: PlayerSource, _ enabled: Bool) async {
        switch source {
        case .spotify:    await command(source, "set shuffling to \(enabled)")
        case .appleMusic: await command(source, "set shuffle enabled to \(enabled)")
        }
    }

    func setRepeat(_ source: PlayerSource, _ mode: RepeatMode) async {
        switch source {
        case .spotify:
            // Spotify's scripting dictionary only has an on/off repeat
            await command(source, "set repeating to \(mode != .off)")
        case .appleMusic:
            let value: String
            switch mode {
            case .off: value = "off"
            case .all: value = "all"
            case .one: value = "one"
            }
            await command(source, "set song repeat to \(value)")
        }
    }

    // MARK: - Private

    private func snapshotScript(for source: PlayerSource) -> String {
        let sep = "(ASCII character 31)"
        switch source {
        case .spotify:
            return """
            tell application "Spotify"
                if player state is stopped then return ""
                set t to current track
                set out to (name of t) & \(sep) & (artist of t) & \(sep) & (album of t)
                set out to out & \(sep) & ((player state is playing) as text) & \(sep) & (player position as text)
                set out to out & \(sep) & ((duration of t) as text) & \(sep) & (artwork url of t)
                return out & \(sep) & (shuffling as text) & \(sep) & (repeating as text)
            end tell
            """
        case .appleMusic:
            return """
            tell application "Music"
                if player state is stopped then return ""
                set t to current track
                set out to (name of t) & \(sep) & (artist of t) & \(sep) & (album of t)
                set out to out & \(sep) & ((player state is playing) as text) & \(sep) & (player position as text)
                set out to out & \(sep) & ((duration of t) as text) & \(sep) & ""
                return out & \(sep) & (shuffle enabled as text) & \(sep) & (song repeat as text)
            end tell
            """
        }
    }

    private func command(_ source: PlayerSource, _ verb: String) async {
        guard source.isRunning else { return }
        await run("tell application \"\(source.appName)\" to \(verb)")
    }

    /// AppleScript formats reals with the user's locale (e.g. "12,5").
    private static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    @discardableResult
    private func run(_ source: String) async -> String? {
        await execute(source)?.stringValue
    }

    private func runForData(_ source: String) async -> Data? {
        guard let descriptor = await execute(source), descriptor.descriptorType != typeNull else { return nil }
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }

    private func execute(_ source: String) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
                cont.resume(returning: err == nil ? result : nil)
            }
        }
    }
}
