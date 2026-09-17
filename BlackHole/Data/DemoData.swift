import Foundation
import SwiftData

/// Sample content for `-demoData YES` launches.
enum DemoData {
    @MainActor
    static func seed(into context: ModelContext) {
        let cal = Calendar.current
        let today = DayKey.today

        let tasks: [(String, Bool, Int?, Date?)] = [
            ("Ship v0.1 DMG", true, 45 * 60, nil),
            ("Write the launch tweet", false, 25 * 60, cal.date(byAdding: .hour, value: 2, to: .now)),
            ("Review open pull requests", false, nil, nil),
            ("Plan sync + MCP support", false, 60 * 60, nil),
        ]
        for (i, t) in tasks.enumerated() {
            let item = TaskItem(title: t.0, dayKey: today, sortIndex: i)
            item.isDone = t.1
            item.completedAt = t.1 ? .now : nil
            item.timeLimitSec = t.2
            item.reminderAt = t.3
            context.insert(item)
        }

        // A believable last week for Insights.
        let focusMinutes = [35, 80, 0, 25, 120, 150, 55]
        let completed = [2, 4, 0, 1, 3, 6, 1]
        for dayOffset in 1...6 {
            guard let day = cal.date(byAdding: .day, value: -dayOffset, to: cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!) else { continue }
            let key = DayKey.of(day)
            let minutes = focusMinutes[6 - dayOffset]
            if minutes > 0 {
                let session = FocusSession(taskID: nil, targetSec: minutes * 60)
                session.startedAt = day
                session.endedAt = day.addingTimeInterval(Double(minutes * 60))
                session.accumulatedSec = Double(minutes * 60)
                context.insert(session)
            }
            for n in 0..<(completed[6 - dayOffset] + 1) {
                let item = TaskItem(title: "Past task \(n + 1)", dayKey: key, sortIndex: n)
                if n < completed[6 - dayOffset] {
                    item.isDone = true
                    item.completedAt = day.addingTimeInterval(Double(n) * 1800)
                }
                context.insert(item)
            }
        }

        context.insert(DailyNote(dayKey: today, text: "Launch checklist\n- README screenshots\n- Record a 20s demo\n- Post on X + Product Hunt"))
        try? context.save()
    }
}
