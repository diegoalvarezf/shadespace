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
        // File drags are received by an AppKit container around the SwiftUI content
        let dropView = DropCatcherView(frame: NSRect(origin: .zero, size: panel.frame.size))
        dropView.autoresizingMask = [.width, .height]
        hostingView.frame = dropView.bounds
        hostingView.autoresizingMask = [.width, .height]
        dropView.addSubview(hostingView)
        panel.contentView = dropView

        // Transparent everywhere except the island, which only takes the mouse while hovered.
        panel.ignoresMouseEvents = true

        bindState()
        setupDrop(dropView)
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

    private func setupDrop(_ view: DropCatcherView) {
        // Drop zones are laid out across the expanded island, which is top-centered in the panel
        let expandedRect: (NSView) -> NSRect = { [weak self] view in
            guard let self else { return .zero }
            let size = NotchGeometry.expandedSize(on: self.state.screen)
            return NSRect(x: view.bounds.midX - size.width / 2, y: view.bounds.maxY - size.height,
                          width: size.width, height: size.height)
        }
        view.acceptsDrop = { [weak view] point in
            guard let view else { return false }
            return expandedRect(view).contains(point)
        }
        view.onEnter = { [weak self] urls in
            guard let self else { return }
            self.state.supportedDropZones = ModuleRegistry.supportedZones(for: urls)
            self.state.dragEntered()
        }
        view.onMove = { [weak self, weak view] point in
            guard let self, let view else { return }
            let rect = expandedRect(view)
            let zones = DropZone.allCases
            let index = Int((point.x - rect.minX) / rect.width * CGFloat(zones.count))
            let zone = zones[min(max(index, 0), zones.count - 1)]
            if self.state.hoveredDropZone != zone { self.state.hoveredDropZone = zone }
        }
        view.onExit = { [weak self] in self?.state.dragExited() }
        view.onDrop = { [weak self] urls in
            guard let self else { return false }
            // A zone that can't take these files falls back to the tray
            let hovered = self.state.hoveredDropZone ?? .tray
            let zone = self.state.supportedDropZones.contains(hovered) ? hovered : .tray
            let handled = self.modules.handleDrop(urls, zone: zone)
            self.state.dragExited()
            return handled
        }
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
