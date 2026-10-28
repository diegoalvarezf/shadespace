import Foundation

/// One Claude Code hook invocation, decoded from the JSON body Claude Code POSTs to the app.
/// Fields follow the hooks reference (code.claude.com/docs/en/hooks); everything except the
/// session and event name is optional because each event carries a different subset.
struct AgentEvent {
    let name: String
    let sessionID: String
    let cwd: String?
    let toolName: String?
    let toolInput: [String: Any]
    let notificationType: String?
    let message: String?
    let error: String?
    /// The original payload, kept for events that need more than the fields above.
    let raw: [String: Any]

    init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String else { return nil }
        self.name = name
        self.sessionID = sessionID
        cwd = object["cwd"] as? String
        toolName = object["tool_name"] as? String
        toolInput = object["tool_input"] as? [String: Any] ?? [:]
        notificationType = object["notification_type"] as? String
        message = object["message"] as? String
        error = object["error"] as? String
        raw = object
    }

    /// Folder name of the session's working directory, used as the session's label.
    var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "Claude Code" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    // MARK: - Step descriptions

    /// Short line describing a tool call, e.g. "Edit · RootView.swift +12 −3".
    /// Line counts are only added once the tool has run (`withChanges`).
    func toolStep(withChanges: Bool) -> String {
        guard let tool = toolName else { return "Working" }
        let input = toolInput

        func file(_ key: String = "file_path") -> String? {
            (input[key] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        }

        switch tool {
        case "Edit":
            let target = file() ?? "file"
            guard withChanges else { return "Edit · \(target)" }
            let added = Self.lineCount(input["new_string"] as? String)
            let removed = Self.lineCount(input["old_string"] as? String)
            return "Edit · \(target) +\(added) −\(removed)"
        case "MultiEdit":
            let target = file() ?? "file"
            guard withChanges, let edits = input["edits"] as? [[String: Any]] else { return "Edit · \(target)" }
            let added = edits.reduce(0) { $0 + Self.lineCount($1["new_string"] as? String) }
            let removed = edits.reduce(0) { $0 + Self.lineCount($1["old_string"] as? String) }
            return "Edit · \(target) +\(added) −\(removed)"
        case "Write":
            let target = file() ?? "file"
            guard withChanges else { return "Write · \(target)" }
            return "Write · \(target) +\(Self.lineCount(input["content"] as? String))"
        case "Read":
            return "Read · \(file() ?? "file")"
        case "NotebookEdit":
            return "Edit · \(file("notebook_path") ?? "notebook")"
        case "Bash":
            let summary = (input["description"] as? String) ?? (input["command"] as? String) ?? ""
            return summary.isEmpty ? "Bash" : "Bash · \(Self.truncate(summary))"
        case "Grep", "Glob":
            let pattern = input["pattern"] as? String ?? ""
            return pattern.isEmpty ? tool : "\(tool) · \(Self.truncate(pattern))"
        case "WebFetch":
            let host = (input["url"] as? String).flatMap { URL(string: $0)?.host } ?? ""
            return host.isEmpty ? "WebFetch" : "WebFetch · \(host)"
        case "WebSearch":
            return "Search · \(Self.truncate(input["query"] as? String ?? ""))"
        case "Agent", "Task":
            let description = input["description"] as? String ?? ""
            return description.isEmpty ? "Agent" : "Agent · \(Self.truncate(description))"
        case "AskUserQuestion":
            return "Has a question for you"
        default:
            // MCP tools arrive as mcp__<server>__<tool>
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                if parts.count >= 3 { return "\(parts.dropFirst(2).joined(separator: "_")) · \(parts[1])" }
            }
            return tool
        }
    }

    static func lineCount(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        // A trailing newline doesn't start another line
        return text.hasSuffix("\n") ? lines - 1 : lines
    }

    private static func truncate(_ text: String, to length: Int = 40) -> String {
        let single = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return single.count > length ? String(single.prefix(length - 1)) + "…" : single
    }
}
