import Foundation

@MainActor
final class AIModuleStore: ObservableObject {

    @Published private(set) var chatAnswer: String? = nil
    @Published private(set) var isAnswering: Bool = false
    @Published private(set) var documentName: String? = nil
    /// Set when Apple Intelligence is off and the summary is only an extract of the text.
    @Published private(set) var unavailableReason: String? = nil

    // Extracted document text kept in memory for follow-up questions
    private(set) var documentText: String? = nil

    private weak var state: ShadespaceState?
    private var summaryTask: Task<Void, Never>?

    init(state: ShadespaceState) {
        self.state = state
    }

    // MARK: - Documents

    func summarize(url: URL) {
        summaryTask?.cancel()
        chatAnswer = nil
        documentText = nil
        documentName = url.lastPathComponent
        if case .unavailable(let reason) = AISummarizer.shared.availability {
            unavailableReason = reason
        } else {
            unavailableReason = nil
        }
        state?.mode = .aiReading(progress: 0.05)
        state?.expand()

        summaryTask = Task {
            // PDF text extraction can take a while on long documents; keep it off the main thread
            let extracted = await Task.detached(priority: .userInitiated) {
                Result { try AISummarizer.extractText(from: url) }
            }.value

            guard !Task.isCancelled else { return }
            let text: String
            switch extracted {
            case .success(let value):
                text = value
            case .failure(let error):
                state?.mode = .aiSummary(text: "Error: \(error.localizedDescription)")
                return
            }
            documentText = text.isEmpty ? nil : text
            state?.mode = .aiReading(progress: 0.15)

            let result = await AISummarizer.shared.summarize(text: text) { fraction in
                guard case .aiReading = self.state?.mode else { return }
                self.state?.mode = .aiReading(progress: 0.15 + 0.85 * fraction)
            }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let summary):
                state?.mode = .aiSummary(text: summary)
            case .failure(let err):
                state?.mode = .aiSummary(text: "Error: \(err.localizedDescription)")
            }
        }
    }

    // MARK: - Q&A

    func askQuestion(_ question: String) {
        guard let text = documentText, !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        chatAnswer = nil
        isAnswering = true

        Task {
            let result = await AISummarizer.shared.ask(question, context: text)
            switch result {
            case .success(let answer):
                chatAnswer = answer
            case .failure(let err):
                chatAnswer = "Error: \(err.localizedDescription)"
            }
            isAnswering = false
        }
    }

    // MARK: - Reset

    func reset() {
        summaryTask?.cancel()
        summaryTask = nil
        documentText = nil
        documentName = nil
        chatAnswer = nil
        isAnswering = false
        state?.mode = .idle
    }
}
