import Foundation
import IOBluetooth

struct AirPodsStatus: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// Single-battery headphones (AirPods Max, Beats Solo…) report one combined value.
    var single: Int?

    var symbol: String {
        let lower = name.lowercased()
        if lower.contains("max") { return "airpodsmax" }
        if lower.contains("pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        return "headphones"
    }

    var hasBattery: Bool { left != nil || right != nil || single != nil }
}

/// Announces Bluetooth headphones when they connect, with their battery levels when available.
///
/// Connection events use the public IOBluetooth notification API. Per-bud battery levels are
/// undocumented `IOBluetoothDevice` properties, so every read is guarded and simply omitted
/// when the running macOS doesn't expose them.
@MainActor
final class AirPodsMonitor: NSObject {
    private weak var state: ShadespaceState?
    private var connectNotification: IOBluetoothUserNotification?
    // Devices connected before launch would otherwise be announced at startup
    private let launchDate = Date()

    init(state: ShadespaceState) {
        self.state = state
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard Date().timeIntervalSince(launchDate) > 3 else { return }
        guard AppSettings.shared.airPodsAlerts, Self.isHeadphones(device) else { return }

        // Battery values arrive a moment after the link comes up; read them after a short delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, device.isConnected() else { return }
            let status = Self.status(of: device)
            self.state?.showAlert(.airPods(status), duration: 5)
        }
    }

    private static func isHeadphones(_ device: IOBluetoothDevice) -> Bool {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods") || name.contains("beats") { return true }
        return device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio)
    }

    private static func status(of device: IOBluetoothDevice) -> AirPodsStatus {
        AirPodsStatus(
            name: device.name ?? "Headphones",
            left: batteryValue(device, "batteryPercentLeft"),
            right: batteryValue(device, "batteryPercentRight"),
            caseLevel: batteryValue(device, "batteryPercentCase"),
            single: batteryValue(device, "batteryPercentSingle")
        )
    }

    private static func batteryValue(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)),
              let number = device.value(forKey: key) as? NSNumber else { return nil }
        let value = number.intValue
        return (1...100).contains(value) ? value : nil
    }
}
