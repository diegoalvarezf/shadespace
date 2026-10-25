import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Shadespace

final class LyricsTests: XCTestCase {
    func testParsesTimestampsAndSortsLines() {
        let lrc = """
        [00:12.50] Second
        [00:01.00][00:30.00] Chorus
        [ar: Someone]
        [01:05.25]Last
        """
        let lines = LyricsService.parse(lrc: lrc)
        XCTAssertEqual(lines.map(\.text), ["Chorus", "Second", "Chorus", "Last"])
        XCTAssertEqual(lines.last?.time ?? 0, 65.25, accuracy: 0.001)
    }

    func testCurrentLineLookup() {
        let lines = [LyricLine(time: 1, text: "a"), LyricLine(time: 5, text: "b"), LyricLine(time: 9, text: "c")]
        XCTAssertNil(lines.line(at: 0.5))
        XCTAssertEqual(lines.line(at: 1)?.text, "a")
        XCTAssertEqual(lines.line(at: 7)?.text, "b")
        XCTAssertEqual(lines.line(at: 100)?.text, "c")
        XCTAssertNil([LyricLine]().line(at: 3))
    }
}

final class NowPlayingTrackTests: XCTestCase {
    private func track(playing: Bool, position: Double = 10, duration: Double = 100) -> NowPlayingTrack {
        NowPlayingTrack(source: .spotify, title: "T", artist: "A", album: "B", isPlaying: playing,
                        positionSec: position, durationSec: duration, artworkURL: nil,
                        shuffle: false, repeatMode: .off)
    }

    func testPositionExtrapolatesOnlyWhilePlaying() {
        let start = Date()
        XCTAssertEqual(track(playing: true).position(at: start.addingTimeInterval(5), since: start), 15, accuracy: 0.001)
        XCTAssertEqual(track(playing: false).position(at: start.addingTimeInterval(5), since: start), 10, accuracy: 0.001)
    }

    func testPositionIsClampedToDuration() {
        let start = Date()
        XCTAssertEqual(track(playing: true, position: 95).position(at: start.addingTimeInterval(60), since: start), 100)
        XCTAssertEqual(track(playing: true).progress(at: start, since: start), 0.1, accuracy: 0.001)
    }

    func testSongIDIgnoresPlaybackState() {
        XCTAssertEqual(track(playing: true).songID, track(playing: false, position: 50).songID)
    }
}

@MainActor
final class SummarizerTextTests: XCTestCase {
    func testChunksRespectSizeAndKeepAllText() {
        let paragraph = String(repeating: "word ", count: 300) // 1500 chars
        let text = Array(repeating: paragraph, count: 10).joined(separator: "\n")
        let chunks = AISummarizer.chunks(of: text, size: 4000)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 4000 })
        XCTAssertEqual(chunks.joined(separator: "\n").count, text.count)
    }

    func testOversizedParagraphIsSplit() {
        let text = String(repeating: "x", count: 10_000)
        let chunks = AISummarizer.chunks(of: text, size: 3000)
        XCTAssertEqual(chunks.count, 4)
        XCTAssertEqual(chunks.map(\.count).reduce(0, +), 10_000)
    }

    func testDetectsDocumentLanguageByName() {
        XCTAssertEqual(AISummarizer.languageName(of: "Este documento explica cómo funciona la aplicación y sus módulos."), "Spanish")
        XCTAssertEqual(AISummarizer.languageName(of: "This document explains how the application and its modules work."), "English")
    }

    func testRecognizesSummarizableFiles() {
        XCTAssertTrue(AISummarizer.canSummarize(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertTrue(AISummarizer.canSummarize(URL(fileURLWithPath: "/tmp/a.md")))
        XCTAssertTrue(AISummarizer.canSummarize(URL(fileURLWithPath: "/tmp/a.docx")))
        XCTAssertFalse(AISummarizer.canSummarize(URL(fileURLWithPath: "/tmp/a.png")))
    }
}

@MainActor
final class FileConverterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writePNG(named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func testPNGBecomesJPEGWithoutOverwriting() async throws {
        let png = try writePNG(named: "photo.png")
        // An existing "photo.jpg" must not be replaced
        try Data("keep".utf8).write(to: directory.appendingPathComponent("photo.jpg"))

        let result = await FileConverterStore.convertImage(at: png)
        let out = try result.get()
        XCTAssertEqual(out.lastPathComponent, "photo 2.jpg")
        let source = CGImageSourceCreateWithURL(out as CFURL, nil)
        XCTAssertEqual(source.flatMap { CGImageSourceGetType($0) } as String?, UTType.jpeg.identifier)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("photo.jpg"), encoding: .utf8), "keep")
    }

    func testCanConvertOnlyImages() {
        XCTAssertTrue(FileConverterStore.canConvert(URL(fileURLWithPath: "/tmp/a.heic")))
        XCTAssertFalse(FileConverterStore.canConvert(URL(fileURLWithPath: "/tmp/a.pdf")))
    }
}

final class StatusModelTests: XCTestCase {
    func testWeatherSymbols() {
        func snapshot(_ code: Int, day: Bool = true) -> WeatherSnapshot {
            WeatherSnapshot(temperature: 20, high: 22, low: 12, code: code, isDay: day, fahrenheit: false)
        }
        XCTAssertEqual(snapshot(0).symbol, "sun.max.fill")
        XCTAssertEqual(snapshot(0, day: false).symbol, "moon.stars.fill")
        XCTAssertEqual(snapshot(63).symbol, "cloud.rain.fill")
        XCTAssertEqual(snapshot(95).symbol, "cloud.bolt.rain.fill")
    }

    func testAirPodsSymbols() {
        XCTAssertEqual(AirPodsStatus(name: "AirPods Pro de Diego").symbol, "airpodspro")
        XCTAssertEqual(AirPodsStatus(name: "AirPods Max").symbol, "airpodsmax")
        XCTAssertEqual(AirPodsStatus(name: "WH-1000XM5").symbol, "headphones")
        XCTAssertFalse(AirPodsStatus(name: "X").hasBattery)
    }
}
