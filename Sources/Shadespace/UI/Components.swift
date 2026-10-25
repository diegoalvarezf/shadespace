import SwiftUI

enum Palette {
    static let green = Color(red: 0.2, green: 0.85, blue: 0.45)
    static let answer = Color(red: 0.55, green: 0.85, blue: 1.0)

    static func battery(_ percent: Int) -> Color {
        if percent <= 20 { return .red }
        if percent <= 50 { return .yellow }
        return green
    }
}

// MARK: - Equalizer bars

struct EqualizerBars: View {
    let isActive: Bool
    var color: Color = .white.opacity(0.8)

    private let freqs: [Double] = [6.1, 5.3, 7.0]
    private let phases: [Double] = [0.0, 1.1, 2.2]

    var body: some View {
        // Paused bars don't need a timeline at all
        if isActive {
            TimelineView(.animation(minimumInterval: 0.08)) { ctx in
                bars(at: ctx.date.timeIntervalSinceReferenceDate)
            }
            .transition(.opacity)
        } else {
            bars(at: nil).opacity(0)
        }
    }

    private func bars(at t: Double?) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                let level = t.map { 0.5 + 0.5 * sin($0 * freqs[i] / 6 + phases[i]) } ?? 0
                Capsule().fill(color).frame(width: 2, height: 4 + 8 * CGFloat(level))
            }
        }
    }
}

// MARK: - Battery icon

struct BatteryIcon: View {
    let percent: Int
    var charging: Bool = false

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.8)
                    .frame(width: 16, height: 9)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(charging ? Palette.green : Palette.battery(percent))
                    .frame(width: max(2, 14 * CGFloat(percent) / 100), height: 7)
                    .padding(.leading, 1)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 16)
                }
            }
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(.white.opacity(0.45))
                .frame(width: 2, height: 4)
        }
    }
}

// MARK: - Progress bar

struct ThinProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(.white.opacity(0.65))
                    .frame(width: max(0, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: 2)
    }
}

// MARK: - Home (nothing playing)

/// Clock, date and weather when no music is playing.
struct HomeView: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .monospacedDigit()
                    Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer()

            if let w = modules.weather.weather {
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: w.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 20))
                        Text("\(Int(w.temperature.rounded()))\(w.unitSymbol)")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Text("\(w.summary) · H \(Int(w.high.rounded()))° L \(Int(w.low.rounded()))°")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 22)
        .overlay(alignment: .bottom) {
            Text("Nothing playing — open Spotify or Music")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.bottom, 12)
        }
    }
}
