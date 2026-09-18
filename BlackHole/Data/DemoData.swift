import Foundation
import SwiftData

/// Sample content for `-demoData YES` launches.
enum DemoData {
    @MainActor
    static func seed(into context: ModelContext) {
        let cal = Calendar.current
        let today = DayKey.today

        struct Seed {
            let title: String
            let done: Bool
            let limitSeconds: Int?
            let remindAt: Date?
        }

        let tasks: [Seed] = [
            Seed(title: "Ship v0.1 DMG", done: true, limitSeconds: 45 * 60, remindAt: nil),
            Seed(
                title: "Write the launch tweet",
                done: false,
                limitSeconds: 25 * 60,
                remindAt: cal.date(byAdding: .hour, value: 2, to: .now)
            ),
            Seed(title: "Review open pull requests", done: false, limitSeconds: nil, remindAt: nil),
            Seed(title: "Plan sync + MCP support", done: false, limitSeconds: 60 * 60, remindAt: nil)
        ]
        for (i, t) in tasks.enumerated() {
            let item = TaskItem(title: t.title, dayKey: today, sortIndex: i)
            item.isDone = t.done
            item.completedAt = t.done ? .now : nil
            item.timeLimitSec = t.limitSeconds
            item.reminderAt = t.remindAt
            context.insert(item)
        }

        // A believable last week for Insights.
        let focusMinutes = [35, 80, 0, 25, 120, 150, 55]
        let completed = [2, 4, 0, 1, 3, 6, 1]
        for dayOffset in 1 ... 6 {
            guard let day = cal.date(byAdding: .day, value: -dayOffset, to: cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!)
            else { continue }
            let key = DayKey.of(day)
            let minutes = focusMinutes[6 - dayOffset]
            if minutes > 0 {
                let session = FocusSession(taskID: nil, targetSec: minutes * 60)
                session.startedAt = day
                session.endedAt = day.addingTimeInterval(Double(minutes * 60))
                session.accumulatedSec = Double(minutes * 60)
                context.insert(session)
            }
            for n in 0 ..< (completed[6 - dayOffset] + 1) {
                let item = TaskItem(title: "Past task \(n + 1)", dayKey: key, sortIndex: n)
                if n < completed[6 - dayOffset] {
                    item.isDone = true
                    item.completedAt = day.addingTimeInterval(Double(n) * 1800)
                }
                context.insert(item)
            }
        }

        context.insert(DailyNote(
            dayKey: today,
            text: "Launch checklist\n- README screenshots\n- Record a 20s demo\n- Post on X + Product Hunt"
        ))
        try? context.save()
    }
}
