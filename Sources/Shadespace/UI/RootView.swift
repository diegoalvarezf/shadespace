import SwiftUI

/// Fills the fixed, transparent panel and draws the island at the top-center.
/// The panel never resizes; the island's size animates here.
struct RootView: View {
    @EnvironmentObject var state: ShadespaceState
    @EnvironmentObject var modules: ModuleRegistry
    @EnvironmentObject var settings: AppSettings
    @State private var contentScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        let size = state.islandSize
        let expandProgress: CGFloat = state.isExpanded ? 1 : 0
        let hoverProgress: CGFloat = state.isHovering && !state.isExpanded ? 1 : 0
        let shape = IslandShape(expandProgress: expandProgress, hoverProgress: hoverProgress)

        return VStack(spacing: 0) {
            if state.isExpanded {
                ExpandedHeader()
            } else {
                if settings.showLiveActivity {
                    CollapsedNotchRow()
                } else if state.agentsActive || state.pomodoroActive {
                    ActivityEars()
                        .frame(height: NotchGeometry.earsHeight(on: state.screen))
                    if state.agentsActive && state.alert == nil {
                        AgentStepLine()
                            .frame(height: NotchGeometry.liveStripHeight)
                            .transition(.opacity)
                    }
                } else {
                    // Hidden: only the notch-sized black area, invisible against the hardware
                    Color.clear.frame(height: state.alert == nil ? state.islandSize.height : state.peekHeaderHeight)
                }
                if let alert = state.alert {
                    AlertRow(alert: alert)
                        .frame(height: NotchGeometry.peekContentHeight)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            if state.isExpanded {
                contentCard
                    .frame(height: NotchGeometry.expandedContentHeight)
                    .scaleEffect(contentScale)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.88, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
                    ))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .contentShape(shape)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: size)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: state.isExpanded)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: state.isHovering)
        .animation(.easeInOut(duration: 0.2), value: state.isDragging)
        // Micro-bounce when the content switches while already expanded
        .onChange(of: state.mode) { _, _ in
            guard state.isExpanded else { return }
            contentScale = 0.95
            withAnimation(.spring(response: 0.38, dampingFraction: 0.5)) {
                contentScale = 1.0
            }
        }
    }

    // MARK: - Expanded content

    @ViewBuilder
    private var contentCard: some View {
        if state.isDragging {
            DropZonesView()
        } else {
            switch state.mode {
            case .idle:
                switch state.page {
                case .nowPlaying: NowPlayingView()
                case .pomodoro:   PomodoroView()
                case .agents:     AgentsView()
                case .tray:       FileTrayView()
                }
            case .aiReading(let progress):
                AIReadingView(progress: progress)
            case .aiSummary(let text):
                AIExpandedView(summary: text)
            case .fileConverting:
                VStack(spacing: 10) {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.8).colorScheme(.dark)
                    Text("Converting file…")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .fileConversionDone(let url):
                ConversionResultView(url: url)
            case .fileConversionError:
                ConversionErrorView()
            }
        }
    }
}

// MARK: - Collapsed notch row

/// Black row that blends with the physical notch. Content flanks the camera housing,
/// and a thin live strip below it shows the current activity.
private struct CollapsedNotchRow: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: ShadespaceState
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        let physH = NotchGeometry.physicalNotchHeight(on: state.screen)
        let extL = NotchGeometry.leftExtension(on: state.screen)
        let extR = NotchGeometry.rightExtension(on: state.screen)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack {
                    if state.pomodoroActive {
                        PixelBot(mood: modules.pomodoro.mood, focusColor: settings.botColor.color).frame(width: 30, height: 30)
                    } else if state.mode == .idle, let img = modules.nowPlaying.artwork {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .opacity(state.nowPlayingIsActive ? 1.0 : 0.45)
                            .animation(.easeInOut(duration: 0.25), value: state.nowPlayingIsActive)
                    }
                }
                .frame(width: extL)

                Spacer() // physical notch camera — no visible pixels

                ZStack {
                    if state.pomodoroActive {
                        PomodoroCountdown()
                    } else if state.mode == .idle {
                        EqualizerBars(isActive: state.nowPlayingIsActive, color: .white.opacity(0.85))
                    }
                }
                .frame(width: extR)
            }
            .frame(height: physH)

            CollapsedLiveContent()
                .frame(maxWidth: .infinity)
                .frame(height: NotchGeometry.liveStripHeight)
                .padding(.horizontal, min(extL, extR))
        }
        .frame(height: NotchGeometry.collapsedRect(on: state.screen).height, alignment: .top)
    }
}

/// Running Pomodoro while the island is otherwise hidden: the bot on the left of the
/// camera, the countdown on the right.
/// Bot on the left of the camera, countdown (or agent count) on the right. Shown while a coding
/// agent or a Pomodoro is active and the island is otherwise hidden. Agents take the bot when
/// both run, since they are the ones that may need you.
private struct ActivityEars: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: ShadespaceState
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        let notchW = NotchGeometry.hasNotch(state.screen) ? NotchGeometry.physicalNotchWidth(on: state.screen) : 0
        let agent = state.agentsActive ? modules.agents.primarySession : nil
        HStack(spacing: 0) {
            PixelBot(mood: agent?.botMood ?? modules.pomodoro.mood, focusColor: settings.botColor.color)
                .frame(width: 30, height: 30)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: notchW)
            Group {
                if state.pomodoroActive {
                    PomodoroCountdown()
                } else if modules.agents.visibleSessions.count > 1 {
                    Text("×\(modules.agents.visibleSessions.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(settings.botColor.color)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .transition(.opacity)
    }
}

/// What the main agent session is doing right now, below the notch.
private struct AgentStepLine: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        if let session = modules.agents.primarySession {
            Text(session.step)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(session.status == .needsInput ? PixelBot.alertColor : .white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 16)
                .id(session.step)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: session.step)
        }
    }
}

private struct PomodoroCountdown: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        let timer = modules.pomodoro
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 3) {
                if !timer.isRunning {
                    Image(systemName: "pause.fill").font(.system(size: 7, weight: .bold))
                }
                Text(PomodoroView.format(timer.remaining(at: ctx.date)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(PixelBot.accent(for: timer.phase == .focus ? .focus : .rest,
                                             focusColor: settings.botColor.color))
            .opacity(timer.isRunning ? 1 : 0.55)
        }
    }
}

private struct CollapsedLiveContent: View {
    @EnvironmentObject var state: ShadespaceState
    @EnvironmentObject var modules: ModuleRegistry
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        switch state.mode {
        case .idle:
            if let track = modules.nowPlaying.track {
                if settings.lyricsInNotch, let lyrics = modules.nowPlaying.lyrics, !lyrics.isEmpty {
                    TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                        let position = track.position(at: ctx.date, since: modules.nowPlaying.snapshotDate)
                        let line = lyrics.line(at: position)?.text ?? ""
                        stripText(line.isEmpty ? "\(track.title) · \(track.artist)" : line, active: track.isPlaying)
                            .id(line)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: line)
                    }
                } else {
                    stripText("\(track.title) · \(track.artist)", active: track.isPlaying)
                }
            }
        case .aiReading(let progress):
            VStack(spacing: 3) {
                Text("Reading document…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                ThinProgressBar(progress: progress)
                    .padding(.horizontal, 20)
            }
        case .aiSummary:
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Summary ready").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        case .fileConverting:
            HStack(spacing: 6) {
                ProgressView().progressViewStyle(.circular).scaleEffect(0.5)
                    .frame(width: 14, height: 14).colorScheme(.dark)
                Text("Converting…").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
        case .fileConversionDone:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                    .foregroundStyle(Palette.green)
                Text("Done").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        case .fileConversionError:
            Text("Conversion failed").font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func stripText(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(active ? 0.80 : 0.40))
            .lineLimit(1)
            .truncationMode(.tail)
            .animation(.easeInOut(duration: 0.2), value: active)
    }
}

// MARK: - Expanded header

/// Uses the space beside the camera housing: page switcher on the left, weather and battery on the right.
private struct ExpandedHeader: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: ShadespaceState
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        let collapsedHeight = NotchGeometry.collapsedRect(on: state.screen).height
        let physH = NotchGeometry.physicalNotchHeight(on: state.screen)
        let notchW = NotchGeometry.hasNotch(state.screen) ? NotchGeometry.physicalNotchWidth(on: state.screen) : 0

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Four pages must fit beside the camera housing, so keep these tight
                HStack(spacing: 2) {
                    pageButton(.nowPlaying, symbol: "music.note")
                    pageButton(.pomodoro, symbol: "timer", indicator: modules.pomodoro.isRunning)
                    pageButton(.agents, symbol: "terminal", indicator: modules.agents.needsInput)
                    pageButton(.tray, symbol: "tray.full", badge: modules.tray.items.count)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)

                Color.clear.frame(width: notchW)

                StatusSummary()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 14)
            }
            .frame(height: physH > 0 ? physH : collapsedHeight)
            Spacer(minLength: 0)
        }
        .frame(height: collapsedHeight)
    }

    private func pageButton(_ page: IslandPage, symbol: String, badge: Int = 0, indicator: Bool = false) -> some View {
        let selected = state.mode == .idle && state.page == page
        return Button {
            if state.mode != .idle { return }
            state.page = page
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                if indicator {
                    Circle().fill(settings.botColor.color).frame(width: 4, height: 4)
                }
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(.white.opacity(selected ? 0.9 : 0.35))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(.white.opacity(selected ? 0.12 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Weather and battery at a glance, shown in the expanded header.
private struct StatusSummary: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        StatusSummaryContent(weather: modules.weather, battery: modules.battery)
    }
}

private struct StatusSummaryContent: View {
    @ObservedObject var weather: WeatherService
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        HStack(spacing: 6) {
            if let w = weather.weather {
                HStack(spacing: 3) {
                    Image(systemName: w.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 10))
                    Text("\(Int(w.temperature.rounded()))°")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            if battery.hasBattery {
                HStack(spacing: 3) {
                    BatteryIcon(percent: battery.batteryPercent, charging: battery.isOnAC)
                    Text("\(battery.batteryPercent)%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        // The space beside the notch is narrow: keep everything on one line
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(.white.opacity(0.6))
    }
}

// MARK: - Alerts (peek)

private struct AlertRow: View {
    let alert: IslandAlert
    @EnvironmentObject var settings: AppSettings

    private var botColor: Color { settings.botColor.color }

    var body: some View {
        HStack(spacing: 8) {
            switch alert {
            case .charging(let percent):
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                Text("Charging").fontWeight(.semibold)
                Spacer()
                BatteryIcon(percent: percent, charging: true)
                Text("\(percent)%").monospacedDigit()
            case .batteryLow(let percent):
                Image(systemName: "battery.25percent").foregroundStyle(.red)
                Text("Low battery").fontWeight(.semibold)
                Spacer()
                Text("\(percent)%").monospacedDigit().foregroundStyle(.red)
            case .batteryFull:
                Image(systemName: "battery.100percent.bolt").foregroundStyle(Palette.green)
                Text("Fully charged").fontWeight(.semibold)
                Spacer()
                Text("100%").monospacedDigit()
            case .airPods(let status):
                Image(systemName: status.symbol)
                Text(status.name).fontWeight(.semibold).lineLimit(1)
                Spacer()
                AirPodsBatteryText(status: status)
            case .trayAdded(let count):
                Image(systemName: "tray.and.arrow.down.fill")
                Text(count == 1 ? "Added to Tray" : "\(count) files added to Tray").fontWeight(.semibold)
                Spacer()
            case .pomodoro(let finished, let next):
                PixelBot(mood: finished == .focus ? .celebrate : .focus, focusColor: botColor)
                    .frame(width: 26, height: 26)
                Text(finished == .focus ? "Focus done!" : "Break over").fontWeight(.semibold)
                Spacer()
                Text("Next: \(next.title)").foregroundStyle(.white.opacity(0.5))
            case .pomodoroSkipped:
                PixelBot(mood: .sad, focusColor: botColor)
                    .frame(width: 26, height: 26)
                Text("Focus skipped").fontWeight(.semibold)
                Spacer()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 16)
    }
}

private struct AirPodsBatteryText: View {
    let status: AirPodsStatus

    var body: some View {
        HStack(spacing: 8) {
            if let single = status.single, status.left == nil, status.right == nil {
                Text("\(single)%")
            }
            if let left = status.left { Text("L \(left)%") }
            if let right = status.right { Text("R \(right)%") }
            if let caseLevel = status.caseLevel {
                HStack(spacing: 2) {
                    Image(systemName: "case")
                    Text("\(caseLevel)%")
                }
            }
            if !status.hasBattery {
                Text("Connected").foregroundStyle(.white.opacity(0.5))
            }
        }
        .monospacedDigit()
        .font(.system(size: 10, weight: .medium))
    }
}

// MARK: - Drag & drop

/// Three side-by-side targets shown while a file is dragged over the island.
private struct DropZonesView: View {
    @EnvironmentObject var state: ShadespaceState

    var body: some View {
        HStack(spacing: 8) {
            zone(.summarize, symbol: "sparkles", title: "Summarize", subtitle: "PDF, text")
            zone(.convert, symbol: "arrow.triangle.2.circlepath", title: "Convert", subtitle: "PNG ↔ JPG")
            zone(.airDrop, symbol: "dot.radiowaves.left.and.right", title: "AirDrop", subtitle: "Send nearby")
            zone(.tray, symbol: "tray.and.arrow.down", title: "Tray", subtitle: "Keep for later")
        }
        .padding(12)
    }

    private func zone(_ zone: DropZone, symbol: String, title: String, subtitle: String) -> some View {
        let hovered = state.hoveredDropZone == zone
        let supported = state.supportedDropZones.contains(zone)
        return VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 9))
                .opacity(0.6)
        }
        .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.45))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(hovered ? 0.12 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(hovered ? 0.4 : 0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .scaleEffect(hovered && supported ? 1.03 : 1)
        // Zones that can't take the dragged file are dimmed; dropping there sends it to the tray
        .opacity(supported ? 1 : 0.35)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
    }
}

// MARK: - AI

private struct AIReadingView: View {
    let progress: Double
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .symbolEffect(.pulse)
            Text(modules.ai.documentName.map { "Reading \($0)…" } ?? "Summarizing…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
            ThinProgressBar(progress: progress)
                .frame(width: 160)
                .animation(.easeOut(duration: 0.3), value: progress)
            Button("Cancel") { modules.ai.reset() }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AIExpandedView: View {
    let summary: String
    @EnvironmentObject var modules: ModuleRegistry
    @State private var question: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text(modules.ai.documentName ?? "Summary")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: copySummary) {
                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Copy summary")
                Button("Clear") { modules.ai.reset() }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if let reason = modules.ai.unavailableReason {
                        Label(reason, systemImage: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow.opacity(0.7))
                    }
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    if modules.ai.isAnswering {
                        HStack(spacing: 6) {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.5)
                                .frame(width: 14, height: 14).colorScheme(.dark)
                            Text("Thinking…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.top, 4)
                    } else if let answer = modules.ai.chatAnswer {
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                        Text(answer)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.answer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }

            if modules.ai.unavailableReason == nil {
                questionField
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var questionField: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
            TextField("Ask about this document…", text: $question)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .focused($inputFocused)
                .onSubmit { submitQuestion() }
            Button(action: submitQuestion) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        question.isEmpty || modules.ai.isAnswering
                            ? AnyShapeStyle(.white.opacity(0.18))
                            : AnyShapeStyle(.white.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            .disabled(question.isEmpty || modules.ai.isAnswering)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    private func submitQuestion() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        modules.ai.askQuestion(q)
        question = ""
        inputFocused = false
    }
}

// MARK: - File conversion results

private struct ConversionResultView: View {
    let url: URL
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Palette.green)
            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                pill("Show in Finder", symbol: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    modules.fileConverter.reset()
                }
                pill("Add to Tray", symbol: "tray.and.arrow.down") {
                    modules.tray.add([url])
                    modules.fileConverter.reset()
                }
                pill("Done", symbol: "xmark") {
                    modules.fileConverter.reset()
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Draggable straight from the result into another app
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    }

    private func pill(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

private struct ConversionErrorView: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.45))
            Text("This image couldn't be converted")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            Button("Dismiss") { modules.fileConverter.reset() }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Island shape (morphs collapsed ↔ expanded)

private struct IslandShape: Shape {
    var expandProgress: CGFloat  // 0 = collapsed, 1 = expanded
    var hoverProgress: CGFloat   // 0 = idle, 1 = hovering (not yet expanded)

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(expandProgress, hoverProgress) }
        set { expandProgress = newValue.first; hoverProgress = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let p = expandProgress
        // collapsed: topR=0 (flush with notch hardware), botR=14
        // expanded:  topR=10, botR=20
        // hover pre-expand: slightly increase botR to hint at upcoming expand
        // Clamp radii so a notch-sized (hidden) island never gets overlapping arcs
        let maxR = max(0, min(rect.width, rect.height) / 2)
        let topR = min(max(0.0, 10.0 * p), maxR)
        let botR = min(max(2.0, 14.0 + 6.0 * p + 3.0 * hoverProgress * (1.0 - p)), maxR)
        // Organic "neck": side edges bow inward slightly at mid-transition (sin peaks at p=0.5)
        let neck = sin(p * .pi) * 4.0

        let edgeH = max(0, rect.height - topR - botR)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))

        if topR > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topR, y: rect.minY + topR),
                radius: topR, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
            )
        }

        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - botR),
            control1: CGPoint(x: rect.maxX - neck, y: rect.minY + topR + edgeH * 0.3),
            control2: CGPoint(x: rect.maxX - neck, y: rect.maxY - botR - edgeH * 0.3)
        )

        path.addArc(
            center: CGPoint(x: rect.maxX - botR, y: rect.maxY - botR),
            radius: botR, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.minX + botR, y: rect.maxY))

        path.addArc(
            center: CGPoint(x: rect.minX + botR, y: rect.maxY - botR),
            radius: botR, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )

        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + topR),
            control1: CGPoint(x: rect.minX + neck, y: rect.maxY - botR - edgeH * 0.3),
            control2: CGPoint(x: rect.minX + neck, y: rect.minY + topR + edgeH * 0.3)
        )

        if topR > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
                radius: topR, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
            )
        }

        path.closeSubpath()
        return path
    }
}
