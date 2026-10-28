import SwiftUI

/// Draws the companion bot on top of the island, at a point derived from the companion's
/// abstract position: beside the camera while collapsed, on the strip below the header
/// while expanded. Moves are animated, so it walks, crosses and ducks smoothly.
struct CompanionLayer: View {
    @EnvironmentObject var state: ShadespaceState
    @EnvironmentObject var modules: ModuleRegistry
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let companion = modules.companion
        let shown = settings.companionEnabled || state.agentsActive || state.pomodoroActive
        GeometryReader { geo in
            if shown {
                let point = position(in: geo.size, companion: companion)
                let size: CGFloat = state.isExpanded ? 22 : 30
                PixelBot(mood: companion.mood, focusColor: settings.botColor.color,
                         look: companion.look, walking: companion.walking)
                    .frame(width: size, height: size)
                    .position(point)
                    .animation(companion.walking
                               ? .linear(duration: companion.moveDuration)
                               : .spring(response: 0.45, dampingFraction: 0.78),
                               value: point)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    /// Canvas point for the bot's current perch.
    private func position(in canvas: CGSize, companion: BotCompanion) -> CGPoint {
        let screen = state.screen
        let hasNotch = NotchGeometry.hasNotch(screen)
        let notchW = hasNotch ? NotchGeometry.physicalNotchWidth(on: screen) : 0
        let centerX = canvas.width / 2

        if state.isExpanded {
            let width = NotchGeometry.expandedSize(on: screen).width
            let physH = NotchGeometry.physicalNotchHeight(on: screen)
            if hasNotch {
                // Stroll along the strip below the camera, leaving room for the vitals on the right
                let left = centerX - width / 2 + 26
                let usable = width - 52 - 70
                return CGPoint(x: left + usable * companion.stripPosition,
                               y: physH + NotchGeometry.liveStripHeight / 2)
            }
            // No camera housing: the header's middle is free
            let usable: CGFloat = 160
            return CGPoint(x: centerX - usable / 2 + usable * companion.stripPosition,
                           y: NotchGeometry.collapsedRect(on: screen).height / 2)
        }

        let ext = NotchGeometry.companionExtension(on: screen)
        let sign: CGFloat = companion.side == .left ? -1 : 1
        // Ducking moves it partway behind the camera housing
        let perch = notchW / 2 + ext / 2 - companion.peek * (ext / 2 + 4)
        return CGPoint(x: centerX + sign * perch, y: NotchGeometry.earsHeight(on: screen) / 2)
    }
}

/// Happiness and energy, shown next to the strolling bot in the expanded island.
struct CompanionVitals: View {
    let life: BotLife

    var body: some View {
        HStack(spacing: 8) {
            meter(symbol: "heart.fill", value: life.happiness, color: Color(red: 1, green: 0.4, blue: 0.55))
            meter(symbol: "bolt.fill", value: life.energy, color: Color(red: 1, green: 0.8, blue: 0.25))
        }
        .help("Mood \(Int(life.happiness * 100))% · Energy \(Int(life.energy * 100))%")
    }

    /// Five pixel-like segments.
    private func meter(symbol: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 8))
                .foregroundStyle(color)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    Rectangle()
                        .fill(Double(i) < (value * 5).rounded() ? color : .white.opacity(0.12))
                        .frame(width: 3, height: 6)
                }
            }
        }
    }
}
