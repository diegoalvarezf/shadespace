import Foundation
import ServiceManagement

/// User preferences, persisted in UserDefaults and exposed through the status bar menu.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Off: the island hides inside the physical notch until hovered. On: a strip below the
    /// notch shows the current song or activity.
    @Published var showLiveActivity: Bool { didSet { save(showLiveActivity, .showLiveActivity) } }
    @Published var lyricsEnabled: Bool { didSet { save(lyricsEnabled, .lyricsEnabled) } }
    @Published var lyricsInNotch: Bool { didSet { save(lyricsInNotch, .lyricsInNotch) } }
    @Published var weatherEnabled: Bool { didSet { save(weatherEnabled, .weatherEnabled) } }
    @Published var useFahrenheit: Bool { didSet { save(useFahrenheit, .useFahrenheit) } }
    @Published var batteryAlerts: Bool { didSet { save(batteryAlerts, .batteryAlerts) } }
    @Published var airPodsAlerts: Bool { didSet { save(airPodsAlerts, .airPodsAlerts) } }
    /// The pixel bot lives beside the notch even when nothing else is going on.
    @Published var companionEnabled: Bool { didSet { save(companionEnabled, .companionEnabled) } }
    @Published var botColor: BotColor { didSet { defaults.set(botColor.rawValue, forKey: Key.botColor.rawValue) } }

    private enum Key: String {
        case showLiveActivity, lyricsEnabled, lyricsInNotch, weatherEnabled, useFahrenheit, batteryAlerts, airPodsAlerts, botColor, companionEnabled
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.showLiveActivity.rawValue: false,
            Key.lyricsEnabled.rawValue: true,
            Key.lyricsInNotch.rawValue: false,
            Key.weatherEnabled.rawValue: true,
            Key.useFahrenheit.rawValue: false,
            Key.batteryAlerts.rawValue: true,
            Key.airPodsAlerts.rawValue: true,
            Key.companionEnabled.rawValue: true,
        ])
        showLiveActivity = defaults.bool(forKey: Key.showLiveActivity.rawValue)
        lyricsEnabled = defaults.bool(forKey: Key.lyricsEnabled.rawValue)
        lyricsInNotch = defaults.bool(forKey: Key.lyricsInNotch.rawValue)
        weatherEnabled = defaults.bool(forKey: Key.weatherEnabled.rawValue)
        useFahrenheit = defaults.bool(forKey: Key.useFahrenheit.rawValue)
        batteryAlerts = defaults.bool(forKey: Key.batteryAlerts.rawValue)
        airPodsAlerts = defaults.bool(forKey: Key.airPodsAlerts.rawValue)
        companionEnabled = defaults.bool(forKey: Key.companionEnabled.rawValue)
        botColor = BotColor(rawValue: defaults.string(forKey: Key.botColor.rawValue) ?? "") ?? .cyan
    }

    private func save(_ value: Bool, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    // MARK: - Launch at login (backed by the system, not UserDefaults)

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Shadespace: launch at login change failed: \(error)")
        }
        objectWillChange.send()
    }
}
