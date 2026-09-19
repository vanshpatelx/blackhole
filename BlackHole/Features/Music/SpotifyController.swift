import AppKit
import SwiftUI

/// Playback for the Spotify desktop app, over Apple events.
///
/// Nothing here needs a Spotify login or an API key: it talks to the copy of Spotify already running
/// on this Mac, the same way the menu bar does. macOS asks once for permission to control Spotify.
@MainActor
@Observable
final class SpotifyController {
    struct Track: Equatable {
        let id: String
        let name: String
        let artist: String
        let artworkURL: URL?
    }

    enum Availability: Equatable {
        /// Spotify isn't running, so there is nothing to show yet.
        case notRunning
        /// Running, and we're allowed to ask it things.
        case ready
        /// Running, but the user hasn't allowed Black Hole to control it.
        case notPermitted
    }

    private(set) var availability: Availability = .notRunning
    private(set) var isPlaying = false
    private(set) var track: Track?
    private(set) var artwork: NSImage?

    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var artworkTrackID: String?

    /// Spotify's bundle id, used to see whether it's running before asking it anything — launching
    /// it behind someone's back would be rude.
    private static let bundleID = "com.spotify.client"

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // Deliberately no work in `init`: the first Apple event is what makes macOS ask permission to
    // control Spotify, and that question should arrive when the card is on screen, not at launch.

    /// Polls while the workspace is on screen, and stops when it isn't.
    func setActive(_ active: Bool) {
        poll?.invalidate()
        poll = nil
        guard active else { return }
        refresh()
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func playPause() {
        run("playpause")
    }

    func next() {
        run("next track")
    }

    func previous() {
        run("previous track")
    }

    /// Brings Spotify forward, for when there's nothing playing to control.
    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func refresh() {
        guard Self.isRunning else {
            availability = .notRunning
            isPlaying = false
            track = nil
            artwork = nil
            return
        }
        // One script for the lot: round trips to another app aren't free, and we do this every 2s.
        let script = """
        tell application "Spotify"
            set out to (player state as text) & "\\n" & ¬
                (id of current track) & "\\n" & ¬
                (name of current track) & "\\n" & ¬
                (artist of current track) & "\\n" & ¬
                (artwork url of current track)
        end tell
        """
        guard let output = evaluate(script) else { return }
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 5 else { return }
        availability = .ready
        isPlaying = lines[0] == "playing"
        let fresh = Track(
            id: lines[1],
            name: lines[2],
            artist: lines[3],
            artworkURL: URL(string: lines[4])
        )
        if fresh != track {
            track = fresh
            loadArtwork(for: fresh)
        }
    }

    private func run(_ command: String) {
        guard Self.isRunning else { return }
        _ = evaluate("tell application \"Spotify\" to \(command)")
        // Spotify needs a beat to settle before it reports the new state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    @discardableResult
    private func evaluate(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -1743 is the user saying no to the automation prompt; anything else is Spotify being busy.
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                availability = .notPermitted
            }
            return nil
        }
        return result?.stringValue
    }

    private func loadArtwork(for track: Track) {
        guard let url = track.artworkURL else {
            artwork = nil
            return
        }
        artworkTrackID = track.id
        Task { [weak self] in
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let image = NSImage(data: data) else { return }
            await MainActor.run {
                // A slow download for a track that has already changed isn't worth showing.
                guard let self, self.artworkTrackID == track.id else { return }
                self.artwork = image
            }
        }
    }
}
