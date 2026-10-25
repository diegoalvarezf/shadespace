import SwiftUI

struct FileTrayView: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        let items = modules.tray.items
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "tray.full")
                    .font(.system(size: 11, weight: .semibold))
                Text("Tray")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .opacity(0.6)
                Spacer()
                if !items.isEmpty {
                    Button("Clear") { modules.tray.clear() }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 20, weight: .ultraLight))
                    Text("Drop files on the notch to keep them here")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.white.opacity(0.25))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            TrayItemView(item: item)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear { modules.tray.pruneMissing() }
    }
}

private struct TrayItemView: View {
    let item: TrayItem
    @EnvironmentObject var modules: ModuleRegistry
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.08 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: { modules.tray.remove(item) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { modules.tray.open(item) }
        // Drag out of the tray into Finder, Mail, a browser…
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { modules.tray.open(item) }
            Button("Show in Finder") { modules.tray.reveal(item) }
            Divider()
            Button("Remove from Tray") { modules.tray.remove(item) }
        }
        .help(item.url.path)
    }
}
