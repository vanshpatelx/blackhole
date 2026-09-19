import AppKit
import SwiftUI

/// Scripted run through the app for recording clips: `-demoData YES -demoReel YES`.
///
/// Everything here drives the same view models a person's clicks drive, so what gets recorded is
/// the app actually working rather than a mock-up. It only runs in demo mode, so a reel can never
/// touch someone's real tasks, notes or calendar.
@MainActor
enum DemoReel {
    /// One beat of the reel: wait, then do something.
    private struct Beat {
        let after: TimeInterval
        let run: (AppServices) -> Void
    }

    static func start(_ services: AppServices) {
        guard AppServices.isDemo else { return }
        let beats: [Beat] = [
            // The notch drops open, the way hovering it does.
            .init(after: 1.2) { $0.notch.expand(pinned: true) },

            // A task arrives and gets ticked off, which is what makes Holey cheer.
            .init(after: 2.6) { _ = $0.taskActions.add("Post the launch video") },
            .init(after: 4.4) { s in
                guard let task = s.taskActions.tasks(for: DayKey.today).first(where: { !$0.isDone }) else { return }
                s.taskActions.setDone(task, true)
            },

            // A note line becomes a task for today.
            .init(after: 6.4) { _ = $0.taskActions.appendToNote("Reply to the Show HN thread", dayKey: DayKey.today) },
            .init(after: 7.6) { _ = $0.taskActions.add("Reply to the Show HN thread") },

            // Insights, long enough for the chart to draw and be read.
            .init(after: 9.4) { $0.notch.tab = .insights },
            .init(after: 13.0) { $0.notch.tab = .workspace },

            // A focus session starts and the notch collapses to the live island.
            .init(after: 14.6) { $0.focus.start(targetSec: 25 * 60, stopwatch: false) },
            .init(after: 16.0) { $0.notch.collapse() },

            // Back to the top, so the reel can loop while recording.
            .init(after: 23.0) { s in
                _ = s.focus.stop()
                s.notch.expand(pinned: true)
            },
            .init(after: 25.0) { $0.notch.collapse() }
        ]

        for beat in beats {
            DispatchQueue.main.asyncAfter(deadline: .now() + beat.after) {
                MainActor.assumeIsolated { beat.run(services) }
            }
        }
    }
}
