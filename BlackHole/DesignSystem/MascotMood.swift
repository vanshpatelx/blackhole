import Foundation

/// Decides how the mascot feels right now from what's happening in the app.
@MainActor
@Observable
final class MascotMoodCenter {
    /// Bumps each time the mascot celebrates, so views can run a one-shot bounce.
    private(set) var celebrationCount = 0
    private(set) var isCelebrating = false
    private(set) var isSleepy = false

    @ObservationIgnored private var celebrateWork: DispatchWorkItem?
    @ObservationIgnored private var sleepWork: DispatchWorkItem?
    /// How long without a visit before the mascot dozes off.
    static let sleepAfter: TimeInterval = 90

    init() {
        poke()
    }

    func celebrate() {
        poke()
        celebrationCount += 1
        isCelebrating = true
        celebrateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.isCelebrating = false }
        }
        celebrateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    /// Any visit (hover, opening the workspace, finishing a task) wakes it up and restarts the nap timer.
    func poke() {
        if isSleepy {
            isSleepy = false
        }
        sleepWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.isSleepy = true }
        }
        sleepWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sleepAfter, execute: work)
    }

    func mood(focusRunning: Bool) -> Mascot.Mood {
        if isCelebrating {
            return .happy
        }
        if focusRunning {
            return .focused
        }
        if isSleepy {
            return .sleepy
        }
        return .normal
    }
}
