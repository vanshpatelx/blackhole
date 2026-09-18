import Foundation
import SwiftData
import UserNotifications

/// All task mutations go through here so views stay declarative and side effects
/// (reminders, focus sessions) stay consistent.
@MainActor
@Observable
final class TaskActions {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let focus: FocusEngine
    @ObservationIgnored var onTaskCompleted: (() -> Void)?

    init(context: ModelContext, focus: FocusEngine) {
        self.context = context
        self.focus = focus
        focus.onFinish = { [weak self] taskID in
            let title = taskID.flatMap { self?.task(with: $0)?.title }
            Notifier.post(id: "focus-finished", title: "Time's up", body: title ?? "Focus session complete")
        }
    }

    func tasks(for dayKey: String) -> [TaskItem] {
        let d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.dayKey == dayKey }, sortBy: [SortDescriptor(\.sortIndex)])
        return (try? context.fetch(d)) ?? []
    }

    func task(with id: UUID) -> TaskItem? {
        var d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    @discardableResult
    func add(_ rawTitle: String, dayKey: String = DayKey.today) -> TaskItem? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let next = (tasks(for: dayKey).map(\.sortIndex).max() ?? -1) + 1
        let task = TaskItem(title: title, dayKey: dayKey, sortIndex: next)
        context.insert(task)
        save()
        return task
    }

    func setDone(_ task: TaskItem, _ done: Bool) {
        task.isDone = done
        task.completedAt = done ? .now : nil
        if done, focus.taskID == task.id { focus.stop() }
        if done { Notifier.cancel(id: task.id.uuidString) }
        save()
        if done { onTaskCompleted?() }
    }

    func rename(_ task: TaskItem, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        task.title = t
        save()
    }

    func setTimeLimit(_ task: TaskItem, minutes: Int?) {
        task.timeLimitSec = minutes.map { $0 * 60 }
        save()
    }

    func focus(on task: TaskItem) {
        if focus.taskID == task.id {
            focus.toggle()
        } else {
            // A task with no time limit counts up; only an explicit limit becomes a countdown.
            focus.start(taskID: task.id, targetSec: task.timeLimitSec, stopwatch: task.timeLimitSec == nil)
        }
    }

    func setReminder(_ task: TaskItem, at date: Date?) {
        task.reminderAt = date
        Notifier.cancel(id: task.id.uuidString)
        if let date { Notifier.schedule(id: task.id.uuidString, title: task.title, body: "Reminder from Black Hole", at: date) }
        save()
    }

    func move(_ task: TaskItem, toDay dayKey: String) {
        guard task.dayKey != dayKey else { return }
        task.sortIndex = (tasks(for: dayKey).map(\.sortIndex).max() ?? -1) + 1
        task.dayKey = dayKey
        if focus.taskID == task.id { focus.stop() }
        save()
    }

    func note(for dayKey: String) -> DailyNote? {
        var d = FetchDescriptor<DailyNote>(predicate: #Predicate { $0.dayKey == dayKey })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Adds a line to the end of a day's notepad, creating the note if needed.
    @discardableResult
    func appendToNote(_ text: String, dayKey: String) -> DailyNote {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = self.note(for: dayKey) ?? {
            let n = DailyNote(dayKey: dayKey)
            context.insert(n)
            return n
        }()
        note.text = note.text.isEmpty ? line : note.text + (note.text.hasSuffix("\n") ? "" : "\n") + line
        note.updatedAt = .now
        save()
        return note
    }

    func moveToTomorrow(_ task: TaskItem) {
        let tomorrow = DayKey.adding(days: 1, to: DayKey.today)
        task.sortIndex = (tasks(for: tomorrow).map(\.sortIndex).max() ?? -1) + 1
        task.dayKey = tomorrow
        if focus.taskID == task.id { focus.stop() }
        save()
    }

    func duplicate(_ task: TaskItem) {
        let copy = TaskItem(title: task.title, dayKey: task.dayKey, sortIndex: task.sortIndex + 1)
        copy.timeLimitSec = task.timeLimitSec
        for t in tasks(for: task.dayKey) where t.sortIndex > task.sortIndex { t.sortIndex += 1 }
        context.insert(copy)
        save()
    }

    func delete(_ task: TaskItem) {
        if focus.taskID == task.id { focus.stop() }
        Notifier.cancel(id: task.id.uuidString)
        context.delete(task)
        save()
    }

    /// Moves `dragged` into the slot currently held by `target`.
    func move(_ draggedID: UUID, before target: TaskItem) {
        var list = tasks(for: target.dayKey)
        guard let from = list.firstIndex(where: { $0.id == draggedID }),
              let to = list.firstIndex(where: { $0.id == target.id }), from != to else { return }
        let item = list.remove(at: from)
        list.insert(item, at: to)
        for (i, t) in list.enumerated() { t.sortIndex = i }
        save()
    }

    /// Unfinished tasks from earlier days follow the user into today.
    func rollOverUnfinishedTasks() {
        let today = DayKey.today
        let d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.dayKey < today && $0.isDone == false })
        guard let stale = try? context.fetch(d), !stale.isEmpty else { return }
        var next = (tasks(for: today).map(\.sortIndex).max() ?? -1) + 1
        for t in stale.sorted(by: { ($0.dayKey, $0.sortIndex) < ($1.dayKey, $1.sortIndex) }) {
            t.dayKey = today
            t.sortIndex = next
            next += 1
        }
        save()
    }

    private func save() { try? context.save() }
}

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(id: String, title: String, body: String, at date: Date) {
        requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    static func post(id: String, title: String, body: String) {
        schedule(id: id, title: title, body: body, at: Date().addingTimeInterval(1))
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

enum ReminderPreset: CaseIterable, Identifiable {
    case in30Minutes, in1Hour, thisEvening, tomorrowMorning

    var id: Self { self }

    var title: String {
        switch self {
        case .in30Minutes: "In 30 Minutes"
        case .in1Hour: "In 1 Hour"
        case .thisEvening: "This Evening"
        case .tomorrowMorning: "Tomorrow Morning"
        }
    }

    func date(from now: Date = .now) -> Date {
        let cal = Calendar.current
        switch self {
        case .in30Minutes: return now.addingTimeInterval(30 * 60)
        case .in1Hour: return now.addingTimeInterval(60 * 60)
        case .thisEvening:
            let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
            return evening > now ? evening : now.addingTimeInterval(60 * 60)
        case .tomorrowMorning:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        }
    }
}
