import AppKit
import Foundation

/// Carries out a typed command and says, in one line, what happened.
///
/// Every verb goes through the same services the MCP tools use, so the keyboard and an assistant
/// drive identical code rather than two implementations that drift apart.
@MainActor
struct CommandRunner {
    let services: AppServices

    /// - Returns: A short confirmation to show in the bar, or nil when there was nothing to do.
    func run(_ command: Command) -> String? {
        switch command {
        case let .task(parsed):
            return addTask(parsed)

        case let .startFocus(minutes, subject):
            return startFocus(minutes: minutes, subject: subject)

        case .pauseFocus:
            guard services.focus.phase == .running else { return "Nothing is running" }
            services.focus.pause()
            return "Paused"

        case .resumeFocus:
            guard services.focus.phase == .paused else { return "Nothing to resume" }
            services.focus.resume()
            return "Resumed"

        case .stopFocus:
            guard services.focus.isActive else { return "Nothing is running" }
            _ = services.focus.stop()
            return "Stopped"

        case .joinMeeting:
            guard let meeting = services.calendar.imminentMeeting() else { return "No meeting coming up" }
            guard let url = meeting.meetingURL else { return "\(meeting.title) has no link to join" }
            NSWorkspace.shared.open(url)
            return "Joining \(meeting.title)"

        case let .note(text):
            _ = services.taskActions.appendToNote(text, dayKey: DayKey.today)
            return "Noted"

        case .insights:
            services.notch.tab = .insights
            services.notch.expand(pinned: true)
            return nil

        case let .music(action):
            return music(action)
        }
    }

    private func addTask(_ parsed: QuickParse.Result) -> String? {
        guard let task = services.taskActions.add(parsed.title, dayKey: parsed.dayKey) else { return nil }
        if let reminder = parsed.reminder {
            services.taskActions.setReminder(task, at: reminder)
        }
        if let rule = parsed.recurrence {
            services.taskActions.setRecurrence(task, rule)
        }
        services.mascot.celebrate()
        return nil
    }

    private func startFocus(minutes: Int?, subject: String?) -> String? {
        // Naming a task focuses that task, so the session shows up against it in Insights.
        if let subject {
            let match = services.taskActions.tasks(for: DayKey.today).first {
                $0.title.localizedCaseInsensitiveContains(subject)
            }
            if let match {
                if let minutes {
                    services.taskActions.setTimeLimit(match, minutes: minutes)
                }
                services.taskActions.focus(on: match)
                return "Focusing on \(match.title)"
            }
        }
        services.focus.start(targetSec: minutes.map { $0 * 60 }, stopwatch: minutes == nil)
        return minutes.map { "Focusing for \($0)m" } ?? "Stopwatch running"
    }

    private func music(_ action: Command.Music) -> String? {
        let spotify = services.spotify
        switch action {
        case .playPause: spotify.playPause()
        case .next: spotify.next()
        case .previous: spotify.previous()
        }
        guard spotify.availability != .notRunning else { return "Spotify isn't open" }
        return spotify.track.map { "\($0.name) — \($0.artist)" } ?? "Spotify"
    }
}
