import Foundation

/// The companion's two vital signs, both in 0…1. They drift with time and react to what you do;
/// they never reach a state the bot can't recover from.
struct BotLife: Codable, Equatable {
    var happiness: Double = 0.7
    var energy: Double = 0.8
    var updatedAt = Date()

    /// Things that happen around the bot.
    enum Event {
        case focusCompleted, focusSkipped
        case agentFinished, agentFailed
        case musicListened      // a few minutes of music
        case attention          // hovered or opened the island
    }

    // Per-hour drift
    private static let happinessDecay = 0.03
    private static let energyDecayAwake = 0.04
    private static let energyGainAsleep = 0.2

    var isTired: Bool { energy < 0.15 }
    var isGloomy: Bool { happiness < 0.3 }

    /// Applies the time passed since the last update.
    mutating func advance(to now: Date, asleep: Bool) {
        let hours = max(0, now.timeIntervalSince(updatedAt) / 3600)
        happiness -= Self.happinessDecay * hours
        energy += (asleep ? Self.energyGainAsleep : -Self.energyDecayAwake) * hours
        clamp()
        updatedAt = now
    }

    mutating func record(_ event: Event) {
        switch event {
        case .focusCompleted: happiness += 0.15; energy -= 0.05
        case .focusSkipped:   happiness -= 0.1
        case .agentFinished:  happiness += 0.05
        case .agentFailed:    happiness -= 0.05
        case .musicListened:  happiness += 0.02
        case .attention:      happiness += 0.01
        }
        clamp()
    }

    private mutating func clamp() {
        // A small floor keeps the bot recoverable: neglected, never gone
        happiness = min(max(happiness, 0.05), 1)
        energy = min(max(energy, 0.05), 1)
    }

    // MARK: - Persistence

    private static let key = "companion.life"

    static func load() -> BotLife {
        guard let data = UserDefaults.standard.data(forKey: key),
              let life = try? JSONDecoder().decode(BotLife.self, from: data) else { return BotLife() }
        return life
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
