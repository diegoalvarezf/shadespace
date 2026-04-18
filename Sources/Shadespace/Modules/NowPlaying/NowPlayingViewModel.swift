import AppKit

@MainActor
final class NowPlayingViewModel: ObservableObject {
    @Published private(set) var snapshot: NowPlayingSnapshot?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var snapshotDate = Date()

    private let spotify = SpotifyController()
    private var timer: Timer?
    private var artworkTask: Task<Void, Never>?
    private var lastArtworkURL: URL?
    private static let artworkCache = NSCache<NSURL, NSImage>()
    private weak var state: ShadespaceState?

    init(state: ShadespaceState) {
        self.state = state
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func playPause() { Task { await spotify.playPause() } }
    func next()      { Task { await spotify.next() } }
    func previous()  { Task { await spotify.previous() } }

    private func poll() {
        Task {
            let snap = await spotify.snapshot()
            self.snapshot = snap
            self.snapshotDate = Date()
            self.state?.nowPlayingIsActive = snap?.isPlaying ?? false
            if let url = snap?.artworkURL, url != self.lastArtworkURL {
                self.lastArtworkURL = url
                self.loadArtwork(url: url)
            } else if snap == nil {
                self.artwork = nil
                self.lastArtworkURL = nil
            }
        }
    }

    private func loadArtwork(url: URL) {
        if let cached = Self.artworkCache.object(forKey: url as NSURL) {
            artwork = cached; return
        }
        artworkTask?.cancel()
        artworkTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            Self.artworkCache.setObject(image, forKey: url as NSURL)
            self.artwork = image
        }
    }
}
