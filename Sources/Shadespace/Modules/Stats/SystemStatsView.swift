import SwiftUI

struct SystemStatsView: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        VStack(spacing: 14) {
            StatRow(label: "CPU", value: modules.stats.stats.cpuPct, symbol: "cpu")
            StatRow(label: "RAM", value: modules.stats.stats.ramPct, symbol: "memorychip")
            if let bat = modules.stats.stats.batteryPct {
                StatRow(
                    label: modules.stats.stats.batteryCharging ? "Charging" : "Battery",
                    value: bat,
                    symbol: batterySymbol(bat)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private func batterySymbol(_ pct: Double) -> String {
        if modules.stats.stats.batteryCharging { return "battery.100.bolt" }
        if pct > 0.75 { return "battery.100" }
        if pct > 0.5  { return "battery.75" }
        if pct > 0.25 { return "battery.50" }
        return "battery.25"
    }
}

private struct StatRow: View {
    let label: String
    let value: Double
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(max(0, min(value, 1))))
                }
            }
            .frame(width: 100, height: 4)
            Text("\(Int(value * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var barColor: Color {
        value > 0.85 ? .red.opacity(0.8) : value > 0.65 ? .orange.opacity(0.8) : .white.opacity(0.75)
    }
}
