import SwiftUI

struct TabBar: View {
    @EnvironmentObject var state: ShadespaceState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ShadespaceTab.allCases) { tab in
                TabBarButton(tab: tab, isActive: state.activeTab == tab) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        state.setTab(tab)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct TabBarButton: View {
    let tab: ShadespaceTab
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 26)
                .foregroundStyle(isActive ? .white : .white.opacity(0.4))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(isActive ? 0.14 : 0))
                )
        }
        .buttonStyle(.plain)
    }
}
