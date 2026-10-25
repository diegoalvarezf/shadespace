import AppKit

enum PomodoroPhase: Equatable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus:      return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak:  return "Long break"
        }
    }
}

/// Focus / break timer. Runs on an end date rather than a per-second tick: a single timer
/// fires when the phase ends, and the UI computes the remaining time while it is visible.
@MainActor
final class PomodoroTimer: ObservableObject {
    enum Status: Equatable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var status: Status = .idle {
        didSet { state?.pomodoroActive = status != .idle }
    }
    /// Focus sessions finished in the current cycle (a long break follows every fourth).
    @Published private(set) var completedFocusSessions = 0
    @Published var focusMinutes: Int {
        didSet {
            UserDefaults.standard.set(focusMinutes, forKey: Self.focusKey)
            if status == .idle, phase == .focus { objectWillChange.send() }
        }
    }

    static let focusPresets = [15, 25, 50]
    static let sessionsPerCycle = 4
    private static let focusKey = "pomodoro.focusMinutes"

    private weak var state: ShadespaceState?
    private var phaseTimer: Timer?

    init(state: ShadespaceState) {
        self.state = state
        let saved = UserDefaults.standard.integer(forKey: Self.focusKey)
        focusMinutes = saved > 0 ? saved : 25
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    var isActive: Bool { status != .idle }

    var mood: PixelBot.Mood {
        if case .paused = status { return .paused }
        return phase == .focus ? .focus : .rest
    }

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus:      return TimeInterval(focusMinutes * 60)
        case .shortBreak: return 5 * 60
        case .longBreak:  return 15 * 60
        }
    }

    func remaining(at date: Date) -> TimeInterval {
        switch status {
        case .idle:                  return duration(of: phase)
        case .paused(let remaining): return remaining
        case .running(let endDate):  return max(0, endDate.timeIntervalSince(date))
        }
    }

    func progress(at date: Date) -> Double {
        let total = duration(of: phase)
        return total > 0 ? 1 - remaining(at: date) / total : 0
    }

    // MARK: - Controls

    func startOrPause() {
        switch status {
        case .idle:
            run(for: duration(of: phase))
        case .paused(let remaining):
            run(for: remaining)
        case .running(let endDate):
            phaseTimer?.invalidate()
            status = .paused(remaining: max(0, endDate.timeIntervalSinceNow))
        }
    }

    func reset() {
        phaseTimer?.invalidate()
        phase = .focus
        completedFocusSessions = 0
        status = .idle
    }

    /// Ends the current phase now and moves to the next one without starting it.
    func skip() {
        let abandonedFocus = phase == .focus && status != .idle
        phaseTimer?.invalidate()
        advance(announce: false)
        if abandonedFocus { state?.showAlert(.pomodoroSkipped, duration: 3) }
    }

    // MARK: - Private

    private func run(for seconds: TimeInterval) {
        let endDate = Date().addingTimeInterval(seconds)
        status = .running(endDate: endDate)
        phaseTimer?.invalidate()
        let timer = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.advance(announce: true) }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        phaseTimer = timer
    }

    private func advance(announce: Bool) {
        let finished = phase
        if finished == .focus {
            completedFocusSessions += 1
            phase = completedFocusSessions >= Self.sessionsPerCycle ? .longBreak : .shortBreak
        } else {
            if finished == .longBreak { completedFocusSessions = 0 }
            phase = .focus
        }
        status = .idle

        guard announce else { return }
        NSSound(named: finished == .focus ? "Glass" : "Hero")?.play()
        state?.showAlert(.pomodoro(finished: finished, next: phase), duration: 6)
    }
}
