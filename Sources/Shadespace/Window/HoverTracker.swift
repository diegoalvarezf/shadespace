import AppKit

@MainActor
final class HoverTracker {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var hotZoneProvider: (() -> NSRect)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var buttonMonitor: Any?
    // While a mouse button is held (e.g. dragging a file from Finder) move events may not reach
    // global monitors, so the pointer is sampled until the button is released.
    private var dragPollTimer: Timer?
    private var isInside = false
    private var lastCheck = Date.distantPast

    private let throttleInterval: TimeInterval = 1.0 / 30.0

    func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
            return event
        }
        buttonMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                if event.type == .leftMouseDown { self?.startDragPolling() } else { self?.stopDragPolling() }
            }
        }
    }

    private func startDragPolling() {
        dragPollTimer?.invalidate()
        dragPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self.stopDragPolling()
                } else {
                    self.handleMouseMoved()
                }
            }
        }
    }

    private func stopDragPolling() {
        dragPollTimer?.invalidate()
        dragPollTimer = nil
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = buttonMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        buttonMonitor = nil
        stopDragPolling()
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
