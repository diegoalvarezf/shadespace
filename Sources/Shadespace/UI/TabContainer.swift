import SwiftUI

struct TabContainer: View {
    @EnvironmentObject var state: ShadespaceState
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                ForEach(ShadespaceTab.allCases) { tab in
                    moduleView(for: tab)
                        .frame(width: w)
                }
            }
            .offset(x: -CGFloat(ShadespaceTab.allCases.firstIndex(of: state.activeTab) ?? 0) * w)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.activeTab)
        }
        .clipped()
    }

    @ViewBuilder
    private func moduleView(for tab: ShadespaceTab) -> some View {
        switch tab {
        case .nowPlaying: NowPlayingView()
        case .clipboard:  ClipboardView()
        case .stats:      SystemStatsView()
        case .focus:      FocusView()
        case .ai:         AIView()
        }
    }
}
