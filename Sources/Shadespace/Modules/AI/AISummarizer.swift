import AppKit
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Summarizes and answers questions about documents with Apple's on-device model
/// (Foundation Models, macOS 26+). Nothing leaves the Mac. When Apple Intelligence is
/// unavailable it falls back to an extractive summary built from the text itself.
@MainActor
final class AISummarizer {
    static let shared = AISummarizer()

    // The on-device model has a 4096-token window (prompt + answer). ~4 chars per token,
    // so chunks of ~6000 chars leave room for instructions and the response.
    private nonisolated static let chunkSize = 6000
    private static let maxChunks = 8

    enum Availability: Equatable {
        case available
        case unavailable(reason: String)
    }

    var availability: Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(reason: "Turn on Apple Intelligence in System Settings for AI summaries.")
            case .unavailable(.deviceNotEligible):
                return .unavailable(reason: "This Mac doesn't support Apple Intelligence.")
            case .unavailable(.modelNotReady):
                return .unavailable(reason: "The Apple Intelligence model is still downloading.")
            case .unavailable:
                return .unavailable(reason: "Apple Intelligence is unavailable.")
            }
        }
        #endif
        return .unavailable(reason: "AI summaries require macOS 26 or later.")
    }

    static func canSummarize(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        if type.conforms(to: .pdf) || type.conforms(to: .text) { return true }
        let wordTypes = ["org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc",
                         "org.oasis-open.opendocument.text"]
        return wordTypes.contains(type.identifier)
    }

    // MARK: - Summary

    /// `progress` receives values in 0...1 as chunks are processed.
    func summarize(text: String, progress: @escaping (Double) -> Void) async -> Result<String, Error> {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return .failure(SummarizerError.emptyDocument) }

        #if canImport(FoundationModels)
        if #available(macOS 26, *), availability == .available {
            do {
                return .success(try await summarizeWithModel(clean, progress: progress))
            } catch {
                return .failure(error)
            }
        }
        #endif
        progress(1)
        return .success(Self.extractiveSummary(clean))
    }

    // MARK: - Q&A

    func ask(_ question: String, context documentText: String) async -> Result<String, Error> {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), availability == .available {
            do {
                return .success(try await askWithModel(question, context: documentText))
            } catch {
                return .failure(error)
            }
        }
        #endif
        if case .unavailable(let reason) = availability {
            return .failure(SummarizerError.unavailable(reason))
        }
        return .failure(SummarizerError.unavailable("Apple Intelligence is unavailable."))
    }

    // MARK: - Foundation Models

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func summarizeWithModel(_ text: String, progress: @escaping (Double) -> Void) async throws -> String {
        let chunks = Self.sampledChunks(of: text)
        let instructions = """
        You summarize documents. Always write in \(Self.languageName(of: text)). \
        Be concise and factual. Do not add information that is not in the text.
        """

        if chunks.count == 1 {
            let session = LanguageModelSession(instructions: instructions)
            progress(0.3)
            let response = try await session.respond(to: "Summarize this document in 3 to 5 sentences:\n\n\(chunks[0])")
            progress(1)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Map: summarize each chunk on its own. Reduce: merge the partial summaries.
        var partials: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: "Summarize this part of a longer document in 2 sentences:\n\n\(chunk)")
            partials.append(response.content)
            progress(Double(index + 1) / Double(chunks.count + 1))
        }

        let session = LanguageModelSession(instructions: instructions)
        let joined = partials.enumerated().map { "Part \($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        let response = try await session.respond(to: """
        These are summaries of consecutive parts of one document. \
        Write a single summary of the whole document in 4 to 6 sentences:

        \(joined)
        """)
        progress(1)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @available(macOS 26, *)
    private func askWithModel(_ question: String, context: String) async throws -> String {
        let passages = Self.relevantPassages(for: question, in: context)
        let session = LanguageModelSession(instructions: """
        You answer questions about a document using only the excerpts provided. \
        Always answer in \(Self.languageName(of: question)), in at most 3 sentences. \
        If the excerpts don't contain the answer, say so.
        """)
        let response = try await session.respond(to: "Excerpts:\n\(passages)\n\nQuestion: \(question)")
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    // MARK: - Text helpers

    /// The model tends to answer in English unless told the language by name.
    nonisolated static func languageName(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        guard let code = recognizer.dominantLanguage?.rawValue,
              let name = Locale(identifier: "en").localizedString(forLanguageCode: code) else {
            return "the same language as the text"
        }
        return name
    }

    static func chunks(of text: String, size: Int = chunkSize) -> [String] {
        var result: [String] = []
        var current = ""
        // Split on paragraph boundaries when possible so chunks stay coherent
        for paragraph in text.components(separatedBy: "\n") {
            if current.count + paragraph.count > size, !current.isEmpty {
                result.append(current)
                current = ""
            }
            if paragraph.count > size {
                var rest = Substring(paragraph)
                while rest.count > size {
                    result.append(String(rest.prefix(size)))
                    rest = rest.dropFirst(size)
                }
                current = String(rest)
            } else {
                current += (current.isEmpty ? "" : "\n") + paragraph
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(current) }
        return result
    }

    /// Very long documents are sampled evenly so the summary covers start, middle and end.
    private static func sampledChunks(of text: String) -> [String] {
        let all = chunks(of: text)
        guard all.count > maxChunks else { return all }
        let step = Double(all.count - 1) / Double(maxChunks - 1)
        return (0..<maxChunks).map { all[Int((Double($0) * step).rounded())] }
    }

    /// Picks the chunks that share the most words with the question.
    private static func relevantPassages(for question: String, in text: String) -> String {
        let words = Set(question.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 })
        let pieces = chunks(of: text, size: 2500)
        let ranked = pieces.enumerated().map { index, piece -> (Int, Int) in
            let lower = piece.lowercased()
            return (index, words.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) })
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        // Keep document order among the best two so the excerpt reads naturally
        let best = ranked.prefix(2).map(\.0).sorted()
        return best.map { pieces[$0] }.joined(separator: "\n…\n")
    }

    /// Fallback without a model: the opening sentences of the document.
    private static func extractiveSummary(_ text: String) -> String {
        let sentences = text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 30 }
        let summary = sentences.prefix(4).joined(separator: ". ")
        return summary.isEmpty ? String(text.prefix(400)) : summary + "."
    }

    nonisolated static func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw SummarizerError.unreadable }
            return (0..<pdf.pageCount)
                .compactMap { pdf.page(at: $0)?.string }
                .joined(separator: "\n")
        }
        // Rich formats (RTF, HTML, Word, OpenDocument) through AppKit's text importers
        if ["rtf", "rtfd", "html", "htm", "doc", "docx", "odt"].contains(ext),
           let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            return attributed.string
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    enum SummarizerError: LocalizedError {
        case unavailable(String), emptyDocument, unreadable
        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .emptyDocument:           return "The document appears to be empty."
            case .unreadable:              return "The document couldn't be read."
            }
        }
    }
}
