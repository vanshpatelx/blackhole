import AppKit
import SwiftData

/// Drives the single active focus session. Time is derived from dates, never from tick counts,
/// so the display stays correct across UI stalls, relaunches and sleep.
@MainActor
@Observable
final class FocusEngine {
    enum Phase: String, Codable { case idle, running, paused, finished }

    private(set) var phase: Phase = .idle
    /// Countdown length for the current session; `nil` means stopwatch.
    private(set) var targetSec: Int?
    /// Length used for the next session started from the timer card.
    private(set) var presetSec: Int? = 25 * 60
    private(set) var taskID: UUID?
    private(set) var accumulated: Double = 0
    private(set) var resumedAt: Date?

    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var finishTimer: Timer?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onFinish: ((UUID?) -> Void)?

    init(context: ModelContext, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.defaults = defaults
        self.now = now
        restore()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
    }

    // MARK: Reading

    var isActive: Bool { phase == .running || phase == .paused || phase == .finished }

    func elapsed(at date: Date) -> Double {
        accumulated + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Seconds left for countdowns, `nil` for stopwatches.
    func remaining(at date: Date) -> Double? {
        targetSec.map { max(0, Double($0) - elapsed(at: date)) }
    }

    /// Value shown on the dot-matrix display.
    func displaySeconds(at date: Date) -> Int {
        switch phase {
        case .idle: return presetSec ?? 0
        default:
            if let r = remaining(at: date) { return Int(r.rounded(.up)) }
            return Int(elapsed(at: date))
        }
    }

    func progress(at date: Date) -> Double {
        guard let t = targetSec, t > 0, phase != .idle else { return 0 }
        return min(1, elapsed(at: date) / Double(t))
    }

    // MARK: Commands

    func setPreset(minutes: Int?) {
        presetSec = minutes.map { $0 * 60 }
        persist()
    }

    func start(taskID: UUID? = nil, targetSec: Int? = nil) {
        if isActive { endSession() }
        let target = targetSec ?? presetSec
        let session = FocusSession(taskID: taskID, targetSec: target)
        context.insert(session)
        sessionID = session.id
        self.taskID = taskID
        self.targetSec = target
        accumulated = 0
        resumedAt = now()
        phase = .running
        scheduleFinish()
        save()
    }

    func pause() {
        guard phase == .running, let r = resumedAt else { return }
        accumulated += max(0, now().timeIntervalSince(r))
        resumedAt = nil
        phase = .paused
        finishTimer?.invalidate()
        save()
    }

    func resume() {
        guard phase == .paused else { return }
        resumedAt = now()
        phase = .running
        scheduleFinish()
        save()
    }

    func toggle() {
        switch phase {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        case .finished: addFiveMinutes()
        }
    }

    func addFiveMinutes() {
        guard isActive else { return }
        targetSec = (targetSec ?? Int(elapsed(at: now()))) + 5 * 60
        if phase == .finished {
            resumedAt = now()
            phase = .running
        }
        scheduleFinish()
        save()
    }

    /// Ends the session and returns to idle. Returns the task the session was attached to.
    @discardableResult
    func stop() -> UUID? {
        let id = taskID
        endSession()
        return id
    }

    // MARK: Internals

    private func scheduleFinish() {
        finishTimer?.invalidate()
        guard phase == .running, let left = remaining(at: now()) else { return }
        finishTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, left), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFinished() }
        }
    }

    func checkFinished() {
        guard phase == .running, let left = remaining(at: now()), left <= 0.01 else { return }
        accumulated = Double(targetSec ?? 0)
        resumedAt = nil
        phase = .finished
        save()
        NSSound(named: "Glass")?.play()
        onFinish?(taskID)
    }

    private func endSession() {
        if phase == .running, let r = resumedAt { accumulated += max(0, now().timeIntervalSince(r)) }
        if let session = currentSession() {
            session.accumulatedSec = accumulated
            session.endedAt = now()
        }
        finishTimer?.invalidate()
        sessionID = nil
        taskID = nil
        targetSec = nil
        accumulated = 0
        resumedAt = nil
        phase = .idle
        save()
    }

    private func currentSession() -> FocusSession? {
        guard let id = sessionID else { return nil }
        var d = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func save() {
        if let session = currentSession() {
            session.accumulatedSec = elapsed(at: now())
        }
        try? context.save()
        persist()
    }

    // Snapshot so a relaunch mid-session picks up where it left off.
    private struct Snapshot: Codable {
        var phase: Phase, targetSec: Int?, presetSec: Int?, taskID: UUID?, accumulated: Double, resumedAt: Date?, sessionID: UUID?
    }
    private static let snapshotKey = "focusEngine.snapshot"

    private func persist() {
        let s = Snapshot(phase: phase, targetSec: targetSec, presetSec: presetSec, taskID: taskID,
                         accumulated: accumulated, resumedAt: resumedAt, sessionID: sessionID)
        defaults.set(try? JSONEncoder().encode(s), forKey: Self.snapshotKey)
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.snapshotKey),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        presetSec = s.presetSec
        guard s.phase != .idle else { return }
        phase = s.phase
        targetSec = s.targetSec
        taskID = s.taskID
        accumulated = s.accumulated
        resumedAt = s.resumedAt
        sessionID = s.sessionID
        if phase == .running {
            scheduleFinish()
            checkFinished()
        }
    }
}
