import SwiftUI

struct AIView: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        VStack(spacing: 0) {
            if !modules.ai.isAvailable {
                unavailableOverlay
            } else {
                chatHistory
                inputBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatHistory: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(modules.ai.history) { turn in
                        MessageBubble(turn: turn)
                    }
                }
                .padding(12)
            }
            .onChange(of: modules.ai.history.count) { _, _ in
                if let last = modules.ai.history.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask anything…", text: Binding(
                get: { modules.ai.prompt },
                set: { modules.ai.prompt = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .onSubmit { modules.ai.send() }

            Button(action: { modules.ai.send() }) {
                Image(systemName: modules.ai.isGenerating ? "stop.circle" : "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(modules.ai.prompt.isEmpty ? .white.opacity(0.3) : .white)
            }
            .buttonStyle(.plain)
            .disabled(modules.ai.prompt.isEmpty && !modules.ai.isGenerating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06))
    }

    private var unavailableOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
            Text("Apple Intelligence").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Text("Not available on this system").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MessageBubble: View {
    let turn: AIModuleStore.Turn

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }
            Text(turn.text.isEmpty ? "…" : turn.text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(turn.role == .user ? 0.12 : 0.06))
                )
            if turn.role == .model { Spacer(minLength: 40) }
        }
        .id(turn.id)
    }
}
