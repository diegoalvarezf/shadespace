import AppKit

/// Sends files with AirDrop through the system sharing service.
@MainActor
enum AirDropService {
    static var isAvailable: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            NSSound.beep()
            return
        }
        // Shadespace is a menu bar app; it must be active for the AirDrop picker to come forward
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }
}
