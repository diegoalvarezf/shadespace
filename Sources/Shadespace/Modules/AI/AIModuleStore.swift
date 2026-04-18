import Foundation

@MainActor
final class AIModuleStore: ObservableObject {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        var text: String
        enum Role { case user, model }
    }

    @Published var prompt: String = ""
    @Published private(set) var history: [Turn] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var isAvailable: Bool = false

    init() {
        if #available(macOS 26, *) {
            isAvailable = AISummarizer.shared.isAvailable
        }
    }

    func send() {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !isGenerating else { return }
        prompt = ""
        history.append(Turn(role: .user, text: p))
        history.append(Turn(role: .model, text: ""))
        isGenerating = true

        Task {
            if #available(macOS 26, *) {
                await streamResponse(p)
            } else {
                finalizeLast(with: "Apple Intelligence requires macOS 26 Sequoia or later.")
            }
        }
    }

    @available(macOS 26, *)
    private func streamResponse(_ prompt: String) async {
        do {
            for try await chunk in AISummarizer.shared.stream(prompt) {
                appendToLast(chunk)
            }
        } catch {
            finalizeLast(with: "Error: \(error.localizedDescription)")
        }
        isGenerating = false
    }

    private func appendToLast(_ text: String) {
        guard !history.isEmpty else { return }
        history[history.count - 1].text = text
    }

    private func finalizeLast(with text: String) {
        appendToLast(text)
        isGenerating = false
    }
}
