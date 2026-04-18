import SwiftUI

struct NotchLiveIndicator: View {
    let isActive: Bool

    private let freqs: [Double] = [6.1, 5.3, 7.0]
    private let phases: [Double] = [0.0, 1.1, 2.2]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    bar(height: height(for: i, t: t))
                }
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: isActive)
    }

    private func height(for i: Int, t: TimeInterval) -> CGFloat {
        6 + 8 * CGFloat(0.5 + 0.5 * sin(t * freqs[i] / 6 + phases[i]))
    }

    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(.white.opacity(0.85))
            .frame(width: 2, height: height)
    }
}
