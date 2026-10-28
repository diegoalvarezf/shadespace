import Foundation

/// Adds and removes Shadespace's "http" hooks in Claude Code's user settings
/// (~/.claude/settings.json). Existing hooks and settings are kept: entries are merged, the file
/// is backed up before every write, and removal only touches handlers pointing at Shadespace.
enum ClaudeCodeHooksInstaller {
    /// Events the notch listens to. PermissionRequest is observed only; it never decides here.
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd",
    ]

    /// Seconds Claude Code waits for the app; it answers immediately, so keep this short.
    static let timeout = 5

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    enum InstallerError: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let reason): return "~/.claude/settings.json couldn't be read: \(reason)"
            }
        }
    }

    // MARK: - Status

    static func isInstalled(at url: URL = settingsURL) -> Bool {
        guard let settings = try? readSettings(at: url),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { groupContainsShadespace($0) }
        }
    }

    // MARK: - Install / uninstall

    /// Returns the backup path, or nil when there was no settings file yet.
    @discardableResult
    static func install(token: String, at url: URL = settingsURL) throws -> URL? {
        var settings = try readSettings(at: url) ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            // Drop an older Shadespace entry (e.g. with a previous token), keep everything else
            groups = removingShadespace(from: groups)
            groups.append(["hooks": [handler(token: token)]])
            hooks[event] = groups
        }

        settings["hooks"] = hooks
        return try write(settings, to: url)
    }

    @discardableResult
    static func uninstall(at url: URL = settingsURL) throws -> URL? {
        guard var settings = try readSettings(at: url),
              var hooks = settings["hooks"] as? [String: Any] else { return nil }

        var changed = false
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]], groups.contains(where: groupContainsShadespace) else { continue }
            let remaining = removingShadespace(from: groups)
            hooks[event] = remaining.isEmpty ? nil : remaining
            changed = true
        }
        // Nothing of ours in the file: leave it untouched, no backup
        guard changed else { return nil }

        if hooks.isEmpty {
            settings["hooks"] = nil
        } else {
            settings["hooks"] = hooks
        }
        return try write(settings, to: url)
    }

    // MARK: - Private

    static func handler(token: String) -> [String: Any] {
        [
            "type": "http",
            "url": AgentHookServer.url,
            "headers": ["X-Shadespace-Token": token],
            "timeout": timeout,
        ]
    }

    private static func isShadespaceHandler(_ handler: [String: Any]) -> Bool {
        (handler["url"] as? String)?.hasPrefix(AgentHookServer.url) == true
    }

    private static func groupContainsShadespace(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains(where: isShadespaceHandler)
    }

    /// Removes Shadespace handlers; a group left without handlers is removed too.
    private static func removingShadespace(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
            let kept = handlers.filter { !isShadespaceHandler($0) }
            if kept.count == handlers.count { return group }
            if kept.isEmpty { return nil }
            var updated = group
            updated["hooks"] = kept
            return updated
        }
    }

    private static func readSettings(at url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.unreadable("it isn't a JSON object")
        }
        return object
    }

    /// Backs up the current file next to it, then replaces it atomically keeping its permissions.
    private static func write(_ settings: [String: Any], to url: URL) throws -> URL? {
        let fileManager = FileManager.default
        var backup: URL?
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]

        if fileManager.fileExists(atPath: url.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let directory = url.deletingLastPathComponent()
            var backupURL = directory.appendingPathComponent("settings.json.shadespace-backup-\(stamp)")
            // Two writes within the same second (connect, then disconnect) must not collide
            var suffix = 2
            while fileManager.fileExists(atPath: backupURL.path) {
                backupURL = directory.appendingPathComponent("settings.json.shadespace-backup-\(stamp)-\(suffix)")
                suffix += 1
            }
            try fileManager.copyItem(at: url, to: backupURL)
            backup = backupURL
            if let permissions = try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] {
                attributes[.posixPermissions] = permissions
            }
        } else {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        return backup
    }
}
