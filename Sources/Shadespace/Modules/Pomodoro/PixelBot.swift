import SwiftUI

/// The pixel robot from diegoalvarezf.dev, keeping the Pomodoro company: antenna, outlined
/// head with square eyes and a neck, on a 16×16 grid. Focused it blinks and hops now and then;
/// on a break it bounces with happy ^ ^ eyes; paused it dozes with flat eyes and a "z";
/// it jumps for joy when a focus session ends and cries when one is skipped.
struct PixelBot: View {
    enum Mood: Equatable {
        case focus, rest, paused, celebrate, sad
    }

    var mood: Mood
    /// Accent while focusing; breaks are green and pauses grey so the phase reads at a glance.
    var focusColor: Color = BotColor.cyan.color
    /// The expanded card can afford a slightly livelier timeline than the notch.
    var animated = false

    private static let grid = 16
    private static let screen = Color(red: 0.05, green: 0.04, blue: 0.12)

    var body: some View {
        TimelineView(.periodic(from: .now, by: animated ? 0.08 : 0.12)) { ctx in
            let sprite = Self.sprite(mood: mood, time: ctx.date.timeIntervalSinceReferenceDate)
            let accent = Self.accent(for: mood, focusColor: focusColor)
            Canvas(rendersAsynchronously: false) { context, size in
                // Half-point steps are whole device pixels on Retina, so the art stays crisp
                let cell = max(1, (min(size.width, size.height) / CGFloat(Self.grid) * 2).rounded(.down) / 2)
                let originX = ((size.width - cell * CGFloat(Self.grid)) / 2).rounded(.down)
                let originY = ((size.height - cell * CGFloat(Self.grid)) / 2).rounded(.down)
                for pixel in sprite {
                    let rect = CGRect(x: originX + CGFloat(pixel.x) * cell, y: originY + CGFloat(pixel.y) * cell,
                                      width: cell, height: cell)
                    let fill: Color
                    switch pixel.ink {
                    case .accent: fill = accent
                    case .dim:    fill = accent.opacity(0.4)
                    case .screen: fill = Self.screen
                    }
                    context.fill(Path(rect), with: .color(fill))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    static let restColor = Color(red: 0.45, green: 1, blue: 0.6)
    static let pausedColor = Color(white: 0.6)

    static func accent(for mood: Mood, focusColor: Color) -> Color {
        switch mood {
        case .focus, .celebrate, .sad: return focusColor
        case .rest:                    return restColor
        case .paused:                  return pausedColor
        }
    }

    // MARK: - Sprite

    private enum Ink { case accent, dim, screen }

    private struct Pixel {
        let x: Int
        let y: Int
        let ink: Ink
    }

    private static func sprite(mood: Mood, time t: Double) -> [Pixel] {
        let tick = Int(t * 8)
        var dy = 0

        switch mood {
        case .focus:
            // A short hop every ten seconds
            let loop = t.truncatingRemainder(dividingBy: 10)
            if loop >= 8.2 && loop < 8.8 { dy = tick % 2 == 0 ? -1 : 0 }
        case .rest:
            // Happy bounce
            dy = (tick / 3) % 2 == 0 ? 0 : -1
        case .celebrate:
            // Quick repeated jumps
            dy = tick % 2 == 0 ? -1 : 0
        case .paused, .sad:
            break
        }

        var pixels: [Pixel] = []
        func put(_ x: Int, _ y: Int, _ ink: Ink, moves: Bool = true) {
            // One row of headroom so a hop never clips the antenna
            let py = moves ? y + 1 + dy : y
            guard (0..<grid).contains(x), (0..<grid).contains(py) else { return }
            pixels.append(Pixel(x: x, y: py, ink: ink))
        }

        // Antenna
        for y in 0...2 { put(7, y, .accent); put(8, y, .accent) }

        // Head: dark screen with a one-pixel outline
        for y in 3...11 {
            for x in 2...13 {
                let edge = x == 2 || x == 13 || y == 3 || y == 11
                put(x, y, edge ? .accent : .screen)
            }
        }

        // Neck
        for y in 12...13 { for x in 6...9 { put(x, y, .dim) } }

        // Eyes
        switch mood {
        case .focus:
            // Blink for ~0.15 s roughly every 3.7 s
            let blink = t.truncatingRemainder(dividingBy: 3.7) < 0.15
            if !blink {
                for y in 6...8 { for x in [4, 5, 6, 9, 10, 11] { put(x, y, .accent) } }
            } else {
                for x in [4, 5, 6, 9, 10, 11] { put(x, 8, .accent) }
            }
        case .rest, .celebrate:
            for (x, y) in [(4, 7), (5, 6), (5, 7), (6, 7), (9, 7), (10, 6), (10, 7), (11, 7)] {
                put(x, y, .accent)
            }
        case .sad:
            for x in [4, 5, 6, 9, 10, 11] { put(x, 8, .accent) }
            // Falling tears, offset between the eyes
            put(5, 9 + tick % 2, .dim)
            put(10, 9 + (tick + 1) % 2, .dim)
        case .paused:
            for x in [4, 5, 6, 9, 10, 11] { put(x, 8, .accent) }
            if t.truncatingRemainder(dividingBy: 2) < 1.3 {
                for (x, y) in [(12, 0), (13, 0), (14, 0), (15, 0), (14, 1), (15, 1), (13, 2), (14, 2),
                               (12, 3), (13, 3), (14, 3), (15, 3)] {
                    put(x, y, .dim, moves: false)
                }
            }
        }
        return pixels
    }
}

/// Accent colors for the bot, chosen in the menu bar menu.
enum BotColor: String, CaseIterable {
    case cyan, blue, purple, pink, red, orange, yellow, white

    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var color: Color {
        switch self {
        case .cyan:   return Color(red: 0, green: 0.898, blue: 1)       // #00e5ff
        case .blue:   return Color(red: 0.25, green: 0.55, blue: 1)
        case .purple: return Color(red: 0.7, green: 0.5, blue: 1)
        case .pink:   return Color(red: 1, green: 0.235, blue: 0.557)   // #ff3c8e
        case .red:    return Color(red: 1, green: 0.3, blue: 0.27)
        case .orange: return Color(red: 1, green: 0.6, blue: 0.2)
        case .yellow: return Color(red: 1, green: 0.84, blue: 0.2)
        case .white:  return Color(white: 0.92)
        }
    }
}
