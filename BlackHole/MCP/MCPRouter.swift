import Foundation
import SwiftData

/// Handles Model Context Protocol JSON-RPC messages and runs Black Hole's tools.
/// Transport-agnostic: the local HTTP server and tests both feed it raw JSON.
@MainActor
final class MCPRouter {
    static let latestProtocolVersion = "2025-06-18"
    private static let supportedProtocolVersions: Set<String> = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]

    private let context: ModelContext
    private let tasks: TaskActions
    private let focus: FocusEngine
    private let calendar: CalendarService?
    private let now: () -> Date

    init(context: ModelContext, tasks: TaskActions, focus: FocusEngine, calendar: CalendarService?, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.tasks = tasks
        self.focus = focus
        self.calendar = calendar
        self.now = now
    }

    /// Returns the JSON response body, or `nil` when the message needs no reply (notifications).
    func handle(_ body: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            return encode(Self.error(id: NSNull(), code: -32700, message: "Parse error"))
        }
        if let batch = json as? [[String: Any]] {
            let replies = batch.compactMap(respond)
            return replies.isEmpty ? nil : encode(replies)
        }
        guard let message = json as? [String: Any] else {
            return encode(Self.error(id: NSNull(), code: -32600, message: "Invalid request"))
        }
        return respond(to: message).map(encode)
    }

    private func respond(to message: [String: Any]) -> [String: Any]? {
        guard let method = message["method"] as? String else {
            return Self.error(id: message["id"] ?? NSNull(), code: -32600, message: "Invalid request")
        }
        // Messages without an id are notifications and never get a response.
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? Self.latestProtocolVersion
            return Self.result(id: id, [
                "protocolVersion": Self.supportedProtocolVersions.contains(requested) ? requested : Self.latestProtocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "black-hole", "title": "Black Hole",
                               "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"],
                "instructions": """
                    Black Hole is the user's daily planner living in their Mac's notch. Days use YYYY-MM-DD \
                    or "today"/"tomorrow". Keep task titles short and actionable. Only delete tasks when the user asks.
                    """,
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": Self.toolDefinitions])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.error(id: id, code: -32602, message: "Missing tool name")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let output = try callTool(name, args)
                let text = String(data: (try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])) ?? Data(), encoding: .utf8) ?? "{}"
                return Self.result(id: id, ["content": [["type": "text", "text": text]], "structuredContent": output, "isError": false])
            } catch let error as ToolError {
                if case .unknownTool = error {
                    return Self.error(id: id, code: -32602, message: error.message)
                }
                return Self.result(id: id, ["content": [["type": "text", "text": error.message]], "isError": true])
            } catch {
                return Self.result(id: id, ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: Tools

    enum ToolError: Error {
        case unknownTool(String)
        case invalid(String)

        var message: String {
            switch self {
            case .unknownTool(let name): "Unknown tool: \(name)"
            case .invalid(let reason): reason
            }
        }
    }

    private func callTool(_ name: String, _ args: [String: Any]) throws -> [String: Any] {
        switch name {
        case "list_tasks":
            let day = try dayKey(args["day"])
            return ["day": day, "tasks": tasks.tasks(for: day).map(taskJSON)]

        case "add_task":
            guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                throw ToolError.invalid("`title` is required")
            }
            let day = try dayKey(args["day"])
            guard let task = tasks.add(title, dayKey: day) else { throw ToolError.invalid("Could not add the task") }
            if let minutes = int(args["time_limit_minutes"]), minutes > 0 { tasks.setTimeLimit(task, minutes: minutes) }
            if let remind = args["remind_at"] as? String {
                guard let date = Self.parseDate(remind) else { throw ToolError.invalid("`remind_at` must be an ISO 8601 date-time") }
                tasks.setReminder(task, at: date)
            }
            return ["task": taskJSON(task)]

        case "update_task":
            let task = try findTask(args["id"])
            if let title = args["title"] as? String { tasks.rename(task, to: title) }
            if let done = args["done"] as? Bool { tasks.setDone(task, done) }
            if let minutes = int(args["time_limit_minutes"]) { tasks.setTimeLimit(task, minutes: minutes > 0 ? minutes : nil) }
            if args["day"] != nil { tasks.move(task, toDay: try dayKey(args["day"])) }
            if let remind = args["remind_at"] {
                if remind is NSNull || (remind as? String)?.isEmpty == true {
                    tasks.setReminder(task, at: nil)
                } else if let raw = remind as? String, let date = Self.parseDate(raw) {
                    tasks.setReminder(task, at: date)
                } else {
                    throw ToolError.invalid("`remind_at` must be an ISO 8601 date-time, or empty to clear")
                }
            }
            return ["task": taskJSON(task)]

        case "delete_task":
            let task = try findTask(args["id"])
            let title = task.title
            tasks.delete(task)
            return ["deleted": title]

        case "start_focus":
            var taskID: UUID?
            if args["task_id"] != nil { taskID = try findTask(args["task_id"]).id }
            if let minutes = int(args["minutes"]) {
                focus.start(taskID: taskID, targetSec: minutes > 0 ? minutes * 60 : nil, stopwatch: minutes == 0)
            } else if let id = taskID, let limit = tasks.task(with: id)?.timeLimitSec {
                focus.start(taskID: id, targetSec: limit)
            } else {
                focus.start(taskID: taskID, targetSec: 25 * 60)
            }
            return focusJSON()

        case "pause_focus":
            focus.pause()
            return focusJSON()

        case "resume_focus":
            focus.resume()
            return focusJSON()

        case "stop_focus":
            focus.stop()
            return focusJSON()

        case "focus_status":
            return focusJSON()

        case "read_note":
            let day = try dayKey(args["day"])
            return ["day": day, "text": tasks.note(for: day)?.text ?? ""]

        case "append_note":
            guard let text = args["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolError.invalid("`text` is required")
            }
            let day = try dayKey(args["day"])
            return ["day": day, "text": tasks.appendToNote(text, dayKey: day).text]

        case "get_insights":
            let days = min(max(int(args["days"]) ?? 7, 1), 60)
            return insightsJSON(days: days)

        case "todays_events":
            guard let calendar else { return ["connected": false, "events": []] }
            guard calendar.status == .connected else {
                return ["connected": false, "events": [], "hint": "Ask the user to connect Calendar in Black Hole Settings."]
            }
            return ["connected": true, "events": calendar.events.map { e in
                ["title": e.title, "calendar": e.calendarTitle, "all_day": e.isAllDay,
                 "start": Self.iso(e.start), "end": Self.iso(e.end), "happening_now": e.isHappening(at: now())] as [String: Any]
            }]

        default:
            throw ToolError.unknownTool(name)
        }
    }

    // MARK: JSON builders

    private func taskJSON(_ t: TaskItem) -> [String: Any] {
        var json: [String: Any] = ["id": t.id.uuidString, "title": t.title, "day": t.dayKey, "done": t.isDone,
                                   "focusing": focus.isActive && focus.taskID == t.id]
        if let limit = t.timeLimitSec { json["time_limit_minutes"] = limit / 60 }
        if let reminder = t.reminderAt { json["remind_at"] = Self.iso(reminder) }
        if let done = t.completedAt { json["completed_at"] = Self.iso(done) }
        return json
    }

    private func focusJSON() -> [String: Any] {
        let date = now()
        var json: [String: Any] = ["state": focus.phase.rawValue]
        guard focus.isActive else { return json }
        json["mode"] = focus.targetSec == nil ? "stopwatch" : "countdown"
        json["elapsed_seconds"] = Int(focus.elapsed(at: date))
        if let remaining = focus.remaining(at: date) { json["remaining_seconds"] = Int(remaining.rounded(.up)) }
        if let id = focus.taskID, let task = tasks.task(with: id) { json["task"] = ["id": id.uuidString, "title": task.title] }
        return json
    }

    private func insightsJSON(days: Int) -> [String: Any] {
        let allTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
        let calc = InsightsCalculator(
            tasks: allTasks.map { .init(dayKey: $0.dayKey, isDone: $0.isDone, completedAt: $0.completedAt) },
            sessions: sessions.map { .init(startedAt: $0.startedAt, seconds: $0.endedAt == nil && focus.isActive ? focus.elapsed(at: now()) : $0.accumulatedSec) })
        let cal = Calendar.current
        let today = cal.startOfDay(for: now())
        let range = (0..<days).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.map(calc.day)
        return [
            "days": range.map { ["day": $0.dayKey, "planned": $0.planned, "completed": $0.completed, "focus_minutes": Int($0.focusMinutes)] },
            "total_focus_minutes": Int(range.reduce(0) { $0 + $1.focusMinutes }),
            "total_completed": range.reduce(0) { $0 + $1.completed },
            "active_days": range.filter(\.isActive).count,
            "current_streak_days": calc.currentStreak(today: now()),
        ]
    }

    // MARK: Argument parsing

    private func findTask(_ raw: Any?) throws -> TaskItem {
        guard let string = raw as? String, let id = UUID(uuidString: string) else { throw ToolError.invalid("`id` must be a task id from list_tasks") }
        guard let task = tasks.task(with: id) else { throw ToolError.invalid("No task with id \(string)") }
        return task
    }

    private func dayKey(_ raw: Any?) throws -> String {
        let cal = Calendar.current
        switch (raw as? String)?.lowercased().trimmingCharacters(in: .whitespaces) {
        case nil, "", "today": return DayKey.of(now())
        case "tomorrow": return DayKey.of(cal.date(byAdding: .day, value: 1, to: now())!)
        case "yesterday": return DayKey.of(cal.date(byAdding: .day, value: -1, to: now())!)
        case let value?:
            guard let date = DayKey.date(value) else { throw ToolError.invalid("`day` must be YYYY-MM-DD, today, tomorrow or yesterday") }
            return DayKey.of(date)
        }
    }

    private func int(_ raw: Any?) -> Int? {
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s) }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return full.date(from: raw) ?? plain.date(from: raw) ?? local.date(from: raw)
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f.string(from: date)
    }

    // MARK: JSON-RPC helpers

    private func encode(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    private static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    // MARK: Tool catalog

    private static func schema(_ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }

    private static let dayProperty: [String: Any] = ["type": "string", "description": "YYYY-MM-DD, \"today\" (default), \"tomorrow\" or \"yesterday\""]
    private static let idProperty: [String: Any] = ["type": "string", "description": "Task id from list_tasks"]

    static let toolDefinitions: [[String: Any]] = [
        ["name": "list_tasks", "title": "List tasks",
         "description": "List the user's tasks for a day, in their planned order, with done state, time limit and reminder.",
         "inputSchema": schema(["day": dayProperty]),
         "annotations": ["readOnlyHint": true]],
        ["name": "add_task", "title": "Add task",
         "description": "Add a task to a day (today by default). Optionally set a focus time limit and a reminder.",
         "inputSchema": schema([
            "title": ["type": "string", "description": "Short, actionable task title"],
            "day": dayProperty,
            "time_limit_minutes": ["type": "integer", "minimum": 1, "description": "Focus time limit in minutes"],
            "remind_at": ["type": "string", "description": "ISO 8601 date-time for a reminder notification"],
         ], required: ["title"])],
        ["name": "update_task", "title": "Update task",
         "description": "Rename a task, mark it done or not done, move it to another day, change its time limit (0 clears) or reminder (empty clears).",
         "inputSchema": schema([
            "id": idProperty,
            "title": ["type": "string"],
            "done": ["type": "boolean"],
            "day": dayProperty,
            "time_limit_minutes": ["type": "integer", "minimum": 0],
            "remind_at": ["type": "string"],
         ], required: ["id"])],
        ["name": "delete_task", "title": "Delete task",
         "description": "Permanently delete a task. Only use when the user explicitly asks.",
         "inputSchema": schema(["id": idProperty], required: ["id"]),
         "annotations": ["destructiveHint": true]],
        ["name": "start_focus", "title": "Start focus session",
         "description": "Start the focus timer, optionally on a task. minutes defaults to the task's time limit or 25; 0 starts a stopwatch.",
         "inputSchema": schema([
            "task_id": idProperty,
            "minutes": ["type": "integer", "minimum": 0],
         ])],
        ["name": "pause_focus", "title": "Pause focus", "description": "Pause the running focus session.", "inputSchema": schema()],
        ["name": "resume_focus", "title": "Resume focus", "description": "Resume a paused focus session.", "inputSchema": schema()],
        ["name": "stop_focus", "title": "Stop focus", "description": "End the current focus session. Time so far is kept in insights.", "inputSchema": schema()],
        ["name": "focus_status", "title": "Focus status",
         "description": "Current focus timer state: idle, running, paused or finished, with time elapsed/remaining and the task.",
         "inputSchema": schema(), "annotations": ["readOnlyHint": true]],
        ["name": "read_note", "title": "Read daily note",
         "description": "Read the user's daily notepad for a day.",
         "inputSchema": schema(["day": dayProperty]), "annotations": ["readOnlyHint": true]],
        ["name": "append_note", "title": "Append to daily note",
         "description": "Append a line to the daily notepad. Never overwrites existing text.",
         "inputSchema": schema(["text": ["type": "string"], "day": dayProperty], required: ["text"])],
        ["name": "get_insights", "title": "Get insights",
         "description": "Per-day planned tasks, completed tasks and focus minutes for recent days, plus totals and the current streak.",
         "inputSchema": schema(["days": ["type": "integer", "minimum": 1, "maximum": 60, "description": "How many days back, default 7"]]),
         "annotations": ["readOnlyHint": true]],
        ["name": "todays_events", "title": "Today's events",
         "description": "Upcoming calendar events for today from the calendars the user chose to show (read-only).",
         "inputSchema": schema(), "annotations": ["readOnlyHint": true]],
    ]
}
