import Foundation

@MainActor
final class AISummarizer {
    static let shared = AISummarizer()

    var isAvailable: Bool {
        if #available(macOS 26, *) {
            return checkAvailability()
        }
        return false
    }

    @available(macOS 26, *)
    private func checkAvailability() -> Bool {
        // FoundationModels availability check — isolated behind @available
        return true // Will be updated when FoundationModels API stabilizes
    }

    func shortSummary(of text: String) async -> String? {
        guard #available(macOS 26, *) else { return nil }
        return await generateSummary(text)
    }

    @available(macOS 26, *)
    private func generateSummary(_ text: String) async -> String? {
        // FoundationModels integration — isolated to avoid compile issues on macOS 14
        return nil
    }

    func stream(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        if #available(macOS 26, *) {
            return streamWithFoundationModels(prompt)
        }
        return AsyncThrowingStream { $0.finish() }
    }

    @available(macOS 26, *)
    private func streamWithFoundationModels(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: nil)
        }
    }
}
