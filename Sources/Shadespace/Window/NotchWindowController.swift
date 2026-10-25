import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchWindowController {
    private let state: ShadespaceState
    private let modules: ModuleRegistry
    private let panel: NotchPanel
    private let hoverTracker = HoverTracker()
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    private var swipeConsumed = false

    init() {
        let screen = NotchGeometry.notchScreen() ?? NSScreen.main!
        self.state = ShadespaceState(screen: screen)
        self.modules = ModuleRegistry(state: state)

        // The panel keeps one fixed frame; the island is drawn and animated by SwiftUI inside it.
        self.panel = NotchPanel(contentRect: NotchGeometry.canvasRect(on: screen))
        // Force dark appearance so SwiftUI color resolution is consistent
        panel.appearance = NSAppearance(named: .darkAqua)

        let hostingView = NSHostingView(
            rootView: RootView()
                .environmentObject(state)
                .environmentObject(modules)
                .environmentObject(AppSettings.shared)
                .preferredColorScheme(.dark)
        )
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        // Transparent everywhere except the island, which only takes the mouse while hovered.
        panel.ignoresMouseEvents = true

        bindState()
        setupHoverTracker()
        setupScrollGesture()
        observeScreenChanges()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    // MARK: - Private

    private func bindState() {
        // Allow keyboard input only when AI summary is visible (for the chat input field)
        state.$mode
            .removeDuplicates()
            .sink { [weak self] mode in
                if case .aiSummary = mode {
                    self?.panel.shouldAcceptKey = true
                } else {
                    self?.panel.shouldAcceptKey = false
                }
            }
            .store(in: &cancellables)
    }

    private func setupHoverTracker() {
        hoverTracker.hotZoneProvider = { [weak self] in self?.state.hotZoneRect ?? .zero }
        hoverTracker.onEnter = { [weak self] in
            self?.panel.ignoresMouseEvents = false
            self?.state.hoverEnter()
        }
        hoverTracker.onExit = { [weak self] in
            guard let self else { return }
            // Keep accepting events during a drag so the drop still lands on the island
            if !self.state.isDragging { self.panel.ignoresMouseEvents = true }
            self.state.hoverExit()
        }
        hoverTracker.start()

        // A drag that ends outside the island must give the mouse back to the windows below
        state.$isDragging
            .removeDuplicates()
            .sink { [weak self] dragging in
                guard let self, !dragging, !self.state.isHovering else { return }
                self.panel.ignoresMouseEvents = true
            }
            .store(in: &cancellables)
    }

    /// Horizontal two-finger swipe over the expanded island skips tracks. One skip per gesture.
    private func setupScrollGesture() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.state.isExpanded, self.state.mode == .idle,
                  self.state.page == .nowPlaying, self.modules.nowPlaying.track != nil else { return event }
            if event.phase == .began || event.phase == .mayBegin { self.swipeConsumed = false }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            guard !self.swipeConsumed else { return nil }
            if event.scrollingDeltaX > 5 {
                self.swipeConsumed = true
                self.modules.nowPlaying.next()
                return nil
            } else if event.scrollingDeltaX < -5 {
                self.swipeConsumed = true
                self.modules.nowPlaying.previous()
                return nil
            }
            return event
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let screen = NotchGeometry.notchScreen() else { return }
                self.state.updateScreen(screen)
                self.panel.setFrame(NotchGeometry.canvasRect(on: screen), display: true)
            }
        }
    }
}
