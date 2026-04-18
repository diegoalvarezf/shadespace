import SwiftUI

struct NowPlayingView: View {
    @StateObject private var vm = NowPlayingViewModel()

    var body: some View {
        Group {
            if let snap = vm.snapshot {
                playing(snap)
            } else {
                idle
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private func playing(_ snap: NowPlayingSnapshot) -> some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(snap.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(snap.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressBar(snap: snap, snapshotDate: vm.snapshotDate)
                    .padding(.top, 4)

                controls(snap)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var artwork: some View {
        Group {
            if let img = vm.artwork {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func controls(_ snap: NowPlayingSnapshot) -> some View {
        HStack(spacing: 18) {
            controlBtn("backward.fill", size: 12) { vm.previous() }
            controlBtn(snap.isPlaying ? "pause.fill" : "play.fill", size: 16) { vm.playPause() }
            controlBtn("forward.fill", size: 12) { vm.next() }
        }
    }

    private func controlBtn(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var idle: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .foregroundStyle(.tertiary)
            Text("Nothing playing")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ProgressBar: View {
    let snap: NowPlayingSnapshot
    let snapshotDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let p = CGFloat(snap.progress(at: ctx.date, since: snapshotDate))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(.white.opacity(0.8))
                        .frame(width: geo.size.width * p)
                }
            }
            .frame(height: 3)
        }
    }
}
