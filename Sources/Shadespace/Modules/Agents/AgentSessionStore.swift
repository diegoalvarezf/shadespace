import Foundation
import Security

struct AgentSession: Identifiable, Equatable {
    enum Status: Equatable {
        case idle        // started, waiting for a prompt
        case working
        case needsInput  // permission prompt, question or idle prompt
        case finished
        case failed
    }

    let id: String
    var project: String
    var status: Status
    var step: String
    var startedAt: Date
    var updatedAt: Date
    var statusChangedAt: Date

    var botMood: PixelBot.Mood {
        switch status {
        case .idle:       return .focus
        case .working:    return .working
        case .needsInput: return .needsYou
        case .finished:   return .celebrate
        case .failed:     return .sad
        }
    }
}

/// Tracks Claude Code sessions from their hook events and decides what the notch shows.
@MainActor
final class AgentSessionStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var serverError: String?

    /// Finished or failed sessions stay on the notch this long before it hides again.
    private static let resultDisplayDuration: TimeInterval = 6
    /// A session that stops sending events (killed terminal, lost hook) leaves the notch after
    /// this long; a long Bash command can legitimately stay silent for a few minutes.
    private static let workingQuietLimit: TimeInterval = 10 * 60
    private static let waitingQuietLimit: TimeInterval = 30 * 60
    /// Sessions that went quiet (closed terminal without SessionEnd) are dropped after this.
    private static let staleAfter: TimeInterval = 2 * 60 * 60
    private static let tokenKey = "agents.hookToken"

    /// Called when a session finishes or fails, so the companion can react.
    var onResult: ((AgentSession.Status) -> Void)?

    private weak var state: ShadespaceState?
    private var server: AgentHookServer?
    private var expiryTask: Task<Void, Never>?

    init(state: ShadespaceState) {
        self.state = state
        let server = AgentHookServer(token: Self.hookToken) { [weak self] body in
            await self?.handle(body)
        }
        server.start()
        self.server = server
        if let error = server.startError {
            serverError = "Couldn't listen on port \(AgentHookServer.port): \(error.localizedDescription)"
        }
    }

    /// Random secret the hooks send back in a header, created once per install.
    static var hookToken: String {
        if let token = UserDefaults.standard.string(forKey: tokenKey) { return token }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        return token
    }

    // MARK: - What the notch shows

    /// Sessions worth showing beside the notch: working or waiting, or just finished.
    var visibleSessions: [AgentSession] {
        let now = Date()
        return sessions.filter { now < Self.hideDate(of: $0) }
    }

    /// The session the notch talks about: one that needs you first, then the latest active one.
    var primarySession: AgentSession? {
        let visible = visibleSessions
        return visible.first { $0.status == .needsInput }
            ?? visible.max { $0.updatedAt < $1.updatedAt }
    }

    var needsInput: Bool { sessions.contains { $0.status == .needsInput } }

    // MARK: - Events

    /// Called for every hook POST. Phase 1 only observes, so the body is always empty and
    /// Claude Code carries on with its normal behavior.
    private func handle(_ body: Data) async -> Data? {
        guard let event = AgentEvent(json: body) else { return nil }
        apply(event)
        return nil
    }

    func apply(_ event: AgentEvent, at now: Date = Date()) {
        if event.name == "SessionEnd" {
            sessions.removeAll { $0.id == event.sessionID }
            publish()
            return
        }

        var session = sessions.first { $0.id == event.sessionID }
            ?? AgentSession(id: event.sessionID, project: event.projectName, status: .idle,
                            step: "Started", startedAt: now, updatedAt: now, statusChangedAt: now)
        let previousStatus = session.status
        session.project = event.projectName
        session.updatedAt = now

        switch event.name {
        case "SessionStart":
            session.status = .idle
            session.step = "Started"
        case "UserPromptSubmit":
            session.status = .working
            session.step = "Thinking…"
        case "PreToolUse":
            session.status = .working
            session.step = event.toolStep(withChanges: false)
        case "PostToolUse":
            session.status = .working
            session.step = event.toolStep(withChanges: true)
        case "PostToolUseFailure":
            // A failed tool call is routine; the agent keeps going
            session.status = .working
            session.step = "\(event.toolName ?? "Tool") failed"
        case "PermissionRequest":
            session.status = .needsInput
            session.step = "Wants to " + event.toolStep(withChanges: false)
        case "Notification":
            switch event.notificationType {
            case "permission_prompt", "idle_prompt", "elicitation_dialog", "agent_needs_input":
                session.status = .needsInput
                session.step = event.message ?? "Waiting for you"
            default:
                break
            }
        case "Stop":
            session.status = .finished
            session.step = "Done"
        case "StopFailure":
            session.status = .failed
            session.step = event.error ?? "Stopped with an error"
        default:
            break
        }

        if session.status != previousStatus {
            session.statusChangedAt = now
            if session.status == .finished || session.status == .failed { onResult?(session.status) }
        }
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
        sessions.removeAll { now.timeIntervalSince($0.updatedAt) > Self.staleAfter }
        publish()
    }

    // MARK: - Private

    /// When a session stops being shown beside the notch.
    private static func hideDate(of session: AgentSession) -> Date {
        switch session.status {
        case .working:            return session.updatedAt.addingTimeInterval(workingQuietLimit)
        case .needsInput:         return session.updatedAt.addingTimeInterval(waitingQuietLimit)
        case .finished, .failed:  return session.statusChangedAt.addingTimeInterval(resultDisplayDuration)
        case .idle:               return .distantPast
        }
    }

    private func publish() {
        state?.agentsActive = !visibleSessions.isEmpty
        objectWillChange.send()

        // Re-evaluate when the next visible session is due to leave the notch
        expiryTask?.cancel()
        let now = Date()
        let pending = sessions
            .map { Self.hideDate(of: $0).timeIntervalSince(now) }
            .filter { $0 > 0 }
        guard let wait = pending.min() else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait + 0.1))
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }
}
