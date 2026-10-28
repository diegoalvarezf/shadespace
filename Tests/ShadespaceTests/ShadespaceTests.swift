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

@MainActor
final class DropRoutingTests: XCTestCase {
    func testSupportedZonesDependOnFileType() {
        let image = [URL(fileURLWithPath: "/tmp/photo.png")]
        let pdf = [URL(fileURLWithPath: "/tmp/paper.pdf")]
        let zip = [URL(fileURLWithPath: "/tmp/archive.zip")]
        // AirDrop takes any file when the Mac supports it
        let airDrop: Set<DropZone> = AirDropService.isAvailable ? [.airDrop] : []
        XCTAssertEqual(ModuleRegistry.supportedZones(for: image), Set<DropZone>([.convert, .tray]).union(airDrop))
        XCTAssertEqual(ModuleRegistry.supportedZones(for: pdf), Set<DropZone>([.summarize, .tray]).union(airDrop))
        XCTAssertEqual(ModuleRegistry.supportedZones(for: zip), Set<DropZone>([.tray]).union(airDrop))
        XCTAssertEqual(ModuleRegistry.supportedZones(for: []), [.tray])
    }
}

@MainActor
final class PomodoroTests: XCTestCase {
    func testCycleGoesFocusShortBreakThenLongBreakAfterFour() {
        let timer = PomodoroTimer(state: ShadespaceState(screen: NSScreen.screens[0]))
        timer.reset()
        var phases: [PomodoroPhase] = []
        for _ in 0..<8 {
            phases.append(timer.phase)
            timer.skip()
        }
        XCTAssertEqual(phases, [.focus, .shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak])
        // The eighth skip ended the long break: a new cycle starts
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.completedFocusSessions, 0)
    }

    func testPauseKeepsRemainingTime() {
        let timer = PomodoroTimer(state: ShadespaceState(screen: NSScreen.screens[0]))
        timer.reset()
        timer.focusMinutes = 25
        timer.startOrPause()
        XCTAssertTrue(timer.isRunning)
        timer.startOrPause()
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remaining(at: Date().addingTimeInterval(600)), 25 * 60, accuracy: 1)
        timer.reset()
    }

    func testFormat() {
        XCTAssertEqual(PomodoroView.format(25 * 60), "25:00")
        XCTAssertEqual(PomodoroView.format(59.2), "1:00")
        XCTAssertEqual(PomodoroView.format(0), "0:00")
    }
}

final class HooksInstallerTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func read() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// A settings file shaped like a real one: other keys and someone else's hooks.
    private func writeExisting() throws {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": [
                "PreToolUse": [["matcher": "Read", "hooks": [["type": "command", "command": "node other.js"]]]],
                "UserPromptSubmit": [["hooks": [["type": "command", "command": "node other.js"]]]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: url)
    }

    func testInstallMergesWithoutTouchingExistingHooks() throws {
        try writeExisting()
        let backup = try ClaudeCodeHooksInstaller.install(token: "abc", at: url)

        XCTAssertNotNil(backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup!.path))
        let settings = try read()
        XCTAssertEqual(settings["model"] as? String, "opus")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let pre = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(pre.count, 2)
        XCTAssertEqual(pre[0]["matcher"] as? String, "Read")
        let ours = try XCTUnwrap((pre[1]["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(ours["type"] as? String, "http")
        XCTAssertEqual(ours["url"] as? String, AgentHookServer.url)
        XCTAssertEqual((ours["headers"] as? [String: String])?["X-Shadespace-Token"], "abc")
        XCTAssertTrue(ClaudeCodeHooksInstaller.isInstalled(at: url))
    }

    func testReinstallReplacesOnlyItsOwnEntry() throws {
        try writeExisting()
        try ClaudeCodeHooksInstaller.install(token: "old", at: url)
        try ClaudeCodeHooksInstaller.install(token: "new", at: url)
        let hooks = try XCTUnwrap(try read()["hooks"] as? [String: Any])
        let pre = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(pre.count, 2)
        let header = (pre[1]["hooks"] as? [[String: Any]])?.first?["headers"] as? [String: String]
        XCTAssertEqual(header?["X-Shadespace-Token"], "new")
    }

    func testUninstallRestoresTheOriginalHooks() throws {
        try writeExisting()
        try ClaudeCodeHooksInstaller.install(token: "abc", at: url)
        try ClaudeCodeHooksInstaller.uninstall(at: url)

        let settings = try read()
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["PreToolUse", "UserPromptSubmit"])
        XCTAssertEqual((hooks["PreToolUse"] as? [[String: Any]])?.count, 1)
        XCTAssertFalse(ClaudeCodeHooksInstaller.isInstalled(at: url))
    }

    func testUninstallWithoutOurHooksLeavesTheFileAlone() throws {
        try writeExisting()
        let before = try Data(contentsOf: url)
        XCTAssertNil(try ClaudeCodeHooksInstaller.uninstall(at: url))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testInstallCreatesTheFileWhenMissing() throws {
        XCTAssertNil(try ClaudeCodeHooksInstaller.install(token: "abc", at: url))
        XCTAssertTrue(ClaudeCodeHooksInstaller.isInstalled(at: url))
    }
}

final class AgentEventTests: XCTestCase {
    private func event(_ object: [String: Any]) -> AgentEvent {
        var payload: [String: Any] = ["session_id": "s1", "cwd": "/Users/me/shadespace"]
        payload.merge(object) { $1 }
        return AgentEvent(json: try! JSONSerialization.data(withJSONObject: payload))!
    }

    func testEditStepCountsLines() {
        let edit = event(["hook_event_name": "PostToolUse", "tool_name": "Edit",
                          "tool_input": ["file_path": "/x/RootView.swift", "old_string": "a\nb\nc", "new_string": "a\nb\nc\nd\ne"]])
        XCTAssertEqual(edit.toolStep(withChanges: true), "Edit · RootView.swift +5 −3")
        XCTAssertEqual(edit.toolStep(withChanges: false), "Edit · RootView.swift")
        XCTAssertEqual(edit.projectName, "shadespace")
    }

    func testOtherToolSteps() {
        XCTAssertEqual(event(["hook_event_name": "PreToolUse", "tool_name": "Bash",
                              "tool_input": ["command": "npm test", "description": "Run tests"]]).toolStep(withChanges: false),
                       "Bash · Run tests")
        XCTAssertEqual(event(["hook_event_name": "PostToolUse", "tool_name": "Write",
                              "tool_input": ["file_path": "/a/b.md", "content": "1\n2\n"]]).toolStep(withChanges: true),
                       "Write · b.md +2")
        XCTAssertEqual(event(["hook_event_name": "PreToolUse", "tool_name": "mcp__github__create_issue"]).toolStep(withChanges: false),
                       "create_issue · github")
    }

    func testRejectsPayloadsWithoutSession() {
        XCTAssertNil(AgentEvent(json: Data(#"{"hook_event_name":"Stop"}"#.utf8)))
    }

    func testHTTPRequestNeedsTheWholeBody() {
        let body = #"{"a":1}"#
        let head = "POST /claude-code HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Shadespace-Token: t\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        XCTAssertNil(HTTPRequest(Data((head + "{\"a\"").utf8)))
        let request = HTTPRequest(Data((head + body).utf8))
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "/claude-code")
        XCTAssertEqual(request?.headers["x-shadespace-token"], "t")
        XCTAssertEqual(request.map { String(decoding: $0.body, as: UTF8.self) }, body)
    }
}

@MainActor
final class AgentSessionStoreTests: XCTestCase {
    private func send(_ store: AgentSessionStore, _ name: String, _ extra: [String: Any] = [:], at date: Date) {
        var payload: [String: Any] = ["session_id": "s1", "cwd": "/p/app", "hook_event_name": name]
        payload.merge(extra) { $1 }
        store.apply(AgentEvent(json: try! JSONSerialization.data(withJSONObject: payload))!, at: date)
    }

    func testLifecycle() {
        let store = AgentSessionStore(state: ShadespaceState(screen: NSScreen.screens[0]))
        let now = Date()
        send(store, "SessionStart", at: now)
        XCTAssertEqual(store.sessions.first?.status, .idle)
        XCTAssertTrue(store.visibleSessions.isEmpty)

        send(store, "PreToolUse", ["tool_name": "Read", "tool_input": ["file_path": "/p/app/a.swift"]], at: now)
        XCTAssertEqual(store.primarySession?.status, .working)
        XCTAssertEqual(store.primarySession?.step, "Read · a.swift")

        send(store, "PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "rm x"]], at: now)
        XCTAssertTrue(store.needsInput)
        XCTAssertEqual(store.primarySession?.botMood, .needsYou)

        send(store, "Stop", at: now)
        XCTAssertEqual(store.primarySession?.botMood, .celebrate)

        send(store, "SessionEnd", ["reason": "other"], at: now)
        XCTAssertTrue(store.sessions.isEmpty)
    }
}

@MainActor
final class AgentVisibilityTests: XCTestCase {
    func testQuietSessionsLeaveTheNotch() {
        let store = AgentSessionStore(state: ShadespaceState(screen: NSScreen.screens[0]))
        let payload = #"{"session_id":"q","hook_event_name":"PreToolUse","tool_name":"Bash"}"#
        store.apply(AgentEvent(json: Data(payload.utf8))!, at: Date().addingTimeInterval(-11 * 60))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertTrue(store.visibleSessions.isEmpty)
    }
}

final class BotLifeTests: XCTestCase {
    func testDriftsWithTimeAndRecoversWhileAsleep() {
        let start = Date()
        var life = BotLife(happiness: 0.5, energy: 0.5, updatedAt: start)
        life.advance(to: start.addingTimeInterval(10 * 3600), asleep: false)
        XCTAssertEqual(life.happiness, 0.2, accuracy: 0.001)
        XCTAssertEqual(life.energy, 0.1, accuracy: 0.001)
        XCTAssertTrue(life.isGloomy)
        XCTAssertTrue(life.isTired)

        life.advance(to: start.addingTimeInterval(13 * 3600), asleep: true)
        XCTAssertEqual(life.energy, 0.7, accuracy: 0.001)
    }

    func testNeverDropsToZeroAndCapsAtOne() {
        var life = BotLife(happiness: 0.1, energy: 0.1, updatedAt: Date())
        life.advance(to: Date().addingTimeInterval(1000 * 3600), asleep: false)
        XCTAssertGreaterThan(life.happiness, 0)
        XCTAssertGreaterThan(life.energy, 0)
        for _ in 0..<20 { life.record(.focusCompleted) }
        XCTAssertEqual(life.happiness, 1)
    }
}
