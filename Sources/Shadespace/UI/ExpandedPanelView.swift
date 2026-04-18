import SwiftUI

struct ExpandedPanelView: View {
    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            Divider().overlay(.white.opacity(0.08))
            TabContainer()
                .frame(maxHeight: .infinity)
        }
    }
}
