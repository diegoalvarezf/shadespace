import AppKit
import Combine

/// Tracks what Spotify and Apple Music are playing. Event driven: each app posts a distributed
/// notification on play/pause/skip/seek, and only then is a fresh snapshot read via AppleScript.
@MainActor
final class NowPlayingViewModel: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var snapshotDate = Date()
    @Published private(set) var lyrics: [LyricLine]?

    private let bridge = MediaPlayerBridge()
    private let lyricsService = LyricsService()
    private var snapshots: [PlayerSource: NowPlayingTrack] = [:]
    // Source that most recently started playing; it wins when both apps have a track
    private var activeSource: PlayerSource?
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var artworkTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var artworkSongID: String?
    private static let artworkCache = NSCache<NSString, NSImage>()
    private weak var state: ShadespaceState?

    init(state: ShadespaceState) {
        self.state = state
    }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        for source in PlayerSource.allCases {
            observers.append(distributed.addObserver(forName: source.stateNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh(source) }
            })
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in
                guard let self, let source = PlayerSource.allCases.first(where: { $0.bundleIdentifier == bundleID }) else { return }
                self.snapshots[source] = nil
                self.publish()
            }
        })

        // Re-sync when the card opens: position may have drifted after a seek inside the app
        state?.$isExpanded
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.refreshAll() }
            .store(in: &cancellables)

        AppSettings.shared.$lyricsEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.loadLyrics(for: self.track) } else { self.lyrics = nil }
            }
            .store(in: &cancellables)

        refreshAll()
    }

    // MARK: - Controls

    func playPause() { send { await $0.playPause($1) } }
    func next()      { send { await $0.next($1) } }
    func previous()  { send { await $0.previous($1) } }

    func seek(toFraction fraction: Double) {
        guard let track, track.durationSec > 0 else { return }
        let seconds = track.durationSec * min(max(fraction, 0), 1)
        // Optimistic update so the bar doesn't jump back while the app catches up
        var updated = track
        updated.positionSec = seconds
        apply(updated)
        send { await $0.seek($1, to: seconds) }
    }

    func toggleShuffle() {
        guard let track else { return }
        let enabled = !track.shuffle
        send { await $0.setShuffle($1, enabled) }
    }

    func cycleRepeat() {
        guard let track else { return }
        let next: RepeatMode
        switch track.repeatMode {
        case .off: next = .all
        // Spotify has no "repeat one" in AppleScript, so it toggles between off and all
        case .all: next = track.source == .appleMusic ? .one : .off
        case .one: next = .off
        }
        send { await $0.setRepeat($1, next) }
    }

    // MARK: - Private

    private func send(_ action: @escaping (MediaPlayerBridge, PlayerSource) async -> Void) {
        guard let source = track?.source else { return }
        Task {
            await action(bridge, source)
            // Shuffle/repeat changes don't post a notification, so read state back explicitly
            refresh(source)
        }
    }

    private func refreshAll() {
        for source in PlayerSource.allCases where source.isRunning {
            refresh(source)
        }
    }

    private func refresh(_ source: PlayerSource) {
        Task {
            let snap = await bridge.snapshot(of: source)
            snapshots[source] = snap
            if snap?.isPlaying == true { activeSource = source }
            publish()
        }
    }

    /// Chooses which source to show: the active one if it has a track, else any playing one,
    /// else whatever is paused.
    private func publish() {
        let candidates = PlayerSource.allCases.compactMap { snapshots[$0] }
        let chosen = candidates.first { $0.source == activeSource && $0.isPlaying }
            ?? candidates.first { $0.isPlaying }
            ?? candidates.first { $0.source == activeSource }
            ?? candidates.first
        apply(chosen)
    }

    private func apply(_ newTrack: NowPlayingTrack?) {
        let songChanged = newTrack?.songID != track?.songID
        track = newTrack
        snapshotDate = Date()
        state?.nowPlayingIsActive = newTrack?.isPlaying ?? false

        guard songChanged else { return }
        loadArtwork(for: newTrack)
        loadLyrics(for: newTrack)
    }

    private func loadArtwork(for track: NowPlayingTrack?) {
        artworkTask?.cancel()
        guard let track else {
            artwork = nil
            artworkSongID = nil
            return
        }
        let key = track.songID as NSString
        if let cached = Self.artworkCache.object(forKey: key) {
            artwork = cached
            artworkSongID = track.songID
            return
        }
        artworkTask = Task {
            let image: NSImage?
            switch track.source {
            case .spotify:
                if let url = track.artworkURL, let (data, _) = try? await URLSession.shared.data(from: url) {
                    image = NSImage(data: data)
                } else {
                    image = nil
                }
            case .appleMusic:
                image = await bridge.appleMusicArtwork()
            }
            guard !Task.isCancelled, self.track?.songID == track.songID else { return }
            let thumbnail = image.map(Self.thumbnail)
            if let thumbnail { Self.artworkCache.setObject(thumbnail, forKey: key) }
            artwork = thumbnail
            artworkSongID = track.songID
        }
    }

    private func loadLyrics(for track: NowPlayingTrack?) {
        lyricsTask?.cancel()
        lyrics = nil
        guard let track, AppSettings.shared.lyricsEnabled else { return }
        lyricsTask = Task {
            let lines = await lyricsService.lyrics(for: track)
            guard !Task.isCancelled, self.track?.songID == track.songID else { return }
            lyrics = lines
        }
    }

    /// Stores artwork at the size it is drawn (retina 2x of the 62pt card thumbnail).
    private static func thumbnail(_ image: NSImage) -> NSImage {
        let side: CGFloat = 128
        let result = NSImage(size: NSSize(width: side, height: side))
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }
}
