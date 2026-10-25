import SwiftUI

struct PomodoroView: View {
    @EnvironmentObject var modules: ModuleRegistry
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let timer = modules.pomodoro
        HStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: timer.progress(at: ctx.date))
                        .stroke(color(for: timer.phase), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timer.progress(at: ctx.date))
                    VStack(spacing: 2) {
                        PixelBot(mood: timer.isActive ? timer.mood : .focus, focusColor: settings.botColor.color,
                                 animated: timer.isRunning)
                            .frame(width: 42, height: 42)
                        Text(Self.format(timer.remaining(at: ctx.date)))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(timer.phase.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    SessionDots(completed: timer.completedFocusSessions)
                }

                if timer.phase == .focus && !timer.isActive {
                    HStack(spacing: 4) {
                        ForEach(PomodoroTimer.focusPresets, id: \.self) { minutes in
                            presetButton(minutes)
                        }
                    }
                } else {
                    Text(timer.isRunning ? "Running" : (timer.isActive ? "Paused" : "Ready"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(height: 20)
                }

                HStack(spacing: 8) {
                    Button(action: timer.startOrPause) {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    iconButton("forward.end.fill", help: "Skip to next phase", action: timer.skip)
                    iconButton("arrow.counterclockwise", help: "Reset", action: timer.reset)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presetButton(_ minutes: Int) -> some View {
        let selected = modules.pomodoro.focusMinutes == minutes
        return Button { modules.pomodoro.focusMinutes = minutes } label: {
            Text("\(minutes)m")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(selected ? 0.9 : 0.4))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(.white.opacity(selected ? 0.14 : 0.05)))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func color(for phase: PomodoroPhase) -> Color {
        PixelBot.accent(for: phase == .focus ? .focus : .rest, focusColor: settings.botColor.color)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// One dot per focus session in the current cycle of four.
private struct SessionDots: View {
    let completed: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<PomodoroTimer.sessionsPerCycle, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index < completed ? 0.8 : 0.15))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
