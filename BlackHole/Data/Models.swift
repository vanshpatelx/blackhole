import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    /// Day the task is planned for, formatted `yyyy-MM-dd` in the user's calendar.
    var dayKey: String
    var sortIndex: Int
    var isDone: Bool
    var completedAt: Date?
    var timeLimitSec: Int?
    var reminderAt: Date?
    var createdAt: Date

    init(title: String, dayKey: String, sortIndex: Int) {
        id = UUID()
        self.title = title
        self.dayKey = dayKey
        self.sortIndex = sortIndex
        isDone = false
        createdAt = .now
    }
}

@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    var taskID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var accumulatedSec: Double
    /// Countdown target in seconds; `nil` for stopwatch sessions.
    var targetSec: Int?

    init(taskID: UUID?, targetSec: Int?) {
        id = UUID()
        self.taskID = taskID
        startedAt = .now
        accumulatedSec = 0
        self.targetSec = targetSec
    }
}

@Model
final class DailyNote {
    @Attribute(.unique) var dayKey: String
    var text: String
    var updatedAt: Date

    init(dayKey: String, text: String = "") {
        self.dayKey = dayKey
        self.text = text
        updatedAt = .now
    }
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func of(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(_ key: String) -> Date? {
        formatter.date(from: key)
    }

    static var today: String {
        of(.now)
    }

    static func adding(days: Int, to key: String) -> String {
        guard let d = date(key), let n = Calendar.current.date(byAdding: .day, value: days, to: d) else { return key }
        return of(n)
    }
}
