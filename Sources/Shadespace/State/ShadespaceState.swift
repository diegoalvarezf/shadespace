import AppKit
import Combine

enum ShadespaceTab: String, CaseIterable, Identifiable {
    case nowPlaying, clipboard, stats, focus, ai
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .clipboard:  return "doc.on.clipboard"
        case .stats:      return "speedometer"
        case .focus:      return "moon.fill"
        case .ai:         return "sparkles"
        }
    }
}

@MainActor
final class ShadespaceState: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var screen: NSScreen
    @Published var activeTab: ShadespaceTab = .nowPlaying
    @Published var nowPlayingIsActive = false

    static let expandedContentHeight: CGFloat = 340

    private var collapseTask: Task<Void, Never>?

    init(screen: NSScreen) {
        self.screen = screen
    }

    func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        isExpanded = true
    }

    func collapse(delay: TimeInterval = 0.25) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.isExpanded = false
        }
    }

    func setTab(_ tab: ShadespaceTab) { activeTab = tab }

    var collapsedRect: NSRect { NotchGeometry.collapsedRect(on: screen) }
    var expandedRect: NSRect { NotchGeometry.expandedRect(on: screen, contentHeight: Self.expandedContentHeight) }
    var hotZoneRect: NSRect { NotchGeometry.hotZoneRect(on: screen) }
}
