import AppKit

struct ClipboardEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let createdAt: Date
    var summary: String?
    var displayText: String { String(text.prefix(120)) }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    private let pb = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let maxEntries = 20

    func start() {
        lastChangeCount = pb.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func paste(_ entry: ClipboardEntry) {
        pb.clearContents()
        pb.setString(entry.text, forType: .string)
        lastChangeCount = pb.changeCount
        PasteService.simulatePasteKeystroke()
    }

    private func tick() {
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              entries.first?.text != text else { return }
        let entry = ClipboardEntry(text: text, createdAt: Date())
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast() }
    }
}
