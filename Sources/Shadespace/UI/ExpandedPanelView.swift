import SwiftUI

struct ExpandedPanelView: View {
    var body: some View {
        VStack(spacing: 10) {
            NowPlayingView()
            Text("Clipboard — próximamente")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            Text("Stats & Focus — próximamente")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
