import AppKit
import Combine
import CoreGraphics

/// The notch pet. Decides where the bot is, what it is doing and which face it makes, from
/// the Pomodoro, coding agents, music, your activity and its own life stats.
///
/// Positions are abstract (a side of the notch, a fraction along the expanded strip); the view
/// turns them into points and animates between them.
@MainActor
final class BotCompanion: ObservableObject {
    enum Side { case left, right }

    /// Side of the camera housing the bot sits on while the island is collapsed.
    @Published private(set) var side: Side = .left
    /// True while it crosses behind the camera to the other side; both sides are shown.
    @Published private(set) var crossing = false
    /// 0…1 how far it is ducking behind the camera housing while peeking.
    @Published private(set) var peek: CGFloat = 0
    /// 0…1 position along the strip below the header while the island is expanded.
    @Published private(set) var stripPosition: CGFloat = 0.1
    @Published private(set) var walking = false
    /// How long the current walk takes, so the view animates it at walking pace.
    @Published private(set) var moveDuration: Double = 0.5
    @Published private(set) var look = 0
    @Published private(set) var asleep = false
    @Published private(set) var life = BotLife.load()
    /// Short reaction (greeting, celebration) that overrides the everyday face.
    @Published private(set) var reaction: PixelBot.Mood?

    /// Walking speed along the expanded strip, in strip widths per second.
    private static let stripSpeed: CGFloat = 0.35
    /// No keyboard or mouse input for this long and the bot falls asleep.
    private static let sleepAfterIdle: TimeInterval = 10 * 60

    private weak var state: ShadespaceState?
    private weak var modules: ModuleRegistry?
    private var cancellables = Set<AnyCancellable>()
    private var behaviorTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var vitalsTimer: Timer?
    private var lastAttention = Date.distantPast
    private var lastMusicReward = Date()

    init(state: ShadespaceState) {
        self.state = state
    }

    /// Starts life once the other modules exist.
    func start(modules: ModuleRegistry) {
        self.modules = modules
        life.advance(to: Date(), asleep: false)
        react(.wave, for: 2.5) // hello

        bindEvents(modules)
        behaviorTask = Task { [weak self] in await self?.liveLoop() }

        vitalsTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkVitals() }
        }
    }

    // MARK: - Face

    /// The face to draw right now. Work and timers come first, then reactions and everyday life.
    var mood: PixelBot.Mood {
        if let modules, let state {
            if state.agentsActive, let session = modules.agents.primarySession { return session.botMood }
            if state.pomodoroActive { return modules.pomodoro.mood }
        }
        if let reaction { return reaction }
        if asleep { return .sleep }
        if modules?.nowPlaying.track?.isPlaying == true { return .dance }
        if life.isGloomy { return .gloomy }
        return .focus
    }

    /// Whether the bot may wander off its perch (not while timers or agents are on display).
    private var isFree: Bool {
        guard let state else { return false }
        return !state.agentsActive && !state.pomodoroActive && state.alert == nil
    }

    // MARK: - Events

    private func bindEvents(_ modules: ModuleRegistry) {
        guard let state else { return }

        // Pomodoro results arrive as island alerts
        state.$alert
            .compactMap { $0 }
            .sink { [weak self] alert in
                switch alert {
                case .pomodoro(finished: .focus, next: _): self?.record(.focusCompleted)
                case .pomodoroSkipped:                      self?.record(.focusSkipped)
                default: break
                }
            }
            .store(in: &cancellables)

        modules.agents.onResult = { [weak self] status in
            self?.record(status == .finished ? .agentFinished : .agentFailed)
        }

        // Opening the island counts as attention, and wakes it up
        state.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                guard let self, expanded else { return }
                if self.asleep { self.wake() }
                if Date().timeIntervalSince(self.lastAttention) > 5 * 60 {
                    self.lastAttention = Date()
                    self.record(.attention)
                }
            }
            .store(in: &cancellables)

        // Activities pin the bot to the left side, next to the countdown or agent line
        state.$agentsActive.combineLatest(state.$pomodoroActive)
            .sink { [weak self] agents, pomodoro in
                guard let self, agents || pomodoro else { return }
                if self.asleep { self.wake() }
                self.crossing = false
                self.peek = 0
                self.side = .left
                self.publishGeometry()
            }
            .store(in: &cancellables)
    }

    private func record(_ event: BotLife.Event) {
        life.record(event)
        life.save()
        switch event {
        case .focusCompleted, .agentFinished: react(.celebrate, for: 3)
        case .focusSkipped, .agentFailed:     react(.sad, for: 3)
        default: break
        }
    }

    private func react(_ mood: PixelBot.Mood, for seconds: TimeInterval) {
        reactionTask?.cancel()
        reaction = mood
        reactionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.reaction = nil
        }
    }

    // MARK: - Vitals and sleep

    private func checkVitals() {
        life.advance(to: Date(), asleep: asleep)
        life.save()

        if modules?.nowPlaying.track?.isPlaying == true, Date().timeIntervalSince(lastMusicReward) > 5 * 60 {
            lastMusicReward = Date()
            life.record(.musicListened)
        }

        let idle = Self.secondsSinceLastInput()
        let busy = state?.agentsActive == true || state?.pomodoroActive == true
            || modules?.nowPlaying.track?.isPlaying == true
        if !asleep, !busy, idle > Self.sleepAfterIdle || life.isTired {
            fallAsleep()
        } else if asleep, busy || (idle < 30 && !life.isTired) {
            wake()
        }
    }

    private func fallAsleep() {
        asleep = true
        walking = false
        look = 0
        peek = 0
    }

    private func wake() {
        asleep = false
        react(.wave, for: 2)
    }

    private static func secondsSinceLastInput() -> TimeInterval {
        // kCGAnyInputEventType: any keyboard, mouse or trackpad event
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    // MARK: - Everyday behavior

    /// Picks a small action every few seconds: glance around, peek behind the camera,
    /// cross to the other side, or stroll along the strip when the island is open.
    private func liveLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3...7)))
            guard !Task.isCancelled, !asleep, reaction == nil, let state else { continue }

            if state.isExpanded {
                await stroll()
                continue
            }

            let roll = Double.random(in: 0..<1)
            switch roll {
            case ..<0.5:
                await glance()
            case ..<0.65 where isFree || state.agentsActive || state.pomodoroActive:
                await peekBehindCamera()
            case ..<0.8 where isFree:
                await crossToOtherSide()
            default:
                break // just stand there, blinking
            }
        }
    }

    private func glance() async {
        look = Bool.random() ? -1 : 1
        try? await Task.sleep(for: .seconds(Double.random(in: 0.8...1.8)))
        look = 0
    }

    private func peekBehindCamera() async {
        look = side == .left ? 1 : -1
        peek = 1
        try? await Task.sleep(for: .seconds(Double.random(in: 1.2...2.2)))
        peek = 0
        look = 0
    }

    private func crossToOtherSide() async {
        // Show both sides, walk behind the camera, then shrink to the new side
        crossing = true
        publishGeometry()
        try? await Task.sleep(for: .seconds(0.35))
        moveDuration = 1.6
        walking = true
        look = side == .left ? 1 : -1
        side = side == .left ? .right : .left
        try? await Task.sleep(for: .seconds(moveDuration))
        walking = false
        look = 0
        try? await Task.sleep(for: .seconds(0.3))
        crossing = false
        publishGeometry()
    }

    private func stroll() async {
        let target = CGFloat.random(in: 0...1)
        let distance = abs(target - stripPosition)
        guard distance > 0.08 else { return await glance() }
        look = target > stripPosition ? 1 : -1
        moveDuration = Double(distance / Self.stripSpeed)
        walking = true
        stripPosition = target
        try? await Task.sleep(for: .seconds(moveDuration))
        walking = false
        look = 0
    }

    private func publishGeometry() {
        state?.companionSide = side
        state?.companionCrossing = crossing
    }
}
