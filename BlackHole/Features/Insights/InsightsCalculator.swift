import Foundation

/// Pure aggregation over tasks and focus sessions, kept free of SwiftData so it's easy to test.
struct InsightsCalculator {
    struct TaskRecord {
        var dayKey: String
        var isDone: Bool
        var completedAt: Date?
    }

    struct SessionRecord {
        var startedAt: Date
        var seconds: Double
    }

    struct Day: Identifiable, Equatable {
        var id: String {
            dayKey
        }

        let dayKey: String
        let date: Date
        let planned: Int
        let completed: Int
        let focusSeconds: Double

        var focusMinutes: Double {
            focusSeconds / 60
        }

        var isActive: Bool {
            completed > 0 || focusSeconds >= 60
        }
    }

    let tasks: [TaskRecord]
    let sessions: [SessionRecord]
    var calendar = Calendar.current

    /// The seven days ending on `today`, oldest first.
    func week(endingOn today: Date) -> [Day] {
        (0 ..< 7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today)).map(day)
        }
    }

    func day(_ date: Date) -> Day {
        let key = DayKey.of(date)
        let planned = tasks.filter { $0.dayKey == key }.count
        let completed = tasks.filter { t in t.completedAt.map { calendar.isDate($0, inSameDayAs: date) } ?? false }.count
        let focus = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }.reduce(0) { $0 + $1.seconds }
        return Day(
            dayKey: key,
            date: calendar.startOfDay(for: date),
            planned: max(planned, completed),
            completed: completed,
            focusSeconds: focus
        )
    }

    /// Consecutive active days ending today. An inactive today doesn't break a streak that ran through yesterday.
    func currentStreak(today: Date) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: today)
        if !day(cursor).isActive {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        while day(cursor).isActive {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    static func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
