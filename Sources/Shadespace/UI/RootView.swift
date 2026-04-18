import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: ShadespaceState

    var body: some View {
        ZStack(alignment: .top) {
            if state.isExpanded {
                VisualEffectBackground()
                    .clipShape(PanelShape(cornerRadius: 16))
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: state.collapsedRect.height)

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
}

private struct PanelShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height
        ), cornerRadius: cornerRadius)
    }
}
