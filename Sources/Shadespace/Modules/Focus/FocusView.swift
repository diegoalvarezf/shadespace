import SwiftUI

struct FocusView: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        VStack(spacing: 16) {
            Button(action: { modules.focus.toggle() }) {
                VStack(spacing: 10) {
                    Image(systemName: modules.focus.isEnabled ? "moon.fill" : "moon")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(modules.focus.isEnabled ? .white : .white.opacity(0.4))
                        .symbolEffect(.bounce, value: modules.focus.isEnabled)
                    Text(modules.focus.isEnabled ? "Do Not Disturb" : "Focus Off")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(modules.focus.isEnabled ? .white : .white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(modules.focus.isEnabled ? 0.12 : 0.04))
                )
            }
            .buttonStyle(.plain)

            Text("Requires Shortcuts: \"Turn On/Off Do Not Disturb\"")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
    }
}
