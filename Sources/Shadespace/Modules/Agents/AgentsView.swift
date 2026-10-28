import AppKit
import SwiftUI

/// Expanded-card page listing Claude Code sessions and their latest step.
struct AgentsView: View {
    @EnvironmentObject var modules: ModuleRegistry
    @EnvironmentObject var settings: AppSettings
    @State private var isConnected = ClaudeCodeHooksInstaller.isInstalled()

    var body: some View {
        let sessions = modules.agents.sessions
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                Text("Agents")
                    .font(.system(size: 11, weight: .semibold))
                if !sessions.isEmpty {
                    Text("\(sessions.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .opacity(0.6)
                }
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if let error = modules.agents.serverError {
                placeholder(symbol: "exclamationmark.triangle", text: error)
            } else if !isConnected {
                VStack(spacing: 8) {
                    placeholder(symbol: "link", text: "See your Claude Code sessions here")
                    Button("Connect Claude Code") {
                        isConnected = ClaudeCodeConnection.connect()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Capsule().fill(.white.opacity(0.12)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                placeholder(symbol: "moon.zzz", text: "No sessions yet — start Claude Code in a terminal")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(sessions) { session in
                            AgentRow(session: session, color: settings.botColor.color)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isConnected = ClaudeCodeHooksInstaller.isInstalled() }
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
            Text(text)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.3))
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgentRow: View {
    let session: AgentSession
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            PixelBot(mood: session.botMood, focusColor: color)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(statusText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(statusColor)
                    Spacer()
                    Text(session.updatedAt, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                        .monospacedDigit()
                }
                Text(session.step)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
    }

    private var statusText: String {
        switch session.status {
        case .idle:       return "Idle"
        case .working:    return "Working"
        case .needsInput: return "Needs you"
        case .finished:   return "Done"
        case .failed:     return "Error"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .needsInput: return PixelBot.alertColor
        case .failed:     return .red
        case .finished:   return Palette.green
        default:          return .white.opacity(0.4)
        }
    }
}

/// Connect / disconnect actions shared by the menu bar menu and the Agents page.
@MainActor
enum ClaudeCodeConnection {
    /// Returns whether the hooks are installed afterwards.
    @discardableResult
    static func connect() -> Bool {
        do {
            let backup = try ClaudeCodeHooksInstaller.install(token: AgentSessionStore.hookToken)
            inform("Claude Code connected",
                   "Shadespace added its hooks to ~/.claude/settings.json and kept your existing ones."
                   + (backup.map { "\n\nBackup: \($0.path)" } ?? "")
                   + "\n\nSessions already open pick them up after restarting Claude Code.")
        } catch {
            inform("Couldn't connect Claude Code", error.localizedDescription, style: .warning)
        }
        return ClaudeCodeHooksInstaller.isInstalled()
    }

    static func disconnect() {
        do {
            let backup = try ClaudeCodeHooksInstaller.uninstall()
            inform("Claude Code disconnected",
                   "Shadespace removed only its own hooks from ~/.claude/settings.json."
                   + (backup.map { "\n\nBackup: \($0.path)" } ?? ""))
        } catch {
            inform("Couldn't disconnect Claude Code", error.localizedDescription, style: .warning)
        }
    }

    private static func inform(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        alert.runModal()
    }
}
