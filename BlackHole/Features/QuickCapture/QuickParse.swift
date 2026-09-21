import Foundation

/// Pulls a day and a time out of something typed in a hurry.
///
/// "ship the dmg tomorrow 3pm" is a task called "ship the dmg", due tomorrow, reminding at 15:00.
/// Only words at the edges of the sentence are eaten, so "meet friday's deadline" keeps its Friday.
enum QuickParse {
    struct Result: Equatable {
        var title: String
        var dayKey: String
        /// When to nudge, if a time was given.
        var reminder: Date?
    }

    static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> Result? {
        var words = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return nil }

        var day = calendar.startOfDay(for: now)
        var matchedDay = false
        var time: (hour: Int, minute: Int)?

        // Work from the end: that's where people put "tomorrow at 4".
        while let last = words.last {
            let token = last.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",."))
            if token == "at" || token == "on" || token == "by" {
                // Only a filler word if something after it was already understood.
                guard matchedDay || time != nil else { break }
                words.removeLast()
                continue
            }
            if let clock = clock(token) {
                guard time == nil else { break }
                time = clock
                words.removeLast()
                continue
            }
            if let offset = dayOffset(token, now: now, calendar: calendar) {
                guard !matchedDay else { break }
                day = calendar.date(byAdding: .day, value: offset, to: day) ?? day
                matchedDay = true
                words.removeLast()
                continue
            }
            break
        }

        let title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        var reminder: Date?
        if let time {
            reminder = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
            // "3pm" after 3pm means tomorrow, unless a day was named.
            if let r = reminder, r <= now, !matchedDay {
                reminder = calendar.date(byAdding: .day, value: 1, to: r)
                day = calendar.startOfDay(for: reminder ?? day)
            }
        }

        return Result(title: title, dayKey: DayKey.of(day), reminder: reminder)
    }

    /// "today", "tomorrow", "mon".."sunday" — as a number of days from now.
    private static func dayOffset(_ token: String, now: Date, calendar: Calendar) -> Int? {
        switch token {
        case "today", "tonight": return 0
        case "tomorrow", "tmr", "tmrw": return 1
        default: break
        }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        guard let index = names.firstIndex(where: { $0 == token || $0.prefix(3) == token && token.count == 3 })
        else { return nil }
        let target = index + 1
        let current = calendar.component(.weekday, from: now)
        // The next one of that weekday; naming today's weekday means a week out.
        let delta = (target - current + 7) % 7
        return delta == 0 ? 7 : delta
    }

    /// "3pm", "3:30pm", "15:00", "9am".
    private static func clock(_ token: String) -> (hour: Int, minute: Int)? {
        let pattern = #"^(\d{1,2})(?::(\d{2}))?(am|pm)?$"#
        guard let match = token.range(of: pattern, options: .regularExpression) else { return nil }
        let text = String(token[match])
        let suffix = text.hasSuffix("am") ? "am" : (text.hasSuffix("pm") ? "pm" : nil)
        let numbers = text.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "")
        let parts = numbers.split(separator: ":")
        guard var hour = Int(parts.first ?? "") else { return nil }
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        guard minute < 60 else { return nil }

        switch suffix {
        case "pm": hour = hour == 12 ? 12 : hour + 12
        case "am": hour = hour == 12 ? 0 : hour
        default:
            // A bare number is only a time when it couldn't be anything else.
            guard numbers.contains(":"), hour < 24 else { return nil }
        }
        guard hour < 24 else { return nil }
        return (hour, minute)
    }
}
