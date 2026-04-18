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

    init() {
        let screen = NotchGeometry.notchScreen() ?? NSScreen.main!
        self.state = ShadespaceState(screen: screen)
        self.modules = ModuleRegistry(state: state)

        let collapsed = NotchGeometry.collapsedRect(on: screen)
        self.panel = NotchPanel(contentRect: collapsed)

        let hostingView = NSHostingView(
            rootView: RootView()
                .environmentObject(state)
                .environmentObject(modules)
        )
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        bindState()
        setupHoverTracker()
        observeScreenChanges()
    }

    func show() { panel.orderFrontRegardless() }

    // MARK: - Private

    private func bindState() {
        state.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                guard let self else { return }
                let target = expanded ? self.state.expandedRect : self.state.collapsedRect
                self.animateFrame(to: target)
                self.modules.setExpanded(expanded)
                self.hoverTracker.hotZoneProvider = { expanded ? target : self.state.hotZoneRect }
            }
            .store(in: &cancellables)

        // Allow key focus when AI tab is active (needed for TextField)
        state.$activeTab
            .combineLatest(state.$isExpanded)
            .sink { [weak self] tab, expanded in
                self?.panel.shouldAcceptKey = expanded && tab == .ai
                if expanded && tab == .ai { self?.panel.makeKey() }
            }
            .store(in: &cancellables)
    }

    private func setupHoverTracker() {
        hoverTracker.hotZoneProvider = { [weak self] in self?.state.hotZoneRect ?? .zero }
        hoverTracker.onEnter = { [weak self] in self?.state.expand() }
        hoverTracker.onExit  = { [weak self] in self?.state.collapse(delay: 0.3) }
        hoverTracker.start()
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let screen = NotchGeometry.notchScreen() ?? NSScreen.main else { return }
            self?.panel.setFrame(NotchGeometry.collapsedRect(on: screen), display: true)
        }
    }

    private func animateFrame(to rect: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(rect, display: true)
        }
    }
}
