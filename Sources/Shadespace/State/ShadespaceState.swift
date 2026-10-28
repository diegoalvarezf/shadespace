import AppKit
import Combine
import SwiftUI

/// Long-running activity that owns the island's content until the user dismisses it.
enum IslandMode: Equatable {
    case idle
    case aiReading(progress: Double)
    case aiSummary(text: String)
    case fileConverting
    case fileConversionDone(url: URL)
    case fileConversionError
}

/// Short-lived notification that makes the island "peek" for a few seconds.
enum IslandAlert: Equatable {
    case charging(percent: Int)
    case batteryLow(percent: Int)
    case batteryFull
    case airPods(AirPodsStatus)
    case trayAdded(count: Int)
    case pomodoro(finished: PomodoroPhase, next: PomodoroPhase)
    case pomodoroSkipped
}

/// Page shown in the expanded card when no activity is running.
enum IslandPage: Equatable {
    case nowPlaying
    case pomodoro
    case agents
    case tray
}

/// Target of a file being dragged over the expanded island.
enum DropZone: CaseIterable, Equatable {
    case summarize
    case convert
    case airDrop
    case tray
}

@MainActor
final class ShadespaceState: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var isHovering = false
    @Published private(set) var screen: NSScreen
    @Published var nowPlayingIsActive = false
    @Published var mode: IslandMode = .idle
    @Published var page: IslandPage = .nowPlaying
    @Published private(set) var alert: IslandAlert?
    @Published private(set) var isDragging = false
    /// A running or paused Pomodoro keeps the island visible beside the notch.
    @Published var pomodoroActive = false
    /// A coding agent session is working, waiting for you, or just finished.
    @Published var agentsActive = false
    @Published var hoveredDropZone: DropZone?
    /// Zones that can take what is being dragged; the others are dimmed.
    @Published var supportedDropZones: Set<DropZone> = Set(DropZone.allCases)

    private var collapseTask: Task<Void, Never>?
    private var hoverExpandTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?

    init(screen: NSScreen) {
        self.screen = screen
    }

    func updateScreen(_ screen: NSScreen) {
        self.screen = screen
    }

    // MARK: - Hover

    func hoverEnter() {
        collapseTask?.cancel()
        collapseTask = nil
        isHovering = true
        hoverExpandTask?.cancel()
        hoverExpandTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.isExpanded = true
        }
    }

    func hoverExit() {
        hoverExpandTask?.cancel()
        hoverExpandTask = nil
        isHovering = false
        collapse(delay: 0.3)
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
            guard !Task.isCancelled, let self, !self.isDragging, !self.isHovering else { return }
            self.isExpanded = false
        }
    }

    // MARK: - Drag & drop

    func dragEntered() {
        isDragging = true
        expand()
    }

    func dragExited() {
        isDragging = false
        hoveredDropZone = nil
        if !isHovering { collapse(delay: 0.4) }
    }

    // MARK: - Alerts

    /// Shows a transient alert. Long-running activities (AI, conversion) are never interrupted.
    func showAlert(_ alert: IslandAlert, duration: TimeInterval = 4) {
        guard mode == .idle else { return }
        alertTask?.cancel()
        self.alert = alert
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.alert = nil
        }
    }

    func dismissAlert() {
        alertTask?.cancel()
        alert = nil
    }

    // MARK: - Geometry

    /// Size of the visible island for the current state, in points.
    var islandSize: CGSize {
        let liveActivity = AppSettings.shared.showLiveActivity
        if isExpanded { return NotchGeometry.expandedSize(on: screen) }
        if alert != nil {
            let peek = NotchGeometry.peekSize(on: screen, liveActivity: liveActivity)
            return CGSize(width: peek.width, height: peekHeaderHeight + NotchGeometry.peekContentHeight)
        }
        if liveActivity { return NotchGeometry.collapsedRect(on: screen).size }
        if agentsActive { return NotchGeometry.agentActivitySize(on: screen) }
        if pomodoroActive { return NotchGeometry.activitySize(on: screen) }
        return NotchGeometry.hiddenSize(on: screen)
    }

    /// Top row of a peek alert: the bot row when an activity is running, else just the notch.
    var peekHeaderHeight: CGFloat {
        if AppSettings.shared.showLiveActivity { return NotchGeometry.collapsedRect(on: screen).height }
        if agentsActive || pomodoroActive { return NotchGeometry.earsHeight(on: screen) }
        return NotchGeometry.peekHeaderHeight(on: screen, liveActivity: false)
    }

    var isHidden: Bool {
        !isExpanded && alert == nil && !AppSettings.shared.showLiveActivity
    }

    /// Island frame in screen coordinates; the hover tracker uses it as its hot zone.
    var islandScreenRect: NSRect {
        let canvas = NotchGeometry.canvasRect(on: screen)
        let size = islandSize
        return NSRect(x: canvas.midX - size.width / 2, y: canvas.maxY - size.height,
                      width: size.width, height: size.height)
    }

    var hotZoneRect: NSRect {
        if isExpanded { return islandScreenRect }
        let rect = islandScreenRect
        // Hidden on a screen without a notch: a thin band at the top edge reveals the island
        if rect.height < 8 {
            return NSRect(x: rect.minX, y: rect.maxY - 8, width: rect.width, height: 8)
        }
        return rect.insetBy(dx: isHidden ? -10 : -40, dy: isHidden ? -4 : -8)
    }
}
