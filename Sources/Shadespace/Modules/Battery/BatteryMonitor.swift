import IOKit.ps
import Foundation
import AppKit

/// Watches the internal battery through IOKit power-source notifications (no polling).
/// Raises island alerts when the charger is plugged in, the battery runs low, or it's full.
@MainActor
final class BatteryMonitor: ObservableObject {

    @Published private(set) var isCharging = false
    @Published private(set) var isOnAC = false
    @Published private(set) var batteryPercent: Int = 100
    @Published private(set) var hasBattery = false

    private static let lowThresholds = [20, 10]

    private weak var state: ShadespaceState?
    private var runLoopSource: CFRunLoopSource?
    private var previouslyOnAC = false
    private var previouslyCharged = false
    // Lowest threshold already announced during this discharge, so each fires once
    private var announcedLowThreshold: Int?

    init(state: ShadespaceState) {
        self.state = state
        readBattery()
        previouslyOnAC = isOnAC
        previouslyCharged = isOnAC && batteryPercent >= 100
        startNotifications()
    }

    // MARK: - Private

    private func startNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.handleChange() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    private func handleChange() {
        readBattery()
        guard hasBattery, let state, AppSettings.shared.batteryAlerts else {
            previouslyOnAC = isOnAC
            return
        }

        if isOnAC && !previouslyOnAC {
            announcedLowThreshold = nil
            state.showAlert(.charging(percent: batteryPercent))
        }

        let charged = isOnAC && batteryPercent >= 100
        if charged && !previouslyCharged {
            state.showAlert(.batteryFull)
        }

        if !isOnAC, let threshold = Self.lowThresholds.last(where: { batteryPercent <= $0 }),
           threshold < (announcedLowThreshold ?? Int.max) {
            announcedLowThreshold = threshold
            state.showAlert(.batteryLow(percent: batteryPercent), duration: 6)
        }

        previouslyOnAC = isOnAC
        previouslyCharged = charged
    }

    private func readBattery() {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sourcesList = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            hasBattery = false
            return
        }

        let battery = sourcesList
            .compactMap { IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }

        guard let info = battery else {
            hasBattery = false
            return
        }

        hasBattery = true
        isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
        isOnAC = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 100
        let maxCapacity = info[kIOPSMaxCapacityKey] as? Int ?? 100
        batteryPercent = maxCapacity > 0 ? Int((Double(capacity) / Double(maxCapacity) * 100).rounded()) : 100
    }
}
