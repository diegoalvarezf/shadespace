import Foundation

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

/// Time-synced lyrics from LRCLib (https://lrclib.net), a free public lyrics database.
/// Only the track title, artist, album and duration are sent; results are cached per song.
actor LyricsService {
    private var cache: [String: [LyricLine]] = [:]
    private var misses: Set<String> = []

    func lyrics(for track: NowPlayingTrack) async -> [LyricLine]? {
        let key = track.songID
        if let cached = cache[key] { return cached }
        if misses.contains(key) { return nil }

        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.durationSec.rounded()))),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Shadespace/0.1 (macOS notch app)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                // 404 means LRCLib has no lyrics for this song; don't ask again this session
                misses.insert(key)
                return nil
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard let synced = payload.syncedLyrics, !synced.isEmpty else {
                misses.insert(key)
                return nil
            }
            let lines = Self.parse(lrc: synced)
            cache[key] = lines
            return lines
        } catch {
            // Network errors are not cached, so the next track change retries
            return nil
        }
    }

    /// Parses LRC lines like "[01:23.45] text". A line may carry several timestamps.
    static func parse(lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for rawLine in lrc.components(separatedBy: .newlines) {
            var rest = Substring(rawLine)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let min = Double(parts[0]), let sec = Double(parts[1]) {
                    times.append(min * 60 + sec)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times {
                lines.append(LyricLine(time: time, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private struct Payload: Decodable {
        let syncedLyrics: String?
    }
}

extension Array where Element == LyricLine {
    /// The line being sung at `position`, or nil before the first line.
    func line(at position: TimeInterval) -> LyricLine? {
        // Binary search for the last line whose time is <= position
        var low = 0, high = count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if self[mid].time <= position {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found.map { self[$0] }
    }
}
