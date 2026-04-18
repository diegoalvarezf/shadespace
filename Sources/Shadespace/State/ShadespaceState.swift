import AppKit
import Combine

@MainActor
final class ShadespaceState: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var screen: NSScreen

    static let expandedContentHeight: CGFloat = 320

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

    var collapsedRect: NSRect { NotchGeometry.collapsedRect(on: screen) }
    var expandedRect: NSRect { NotchGeometry.expandedRect(on: screen, contentHeight: Self.expandedContentHeight) }
    var hotZoneRect: NSRect { NotchGeometry.hotZoneRect(on: screen) }
}
