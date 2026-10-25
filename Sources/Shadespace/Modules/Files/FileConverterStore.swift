import AppKit
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class FileConverterStore: ObservableObject {

    private weak var state: ShadespaceState?

    init(state: ShadespaceState) {
        self.state = state
    }

    static func canConvert(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    func convert(url: URL) {
        state?.mode = .fileConverting
        state?.expand()

        Task {
            let result = await Self.convertImage(at: url)
            switch result {
            case .success(let outURL):
                state?.mode = .fileConversionDone(url: outURL)
            case .failure:
                state?.mode = .fileConversionError
            }
        }
    }

    func reset() {
        state?.mode = .idle
    }

    /// PNG → JPEG, JPEG → PNG. Other formats (HEIC, WebP, TIFF, GIF…) become PNG when they
    /// have transparency and JPEG otherwise. The original file is never overwritten.
    static func convertImage(at url: URL) async -> Result<URL, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
                else {
                    continuation.resume(returning: .failure(ConversionError.unreadable))
                    return
                }

                let sourceType = UTType(filenameExtension: url.pathExtension)
                let target: UTType
                if sourceType == .png {
                    target = .jpeg
                } else if sourceType == .jpeg {
                    target = .png
                } else {
                    target = hasAlpha(image) ? .png : .jpeg
                }

                let outURL = uniqueURL(for: url, ext: target == .jpeg ? "jpg" : "png")
                guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, target.identifier as CFString, 1, nil) else {
                    continuation.resume(returning: .failure(ConversionError.unwritable))
                    return
                }

                let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
                CGImageDestinationAddImage(dest, image, target == .jpeg ? options : nil)
                if CGImageDestinationFinalize(dest) {
                    continuation.resume(returning: .success(outURL))
                } else {
                    continuation.resume(returning: .failure(ConversionError.unwritable))
                }
            }
        }
    }

    private nonisolated static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// "photo.jpg" → "photo.png", or "photo 2.png" if that already exists.
    private nonisolated static func uniqueURL(for url: URL, ext: String) -> URL {
        let base = url.deletingPathExtension()
        var candidate = base.appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent) \(index)")
                .appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    enum ConversionError: Error {
        case unreadable, unwritable
    }
}
