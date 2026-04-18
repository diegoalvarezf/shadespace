import AppKit

@MainActor
final class FocusController: ObservableObject {
    @Published private(set) var isEnabled = false

    func toggle() {
        isEnabled.toggle()
        let shortcut = isEnabled ? "Turn On Do Not Disturb" : "Turn Off Do Not Disturb"
        Task.detached {
            let p = Process()
            p.launchPath = "/usr/bin/shortcuts"
            p.arguments = ["run", shortcut]
            try? p.run()
            p.waitUntilExit()
        }
    }
}
