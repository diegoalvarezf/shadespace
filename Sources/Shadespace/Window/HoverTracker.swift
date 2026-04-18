import AppKit

@MainActor
final class HoverTracker {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var hotZoneProvider: (() -> NSRect)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isInside = false
    private var lastCheck = Date.distantPast

    private let throttleInterval: TimeInterval = 1.0 / 30.0

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleMouseMoved() {
        let now = Date()
        guard now.timeIntervalSince(lastCheck) >= throttleInterval else { return }
        lastCheck = now

        let mousePos = NSEvent.mouseLocation
        guard let zone = hotZoneProvider?() else { return }
        let inside = zone.contains(mousePos)

        if inside && !isInside {
            isInside = true
            onEnter?()
        } else if !inside && isInside {
            isInside = false
            onExit?()
        }
    }
}
