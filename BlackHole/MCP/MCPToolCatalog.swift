import Foundation

/// The tools Black Hole advertises over MCP, with their JSON schemas.
extension MCPRouter {
    private static func schema(_ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }

    private static let dayProperty: [String: Any] = [
        "type": "string",
        "description": "YYYY-MM-DD, \"today\" (default), \"tomorrow\" or \"yesterday\""
    ]
    private static let idProperty: [String: Any] = ["type": "string", "description": "Task id from list_tasks"]

    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "list_tasks",
            "title": "List tasks",
            "description": "List the user's tasks for a day, in their planned order, with done state, time limit and reminder.",
            "inputSchema": schema(["day": dayProperty]),
            "annotations": ["readOnlyHint": true]
        ],
        [
            "name": "add_task",
            "title": "Add task",
            "description": "Add a task to a day (today by default). Optionally set a focus time limit and a reminder.",
            "inputSchema": schema([
                "title": ["type": "string", "description": "Short, actionable task title"],
                "day": dayProperty,
                "time_limit_minutes": ["type": "integer", "minimum": 1, "description": "Focus time limit in minutes"],
                "remind_at": ["type": "string", "description": "ISO 8601 date-time for a reminder notification"]
            ], required: ["title"])
        ],
        [
            "name": "update_task",
            "title": "Update task",
            "description": """
            Rename a task, mark it done or not done, move it to another day, \
            change its time limit (0 clears) or reminder (empty clears).
            """,
            "inputSchema": schema([
                "id": idProperty,
                "title": ["type": "string"],
                "done": ["type": "boolean"],
                "day": dayProperty,
                "time_limit_minutes": ["type": "integer", "minimum": 0],
                "remind_at": ["type": "string"]
            ], required: ["id"])
        ],
        [
            "name": "delete_task",
            "title": "Delete task",
            "description": "Permanently delete a task. Only use when the user explicitly asks.",
            "inputSchema": schema(["id": idProperty], required: ["id"]),
            "annotations": ["destructiveHint": true]
        ],
        [
            "name": "start_focus",
            "title": "Start focus session",
            "description": """
            Start the focus timer, optionally on a task. \
            minutes defaults to the task's time limit or 25; 0 starts a stopwatch.
            """,
            "inputSchema": schema([
                "task_id": idProperty,
                "minutes": ["type": "integer", "minimum": 0]
            ])
        ],
        ["name": "pause_focus", "title": "Pause focus", "description": "Pause the running focus session.", "inputSchema": schema()],
        ["name": "resume_focus", "title": "Resume focus", "description": "Resume a paused focus session.", "inputSchema": schema()],
        [
            "name": "stop_focus",
            "title": "Stop focus",
            "description": "End the current focus session. Time so far is kept in insights.",
            "inputSchema": schema()
        ],
        [
            "name": "focus_status",
            "title": "Focus status",
            "description": "Current focus timer state: idle, running, paused or finished, with time elapsed/remaining and the task.",
            "inputSchema": schema(),
            "annotations": ["readOnlyHint": true]
        ],
        [
            "name": "read_note",
            "title": "Read daily note",
            "description": "Read the user's daily notepad for a day.",
            "inputSchema": schema(["day": dayProperty]),
            "annotations": ["readOnlyHint": true]
        ],
        [
            "name": "append_note",
            "title": "Append to daily note",
            "description": "Append a line to the daily notepad. Never overwrites existing text.",
            "inputSchema": schema(["text": ["type": "string"], "day": dayProperty], required: ["text"])
        ],
        [
            "name": "get_insights",
            "title": "Get insights",
            "description": "Per-day planned tasks, completed tasks and focus minutes for recent days, plus totals and the current streak.",
            "inputSchema": schema(
                ["days": ["type": "integer", "minimum": 1, "maximum": 60, "description": "How many days back, default 7"]]
            ),
            "annotations": ["readOnlyHint": true]
        ],
        [
            "name": "todays_events",
            "title": "Today's events",
            "description": "Upcoming calendar events for today from the calendars the user chose to show (read-only).",
            "inputSchema": schema(),
            "annotations": ["readOnlyHint": true]
        ]
    ]
}
