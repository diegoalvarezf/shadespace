import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        Group {
            if let snap = modules.nowPlaying.snapshot {
                playing(snap)
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func playing(_ snap: NowPlayingSnapshot) -> some View {
        HStack(spacing: 12) {
            artworkView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(snap.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(snap.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                ProgressBar(snap: snap, snapshotDate: modules.nowPlaying.snapshotDate)
                    .padding(.top, 5)
                controls(snap)
                    .padding(.top, 4)
            }
        }
    }

    private var artworkView: some View {
        Group {
            if let img = modules.nowPlaying.artwork {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func controls(_ snap: NowPlayingSnapshot) -> some View {
        HStack(spacing: 20) {
            controlBtn("backward.fill", size: 12) { modules.nowPlaying.previous() }
            controlBtn(snap.isPlaying ? "pause.fill" : "play.fill", size: 16) { modules.nowPlaying.playPause() }
            controlBtn("forward.fill", size: 12) { modules.nowPlaying.next() }
        }
    }

    private func controlBtn(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var idle: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note").font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary)
            Text("Nothing playing").font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Capsule().fill(.white.opacity(0.85)).frame(width: geo.size.width * p)
                }
            }
            .frame(height: 3)
        }
    }
}
