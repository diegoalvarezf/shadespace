import AppKit

struct TrayItem: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// A shelf for files: drop them on the notch, drag them out later into any app.
/// Stores references to the original files (not copies) and remembers them across launches.
@MainActor
final class FileTrayStore: ObservableObject {
    @Published private(set) var items: [TrayItem] = []

    private static let defaultsKey = "fileTray.paths"
    private static let maxItems = 24
    private weak var state: ShadespaceState?

    init(state: ShadespaceState) {
        self.state = state
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        items = paths.map { TrayItem(url: URL(fileURLWithPath: $0)) }
        pruneMissing()
    }

    func add(_ urls: [URL]) {
        let existing = Set(items.map(\.url))
        let new = urls.filter { !existing.contains($0) }.map { TrayItem(url: $0) }
        guard !new.isEmpty else { return }
        items = Array((new + items).prefix(Self.maxItems))
        save()
        state?.page = .tray
        state?.showAlert(.trayAdded(count: new.count), duration: 2.5)
    }

    func remove(_ item: TrayItem) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items = []
        save()
    }

    func open(_ item: TrayItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: TrayItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Drops files that were moved or deleted since they were added.
    func pruneMissing() {
        let before = items.count
        items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        if items.count != before { save() }
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: Self.defaultsKey)
    }
}
