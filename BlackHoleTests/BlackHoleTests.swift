import SwiftData
import XCTest
@testable import BlackHole

final class InsightsCalculatorTests: XCTestCase {
    private let cal = Calendar.current

    private func day(_ offset: Int, hour: Int = 10, from base: Date) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.date(bySettingHour: hour, minute: 0, second: 0, of: base)!)!
    }

    func testWeekAggregatesPlannedCompletedAndFocus() {
        let today = Date()
        let calc = InsightsCalculator(
            tasks: [
                .init(dayKey: DayKey.of(today), isDone: true, completedAt: day(0, from: today)),
                .init(dayKey: DayKey.of(today), isDone: false, completedAt: nil),
                .init(dayKey: DayKey.of(day(-1, from: today)), isDone: true, completedAt: day(-1, from: today)),
            ],
            sessions: [
                .init(startedAt: day(0, from: today), seconds: 1500),
                .init(startedAt: day(0, hour: 14, from: today), seconds: 600),
                .init(startedAt: day(-8, from: today), seconds: 9999),
            ])

        let week = calc.week(endingOn: today)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.dayKey, DayKey.of(today))
        XCTAssertEqual(week.last?.planned, 2)
        XCTAssertEqual(week.last?.completed, 1)
        XCTAssertEqual(week.last?.focusSeconds, 2100)
        XCTAssertEqual(week.reduce(0) { $0 + $1.focusSeconds }, 2100, "Sessions older than a week are excluded")
        XCTAssertEqual(week.filter(\.isActive).count, 2)
    }

    func testStreakSurvivesInactiveToday() {
        let today = Date()
        let calc = InsightsCalculator(tasks: [], sessions: [
            .init(startedAt: day(-1, from: today), seconds: 600),
            .init(startedAt: day(-2, from: today), seconds: 600),
            .init(startedAt: day(-4, from: today), seconds: 600),
        ])
        XCTAssertEqual(calc.currentStreak(today: today), 2)
    }

    func testDurationFormatting() {
        XCTAssertEqual(InsightsCalculator.formatDuration(59), "0m")
        XCTAssertEqual(InsightsCalculator.formatDuration(45 * 60), "45m")
        XCTAssertEqual(InsightsCalculator.formatDuration(120 * 60), "2h")
        XCTAssertEqual(InsightsCalculator.formatDuration(307 * 60), "5h 7m")
    }
}

@MainActor
final class FocusEngineTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var container: ModelContainer!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        container = try ModelContainer(for: TaskItem.self, FocusSession.self, DailyNote.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defaults = UserDefaults(suiteName: "FocusEngineTests-\(UUID())")
    }

    private func makeEngine() -> FocusEngine {
        FocusEngine(context: container.mainContext, defaults: defaults, now: { [unowned self] in self.now })
    }

    func testCountdownPauseResumeAndAddFive() {
        let engine = makeEngine()
        engine.start(targetSec: 25 * 60)
        now += 600
        XCTAssertEqual(engine.displaySeconds(at: now), 15 * 60)

        engine.pause()
        now += 3600
        XCTAssertEqual(engine.displaySeconds(at: now), 15 * 60, "Paused time doesn't count")

        engine.resume()
        now += 60
        engine.addFiveMinutes()
        XCTAssertEqual(engine.displaySeconds(at: now), 19 * 60)
    }

    func testFinishAndStopRecordsSession() throws {
        let engine = makeEngine()
        engine.start(targetSec: 60)
        now += 61
        engine.checkFinished()
        XCTAssertEqual(engine.phase, .finished)
        XCTAssertEqual(engine.displaySeconds(at: now), 0)

        engine.stop()
        XCTAssertEqual(engine.phase, .idle)
        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.accumulatedSec ?? 0, 60, accuracy: 0.001)
        XCTAssertNotNil(sessions.first?.endedAt)
    }

    func testStopwatchCountsUp() {
        let engine = makeEngine()
        engine.setPreset(minutes: nil)
        engine.start()
        now += 95
        XCTAssertNil(engine.remaining(at: now))
        XCTAssertEqual(engine.displaySeconds(at: now), 95)
    }

    func testRelaunchRestoresRunningSession() {
        let engine = makeEngine()
        engine.start(targetSec: 25 * 60)
        now += 300
        let relaunched = makeEngine()
        XCTAssertEqual(relaunched.phase, .running)
        XCTAssertEqual(relaunched.displaySeconds(at: now), 20 * 60)
    }
}

final class DotMatrixTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(DotMatrixText.format(seconds: 25 * 60), "25:00")
        XCTAssertEqual(DotMatrixText.format(seconds: 59), "00:59")
        XCTAssertEqual(DotMatrixText.format(seconds: 3725), "1:02:05")
    }
}
