import AppKit
import SwiftData
import SwiftUI

/// Long-lived app state shared by the notch panel, the dashboard window and the menu bar item.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let dayClock = DayClock()
    let focus: FocusEngine
    let calendar = CalendarService()
    let notch = NotchViewModel()
    let mascot = MascotMoodCenter()
    let taskActions: TaskActions
    /// Local MCP endpoint for AI assistants. Not started in demo mode.
    private(set) var mcp: MCPServer!

    /// Our own file under Application Support. SwiftData's default `default.store` is shared by every
    /// unsandboxed app that doesn't pick a location.
    static var storeURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Black Hole", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "BlackHole.store")
    }

    /// Launch with `-demoData YES` to use a throwaway in-memory store filled with sample data
    /// (for screenshots and trying things out without touching your real data).
    static let isDemo = UserDefaults.standard.bool(forKey: "demoData")

    private init() {
        do {
            let config = Self.isDemo ? ModelConfiguration(isStoredInMemoryOnly: true) : ModelConfiguration(url: Self.storeURL)
            container = try ModelContainer(for: TaskItem.self, FocusSession.self, DailyNote.self, configurations: config)
        } catch {
            fatalError("Could not open the Black Hole database: \(error)")
        }
        if Self.isDemo { DemoData.seed(into: container.mainContext) }
        focus = FocusEngine(context: container.mainContext,
                            defaults: Self.isDemo ? UserDefaults(suiteName: "app.getblackhole.demo")! : .standard)
        taskActions = TaskActions(context: container.mainContext, focus: focus)
        taskActions.onTaskCompleted = { [mascot] in mascot.celebrate() }
        let notifyFinish = focus.onFinish
        focus.onFinish = { [mascot] taskID in
            notifyFinish?(taskID)
            mascot.celebrate()
        }
        notch.onExpansionVisit = { [mascot] in mascot.poke() }
        dayClock.onDayChange = { [weak self] in self?.taskActions.rollOverUnfinishedTasks() }
        if !Self.isDemo { taskActions.rollOverUnfinishedTasks() }
        let router = MCPRouter(context: container.mainContext, tasks: taskActions, focus: focus, calendar: calendar)
        mcp = MCPServer(router: router, allowStart: !Self.isDemo)
    }
}

/// Publishes the current day key and fires when the calendar day changes.
@MainActor
@Observable
final class DayClock {
    private(set) var today = DayKey.today
    @ObservationIgnored var onDayChange: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let key = DayKey.today
        guard key != today else { return }
        today = key
        onDayChange?()
    }
}

extension View {
    /// Injects everything a Black Hole view may read from the environment.
    @MainActor
    func blackHoleEnvironment() -> some View {
        blackHoleEnvironment(.shared)
    }

    func blackHoleEnvironment(_ services: AppServices) -> some View {
        self
            .modelContainer(services.container)
            .environment(services.dayClock)
            .environment(services.focus)
            .environment(services.calendar)
            .environment(services.notch)
            .environment(services.taskActions)
            .environment(services.mascot)
            .environment(services.mcp)
    }
}
