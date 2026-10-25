import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        Group {
            if let track = modules.nowPlaying.track {
                playing(track)
            } else {
                HomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Playing state

    private func playing(_ track: NowPlayingTrack) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                artworkView
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        EqualizerBars(isActive: track.isPlaying, color: .white.opacity(0.55))
                            .frame(width: 20, height: 14)
                    }

                    LyricOrArtistLine(track: track)
                        .padding(.top, 2)

                    ProgressRow(track: track, snapshotDate: modules.nowPlaying.snapshotDate) { fraction in
                        modules.nowPlaying.seek(toFraction: fraction)
                    }
                    .padding(.top, 9)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)

            controls(track)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let img = modules.nowPlaying.artwork {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
        }
    }

    // MARK: - Controls

    private func controls(_ track: NowPlayingTrack) -> some View {
        HStack(spacing: 0) {
            controlBtn("shuffle", size: 11, opacity: track.shuffle ? 0.9 : 0.25) {
                modules.nowPlaying.toggleShuffle()
            }
            Spacer()

            controlBtn("backward.fill", size: 15, opacity: 0.7) {
                modules.nowPlaying.previous()
            }
            Spacer()

            Button(action: { modules.nowPlaying.playPause() }) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: track.isPlaying ? 0 : 1.5)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            controlBtn("forward.fill", size: 15, opacity: 0.7) {
                modules.nowPlaying.next()
            }
            Spacer()

            controlBtn(track.repeatMode == .one ? "repeat.1" : "repeat", size: 11,
                       opacity: track.repeatMode == .off ? 0.25 : 0.9) {
                modules.nowPlaying.cycleRepeat()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func controlBtn(
        _ symbol: String,
        size: CGFloat,
        opacity: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(opacity))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lyric / artist line

/// Shows the current synced lyric when available, otherwise the artist.
private struct LyricOrArtistLine: View {
    let track: NowPlayingTrack
    @EnvironmentObject var modules: ModuleRegistry

    var body: some View {
        if let lyrics = modules.nowPlaying.lyrics, !lyrics.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let position = track.position(at: ctx.date, since: modules.nowPlaying.snapshotDate)
                let line = lyrics.line(at: position)?.text ?? ""
                Text(line.isEmpty ? track.artist : line)
                    .font(.system(size: 11, weight: line.isEmpty ? .regular : .medium))
                    .foregroundStyle(.white.opacity(line.isEmpty ? 0.45 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(line)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: line)
            }
        } else {
            Text(track.artist)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Progress Row

/// Progress bar that can be dragged to seek. The bar only grows while scrubbing.
private struct ProgressRow: View {
    let track: NowPlayingTrack
    let snapshotDate: Date
    let onSeek: (Double) -> Void
    @State private var scrubFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let livePosition = track.position(at: ctx.date, since: snapshotDate)
            let fraction = scrubFraction ?? track.progress(at: ctx.date, since: snapshotDate)
            let elapsed = scrubFraction.map { $0 * track.durationSec } ?? livePosition
            let remaining = track.durationSec - elapsed

            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.1))
                        Capsule()
                            .fill(.white.opacity(0.7))
                            .frame(width: max(0, geo.size.width * CGFloat(fraction)))
                    }
                    .frame(height: scrubFraction == nil ? 2 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                scrubFraction = min(max(value.location.x / geo.size.width, 0), 1)
                            }
                            .onEnded { value in
                                let final = min(max(value.location.x / geo.size.width, 0), 1)
                                onSeek(final)
                                scrubFraction = nil
                            }
                    )
                    .animation(.easeOut(duration: 0.15), value: scrubFraction == nil)
                }
                .frame(height: 8)

                HStack {
                    Text(formatTime(elapsed))
                    Spacer()
                    Text("-\(formatTime(max(0, remaining)))")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
