import Foundation

/// What a line typed into the bar means.
///
/// Anything that isn't a recognised verb is a task, because that is what people type most and
/// guessing wrong there is the most annoying way to be clever.
enum Command: Equatable {
    case task(QuickParse.Result)
    case startFocus(minutes: Int?, on: String?)
    case pauseFocus
    case resumeFocus
    case stopFocus
    case joinMeeting
    case note(String)
    case insights
    case music(Music)

    enum Music: Equatable { case playPause, next, previous }

    static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> Command? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        var words = trimmed.split(separator: " ").map(String.init)
        let verb = words.removeFirst().lowercased()
        let rest = words.joined(separator: " ")

        // Whole-line phrases people actually type, before anything is picked apart.
        switch lower {
        case "pause", "pause focus", "pause timer": return .pauseFocus
        case "resume", "resume focus", "continue": return .resumeFocus
        case "stop", "stop focus", "stop timer", "done focusing": return .stopFocus
        case "join", "join meeting", "join call": return .joinMeeting
        case "insights", "stats", "what did i do this week", "what did i focus on this week":
            return .insights
        case "play", "pause music", "resume music": return .music(.playPause)
        case "next", "next track", "skip": return .music(.next)
        case "previous", "previous track", "back": return .music(.previous)
        default: break
        }

        switch verb {
        case "focus", "timer":
            return .startFocus(minutes: minutes(in: words), on: subject(in: words))
        case "note", "jot":
            return rest.isEmpty ? nil : .note(rest)
        default:
            guard let parsed = QuickParse.parse(trimmed, now: now, calendar: calendar) else { return nil }
            return .task(parsed)
        }
    }

    /// The first bare number, which is how long to focus for. "focus 45 on the post" → 45.
    private static func minutes(in words: [String]) -> Int? {
        for word in words {
            let digits = word.trimmingCharacters(in: CharacterSet(charactersIn: "m"))
            if let value = Int(digits), value > 0, value <= 600 {
                return value
            }
        }
        return nil
    }

    /// What the session is about: everything after "on", so the task can be matched by name.
    private static func subject(in words: [String]) -> String? {
        guard let index = words.firstIndex(where: { $0.lowercased() == "on" }) else { return nil }
        let subject = words[(index + 1)...].joined(separator: " ")
        return subject.isEmpty ? nil : subject
    }
}
