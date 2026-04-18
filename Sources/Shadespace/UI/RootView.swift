import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: ShadespaceState

    var body: some View {
        ZStack(alignment: .top) {
            if state.isExpanded {
                VisualEffectBackground()
                    .overlay(Color.black.opacity(0.45))
                    .clipShape(PanelShape(cornerRadius: 18))
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                notchRow
                if state.isExpanded {
                    ExpandedPanelView()
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                        ))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: state.isExpanded)
    }

    private var notchRow: some View {
        ZStack(alignment: .trailing) {
            Color.black
            NotchLiveIndicator(isActive: state.nowPlayingIsActive && !state.isExpanded)
                .padding(.trailing, 10)
        }
        .frame(height: state.collapsedRect.height)
    }
}

private struct PanelShape: Shape {
    var cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius)
    }
}
