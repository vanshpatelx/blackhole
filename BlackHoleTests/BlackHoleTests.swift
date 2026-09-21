@testable import BlackHole
import EventKit
import SwiftData
import XCTest

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
                .init(dayKey: DayKey.of(day(-1, from: today)), isDone: true, completedAt: day(-1, from: today))
            ],
            sessions: [
                .init(startedAt: day(0, from: today), seconds: 1500),
                .init(startedAt: day(0, hour: 14, from: today), seconds: 600),
                .init(startedAt: day(-8, from: today), seconds: 9999)
            ]
        )

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
            .init(startedAt: day(-4, from: today), seconds: 600)
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
        container = try ModelContainer(
            for: TaskItem.self,
            FocusSession.self,
            DailyNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        defaults = UserDefaults(suiteName: "FocusEngineTests-\(UUID())")
    }

    private func makeEngine() -> FocusEngine {
        FocusEngine(context: container.mainContext, defaults: defaults, now: { [unowned self] in now })
    }

    func testAFinishedTimerDoesNotComeBackOnRelaunch() {
        let engine = makeEngine()
        engine.start(targetSec: 60)
        now += 61
        engine.checkFinished()
        XCTAssertEqual(engine.phase, .finished)
        XCTAssertTrue(engine.isActive, "It stays in the notch while you're still looking at it")

        // Quitting and reopening: the chime happened hours ago, so the notch should be empty.
        now += 3600
        let relaunched = makeEngine()
        XCTAssertEqual(relaunched.phase, .idle)
        XCTAssertFalse(relaunched.isActive)

        // The session still counts towards Insights, ended when it ran out rather than at relaunch.
        let sessions = try? container.mainContext.fetch(FetchDescriptor<FocusSession>())
        let session = try? XCTUnwrap(sessions?.first)
        XCTAssertEqual(session?.accumulatedSec, 60)
        XCTAssertEqual(session?.endedAt, session?.startedAt.addingTimeInterval(60))
    }

    func testAPausedTimerIsStillThereAfterRelaunch() {
        let engine = makeEngine()
        engine.start(targetSec: 25 * 60)
        now += 300
        engine.pause()

        let relaunched = makeEngine()
        XCTAssertEqual(relaunched.phase, .paused, "A paused timer is deliberate; keep it")
        XCTAssertEqual(relaunched.displaySeconds(at: now), 20 * 60)
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

@MainActor
final class MCPRouterTests: XCTestCase {
    private var container: ModelContainer!
    private var router: MCPRouter!
    private var tasks: TaskActions!

    override func setUp() async throws {
        container = try ModelContainer(
            for: TaskItem.self,
            FocusSession.self,
            DailyNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let focus = FocusEngine(context: container.mainContext, defaults: UserDefaults(suiteName: "MCPRouterTests-\(UUID())")!)
        tasks = TaskActions(context: container.mainContext, focus: focus)
        router = MCPRouter(context: container.mainContext, tasks: tasks, focus: focus, calendar: nil)
    }

    private func call(_ method: String, _ params: [String: Any] = [:], id: Int = 1) throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let reply = try XCTUnwrap(router.handle(body))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
    }

    private func tool(_ name: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        let reply = try call("tools/call", ["name": name, "arguments": args])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false, "\(name) failed: \(result)")
        return try XCTUnwrap(result["structuredContent"] as? [String: Any])
    }

    func testInitializeNegotiatesVersion() throws {
        let result = try XCTUnwrap(try call("initialize", ["protocolVersion": "2025-03-26"])["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        let unknown = try XCTUnwrap(try call("initialize", ["protocolVersion": "1999-01-01"])["result"] as? [String: Any])
        XCTAssertEqual(unknown["protocolVersion"] as? String, MCPRouter.latestProtocolVersion)
    }

    func testNotificationsGetNoReply() throws {
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(router.handle(body))
    }

    func testToolsListHasTheCatalog() throws {
        let result = try XCTUnwrap(try call("tools/list")["result"] as? [String: Any])
        let names = (result["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        XCTAssertTrue(names.contains("add_task"))
        XCTAssertTrue(names.contains("start_focus"))
        XCTAssertEqual(Set(names).count, names.count, "Tool names must be unique")
    }

    func testAddUpdateListAndDeleteTask() throws {
        let added = try XCTUnwrap(try tool("add_task", ["title": "Write docs", "time_limit_minutes": 30])["task"] as? [String: Any])
        let id = try XCTUnwrap(added["id"] as? String)
        XCTAssertEqual(added["time_limit_minutes"] as? Int, 30)

        _ = try tool("update_task", ["id": id, "done": true])
        let listed = try XCTUnwrap(try tool("list_tasks")["tasks"] as? [[String: Any]])
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?["done"] as? Bool, true)

        _ = try tool("update_task", ["id": id, "day": "tomorrow"])
        XCTAssertEqual(try (tool("list_tasks")["tasks"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(try (tool("list_tasks", ["day": "tomorrow"])["tasks"] as? [[String: Any]])?.count, 1)

        _ = try tool("delete_task", ["id": id])
        XCTAssertEqual(try (tool("list_tasks", ["day": "tomorrow"])["tasks"] as? [[String: Any]])?.count, 0)
    }

    func testFocusLifecycle() throws {
        XCTAssertEqual(try tool("start_focus", ["minutes": 10])["state"] as? String, "running")
        XCTAssertEqual(try tool("pause_focus")["state"] as? String, "paused")
        XCTAssertEqual(try tool("focus_status")["mode"] as? String, "countdown")
        XCTAssertEqual(try tool("stop_focus")["state"] as? String, "idle")
        XCTAssertEqual(try tool("start_focus", ["minutes": 0])["mode"] as? String, "stopwatch")
    }

    func testFocusOnATaskCountsUpUnlessItHasATimeLimit() throws {
        let plain = try XCTUnwrap(try tool("add_task", ["title": "No limit"])["task"] as? [String: Any])
        let started = try tool("start_focus", ["task_id": XCTUnwrap(plain["id"] as? String)])
        XCTAssertEqual(started["mode"] as? String, "stopwatch")
        _ = try tool("stop_focus")

        let limited = try XCTUnwrap(try tool("add_task", ["title": "Has limit", "time_limit_minutes": 45])["task"] as? [String: Any])
        let countdown = try tool("start_focus", ["task_id": XCTUnwrap(limited["id"] as? String)])
        XCTAssertEqual(countdown["mode"] as? String, "countdown")
        XCTAssertEqual(countdown["remaining_seconds"] as? Int, 45 * 60)
        _ = try tool("stop_focus")

        // The timer card on its own still offers the usual 25-minute countdown.
        XCTAssertEqual(try tool("start_focus")["mode"] as? String, "countdown")
    }

    func testAppendNoteNeverOverwrites() throws {
        _ = try tool("append_note", ["text": "first"])
        let text = try tool("append_note", ["text": "second"])["text"] as? String
        XCTAssertEqual(text, "first\nsecond")
    }

    func testBadInputIsAToolErrorNotACrash() throws {
        let reply = try call("tools/call", ["name": "update_task", "arguments": ["id": "not-a-uuid"]])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)

        let unknown = try call("tools/call", ["name": "launch_rockets"])
        XCTAssertNotNil(unknown["error"])
        XCTAssertNotNil(try call("does/not/exist")["error"])
    }
}

final class HTTPRequestParsingTests: XCTestCase {
    func testWaitsForFullBody() {
        let head = "POST /mcp HTTP/1.1\r\nContent-Length: 10\r\nAuthorization: Bearer abc\r\n\r\n"
        XCTAssertNil(HTTPRequest(Data((head + "12345").utf8)))
        let request = HTTPRequest(Data((head + "1234567890").utf8))
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "/mcp")
        XCTAssertEqual(request?.headers["authorization"], "Bearer abc")
        XCTAssertEqual(request?.body.count, 10)
    }
}

final class HTTPKeepAliveTests: XCTestCase {
    func testKeepAliveByDefaultAndPipelinedBytesArePreserved() throws {
        let first = "POST /mcp HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}"
        let second = "POST /mcp HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
        let request = try XCTUnwrap(HTTPRequest(Data((first + second).utf8)))
        XCTAssertTrue(request.wantsKeepAlive)
        XCTAssertEqual(request.byteCount, first.utf8.count, "Only the first request's bytes are consumed")

        let closing = try XCTUnwrap(HTTPRequest(Data("POST /mcp HTTP/1.1\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)))
        XCTAssertFalse(closing.wantsKeepAlive)
    }

    func testResponseHeaderReflectsKeepAlive() {
        var response = HTTPResponse(status: 200, body: Data("hi".utf8))
        response.keepAlive = true
        XCTAssertTrue(String(decoding: response.serialized(), as: UTF8.self).contains("Connection: keep-alive"))
        response.keepAlive = false
        XCTAssertTrue(String(decoding: response.serialized(), as: UTF8.self).contains("Connection: close"))
    }
}

final class LoopbackGuardTests: XCTestCase {
    func testOnlyLoopbackAuthoritiesAreAccepted() {
        XCTAssertTrue(MCPServer.isLoopbackAuthority("127.0.0.1:52321", port: 52321))
        XCTAssertTrue(MCPServer.isLoopbackAuthority("LocalHost:52321", port: 52321))
        // A name an attacker can point at 127.0.0.1 must not pass, which is what stops DNS rebinding.
        XCTAssertFalse(MCPServer.isLoopbackAuthority("localhost.attacker.com:52321", port: 52321))
        XCTAssertFalse(MCPServer.isLoopbackAuthority("127.0.0.1.attacker.com:52321", port: 52321))
        XCTAssertFalse(MCPServer.isLoopbackAuthority("127.0.0.1:1234", port: 52321))
        XCTAssertFalse(MCPServer.isLoopbackAuthority(nil, port: 52321))
    }

    func testOriginsMustMatchExactly() {
        let allowed = MCPServer.loopbackOrigins(port: 52321)
        XCTAssertTrue(allowed.contains("http://127.0.0.1:52321"))
        XCTAssertFalse(allowed.contains("http://localhost.attacker.com"))
        XCTAssertFalse(allowed.contains("http://127.0.0.1:52321.attacker.com"))
    }
}

@MainActor
final class MeetingIslandTests: XCTestCase {
    private func event(startingIn seconds: TimeInterval, lasting: TimeInterval = 1800, allDay: Bool = false) -> CalendarService.Event {
        CalendarService.Event(
            id: UUID().uuidString,
            title: "Design review",
            start: .now.addingTimeInterval(seconds),
            end: .now.addingTimeInterval(seconds + lasting),
            isAllDay: allDay,
            calendarTitle: "Work",
            color: .blue,
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
    }

    func testMeetingLinksAreFoundWhereverTheInviteHidesThem() {
        let invite = EKEvent(eventStore: EKEventStore())
        invite.notes = "Dial in, or use https://zoom.us/j/1234567890 to join"
        XCTAssertEqual(CalendarService.meetingLink(in: invite)?.host(), "zoom.us")

        invite.notes = nil
        invite.location = "https://teams.microsoft.com/l/meetup-join/xyz"
        XCTAssertEqual(CalendarService.meetingLink(in: invite)?.host(), "teams.microsoft.com")

        // A room name or an unrelated link is not something you can join.
        invite.location = "Meeting room 3, second floor"
        invite.notes = "Agenda: https://notion.so/some-doc"
        XCTAssertNil(CalendarService.meetingLink(in: invite))
    }

    func testOnlyMeetingsInsideTheWindowTakeTheNotch() {
        let service = CalendarService()
        // Far out, so the notch stays empty while you work.
        service.setEventsForTesting([event(startingIn: 30 * 60)])
        XCTAssertNil(service.imminentMeeting())

        // Inside the lead time.
        service.setEventsForTesting([event(startingIn: 4 * 60)])
        XCTAssertNotNil(service.imminentMeeting())

        // Started a moment ago: still worth showing, you may not have joined yet.
        service.setEventsForTesting([event(startingIn: -2 * 60)])
        XCTAssertNotNil(service.imminentMeeting())

        // Long underway: you joined or you skipped it, either way stop holding the notch.
        service.setEventsForTesting([event(startingIn: -30 * 60, lasting: 7200)])
        XCTAssertNil(service.imminentMeeting())

        // All-day events are not meetings to join.
        service.setEventsForTesting([event(startingIn: 60, allDay: true)])
        XCTAssertNil(service.imminentMeeting())
    }

    func testDismissingAMeetingClearsTheNotch() {
        let service = CalendarService()
        let meeting = event(startingIn: 60)
        service.setEventsForTesting([meeting])
        XCTAssertNotNil(service.imminentMeeting())
        service.dismissMeeting(id: meeting.id)
        XCTAssertNil(service.imminentMeeting())
    }
}

final class AllowedHostTests: XCTestCase {
    func testTailnetAndTunnelHostsAreNotRebinding() {
        // Rebinding needs DNS the attacker hands out. They can't be given a *.ts.net or a
        // *.getblackhole.app name, so recognising those hosts doesn't reopen the hole that
        // prefix-matching did — these still have to be rejected.
        XCTAssertFalse(MCPServer.isLoopbackAuthority("machine.tailnet.ts.net", port: 52321))
        XCTAssertFalse(MCPServer.isLoopbackAuthority("mcp-8957cee3.getblackhole.app", port: 52321))
        XCTAssertFalse(MCPServer.isLoopbackAuthority("localhost.attacker.com:52321", port: 52321))
    }
}

final class QuickParseTests: XCTestCase {
    private let cal = Calendar.current
    /// A Wednesday, 10:00.
    private lazy var now = cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 10))!

    private func parse(_ s: String) -> QuickParse.Result? {
        QuickParse.parse(s, now: now, calendar: cal)
    }

    func testPlainTextIsJustATaskForToday() {
        let r = parse("write the launch tweet")
        XCTAssertEqual(r?.title, "write the launch tweet")
        XCTAssertEqual(r?.dayKey, "2026-09-16")
        XCTAssertNil(r?.reminder)
    }

    func testTomorrowAndTimesComeOutOfTheTitle() throws {
        XCTAssertEqual(parse("ship the dmg tomorrow")?.dayKey, "2026-09-17")
        XCTAssertEqual(parse("ship the dmg tomorrow")?.title, "ship the dmg")

        let r = parse("call mika tomorrow at 3pm")
        XCTAssertEqual(r?.title, "call mika")
        XCTAssertEqual(r?.dayKey, "2026-09-17")
        XCTAssertEqual(try cal.component(.hour, from: XCTUnwrap(r?.reminder)), 15)
    }

    func testWeekdayNamesLandOnTheNextOne() {
        // Wednesday → Friday is two days out; naming today's weekday means next week.
        XCTAssertEqual(parse("review prs friday")?.dayKey, "2026-09-18")
        XCTAssertEqual(parse("review prs wednesday")?.dayKey, "2026-09-23")
        XCTAssertEqual(parse("review prs fri")?.dayKey, "2026-09-18")
    }

    func testATimeAlreadyPastMeansTomorrow() {
        // It's 10:00, so "9am" can only sensibly mean tomorrow morning.
        XCTAssertEqual(parse("standup 9am")?.dayKey, "2026-09-17")
        // But naming the day is explicit, so leave it alone.
        XCTAssertEqual(parse("standup today 9am")?.dayKey, "2026-09-16")
    }

    func testWordsInsideTheTitleAreLeftAlone() {
        // Only trailing words are eaten, so a task can still be about a day.
        XCTAssertEqual(parse("plan tomorrow's standup")?.title, "plan tomorrow's standup")
        XCTAssertEqual(parse("buy 2 tickets")?.title, "buy 2 tickets")
        XCTAssertNil(parse("buy 2 tickets")?.reminder, "A bare number isn't a time")
    }

    func testNothingUsableIsNothing() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("   "))
        XCTAssertNil(parse("tomorrow"), "A day with no task isn't a task")
    }
}
