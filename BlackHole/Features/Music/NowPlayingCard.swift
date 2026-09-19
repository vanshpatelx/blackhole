import SwiftUI

/// What Spotify is playing, with the three controls anyone actually reaches for.
struct NowPlayingCard: View {
    /// False inside the notch, where the panel is built at launch and kept in the tree: there the
    /// panel's own expansion drives polling, so opening the workspace is what asks Spotify anything.
    var pollsWhenShown = true
    @Environment(SpotifyController.self) private var spotify

    var body: some View {
        Card(tint: Palette.music) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(icon: "music.note", title: "Playing")

                switch spotify.availability {
                case .ready:
                    if let track = spotify.track {
                        playing(track)
                    } else {
                        hint("Nothing playing.")
                    }
                case .notRunning:
                    VStack(alignment: .leading, spacing: 6) {
                        hint(SpotifyController.isInstalled ? "Spotify isn't open." : "Spotify isn't installed.")
                        if SpotifyController.isInstalled {
                            Button("Open Spotify") { spotify.openSpotify() }
                                .buttonStyle(PillButtonStyle())
                                .fixedSize()
                        }
                    }
                case .notPermitted:
                    hint("Allow Black Hole to control Spotify in System Settings → Privacy & Security → Automation.")
                }

                Spacer(minLength: 0)

                if spotify.availability == .ready {
                    HStack(spacing: 2) {
                        IconButton(systemName: "backward.fill", size: 24, help: "Previous") { spotify.previous() }
                        IconButton(
                            systemName: spotify.isPlaying ? "pause.fill" : "play.fill",
                            size: 28,
                            help: spotify.isPlaying ? "Pause" : "Play"
                        ) { spotify.playPause() }
                        IconButton(systemName: "forward.fill", size: 24, help: "Next") { spotify.next() }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .onAppear {
            if pollsWhenShown {
                spotify.setActive(true)
            }
        }
        .onDisappear {
            if pollsWhenShown {
                spotify.setActive(false)
            }
        }
    }

    private func playing(_ track: SpotifyController.Track) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Group {
                if let art = spotify.artwork {
                    Image(nsImage: art).resizable().scaledToFill()
                } else {
                    Palette.well
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(track.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
