import Foundation
import SwiftData

/// Plain Codable snapshot of everything the user owns, used for JSON backups.
struct BlackHoleBackup: Codable {
    struct Task: Codable {
        var id: UUID, title: String, dayKey: String, sortIndex: Int, isDone: Bool
        var completedAt: Date?, timeLimitSec: Int?, reminderAt: Date?, createdAt: Date
    }

    struct Session: Codable {
        var id: UUID, taskID: UUID?, startedAt: Date, endedAt: Date?, accumulatedSec: Double, targetSec: Int?
    }

    struct Note: Codable {
        var dayKey: String, text: String, updatedAt: Date
    }

    var version = 1
    var exportedAt = Date()
    var tasks: [Task]
    var sessions: [Session]
    var notes: [Note]
}

enum DataExporter {
    @MainActor
    static func makeBackup(context: ModelContext) throws -> Data {
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        let notes = try context.fetch(FetchDescriptor<DailyNote>())
        let backup = BlackHoleBackup(
            tasks: tasks.map { .init(
                id: $0.id,
                title: $0.title,
                dayKey: $0.dayKey,
                sortIndex: $0.sortIndex,
                isDone: $0.isDone,
                completedAt: $0.completedAt,
                timeLimitSec: $0.timeLimitSec,
                reminderAt: $0.reminderAt,
                createdAt: $0.createdAt
            ) },
            sessions: sessions.map { .init(
                id: $0.id,
                taskID: $0.taskID,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                accumulatedSec: $0.accumulatedSec,
                targetSec: $0.targetSec
            ) },
            notes: notes.map { .init(dayKey: $0.dayKey, text: $0.text, updatedAt: $0.updatedAt) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }
}
