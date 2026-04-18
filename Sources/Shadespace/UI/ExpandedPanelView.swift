import SwiftUI

struct ExpandedPanelView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Now Playing")
                .foregroundStyle(.secondary)
            Text("Clipboard")
                .foregroundStyle(.secondary)
            Text("Stats & Focus")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
