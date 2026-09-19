import AppKit
import EventKit
import SwiftUI

/// Read-only access to today's upcoming events from every account in the macOS calendar database:
/// iCloud, Google (any number of accounts), Outlook/Exchange, CalDAV and subscribed calendars.
@MainActor
@Observable
final class CalendarService {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let calendarTitle: String
        let color: Color
        /// Zoom/Meet/Teams link from the invite, when there is one to join.
        let meetingURL: URL?

        func isHappening(at date: Date) -> Bool {
            start <= date && date < end
        }
    }

    struct CalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let color: Color
        var isVisible: Bool
    }

    /// Calendars grouped by the account they belong to, e.g. "iCloud", "work@company.com".
    struct Account: Identifiable, Equatable {
        let id: String
        let title: String
        var calendars: [CalendarInfo]
    }

    enum Status { case notDetermined, connected, denied }

    private(set) var status: Status = .notDetermined
    private(set) var events: [Event] = []
    private(set) var accounts: [Account] = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var refreshTimer: Timer?
    /// Hidden rather than visible IDs, so calendars added later show up by default.
    private static let hiddenKey = "calendar.hiddenCalendarIDs"
    @ObservationIgnored private var hiddenIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.hiddenKey) }
    }

    init() {
        updateStatus()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSourcesAndRefresh() }
        }
        // Drop events as they end and flip "Happening now" without waiting for store changes.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        reloadSourcesAndRefresh()
    }

    func connect() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            reloadSourcesAndRefresh()
        }
    }

    func setVisible(_ visible: Bool, calendarID: String) {
        var hidden = hiddenIDs
        if visible {
            hidden.remove(calendarID)
        } else {
            hidden.insert(calendarID)
        }
        hiddenIDs = hidden
        loadAccounts()
        refresh()
    }

    /// Opens System Settings → Internet Accounts, where Google, Outlook and other accounts are added.
    func openInternetAccounts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
    }

    func reloadSourcesAndRefresh() {
        store.refreshSourcesIfNecessary()
        loadAccounts()
        refresh()
    }

    func refresh() {
        guard !isShowingDemoMeeting else { return }
        updateStatus()
        guard status == .connected else {
            events = []
            return
        }
        let hidden = hiddenIDs
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            events = []
            return
        }
        let now = Date()
        let cal = Calendar.current
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let predicate = store.predicateForEvents(withStart: cal.startOfDay(for: now), end: endOfDay, calendars: calendars)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { e in
                Event(
                    id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)",
                    title: e.title ?? "Untitled",
                    start: e.startDate,
                    end: e.endDate,
                    isAllDay: e.isAllDay,
                    calendarTitle: e.calendar?.title ?? "",
                    color: e.calendar?.cgColor.map { Color(cgColor: $0) } ?? Palette.ink,
                    meetingURL: Self.meetingLink(in: e)
                )
            }
    }

    /// How soon a meeting has to be before the notch starts counting down to it.
    static let meetingLeadTime: TimeInterval = 5 * 60

    /// How long a meeting keeps the notch after it has started. Past this you have either joined or
    /// decided not to, and a two-hour workshop shouldn't sit in the notch all morning.
    static let meetingGracePeriod: TimeInterval = 10 * 60

    @ObservationIgnored private var dismissedMeetingIDs: Set<String> = []

    /// Stops showing this meeting in the notch, until the app restarts.
    func dismissMeeting(id: String) {
        dismissedMeetingIDs.insert(id)
        // `events` is unchanged, so nudge observers to drop the island.
        events = events
    }

    /// The meeting worth showing in the notch right now: one starting within the lead time, or one
    /// that started moments ago. All-day events never count.
    func imminentMeeting(at date: Date = .now) -> Event? {
        events.first { event in
            guard !event.isAllDay, event.end > date, !dismissedMeetingIDs.contains(event.id) else { return false }
            let untilStart = event.start.timeIntervalSince(date)
            return untilStart <= Self.meetingLeadTime && untilStart > -Self.meetingGracePeriod
        }
    }

    @ObservationIgnored private var isShowingDemoMeeting = false

    /// Sample meeting for `-demoData YES -demoMeeting YES`, so the notch countdown can be seen and
    /// captured without waiting on a real invite. Ignored outside demo mode.
    func seedDemoMeeting() {
        guard AppServices.isDemo else { return }
        isShowingDemoMeeting = true
        status = .connected
        // `-demoMeetingIn <seconds>` moves the sample meeting and `-demoMeetingStarted YES` puts it
        // just behind us, so both the countdown and the "Now" state can be captured on demand.
        // (A negative `-demoMeetingIn` can't work: macOS reads a leading dash as the next key.)
        let startsIn = UserDefaults.standard.bool(forKey: "demoMeetingStarted")
            ? -45
            : UserDefaults.standard.object(forKey: "demoMeetingIn") as? Int ?? 200
        events = [Event(
            id: "demo-meeting",
            title: "Design review",
            start: .now.addingTimeInterval(TimeInterval(startsIn)),
            end: .now.addingTimeInterval(TimeInterval(startsIn) + 30 * 60),
            isAllDay: false,
            calendarTitle: "Work",
            color: Color(hex: 0x62B6FF),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )]
    }

    #if DEBUG
        /// Lets tests drive the notch without a real calendar database behind it.
        func setEventsForTesting(_ events: [Event]) {
            self.events = events
        }
    #endif

    /// Video links live in different fields depending on who sent the invite: Google Calendar fills
    /// in the URL, Outlook buries it in the body, and people paste them into the location by hand.
    static func meetingLink(in event: EKEvent) -> URL? {
        if let url = event.url, isMeetingLink(url) {
            return url
        }
        for text in [event.location, event.notes].compactMap({ $0 }) {
            if let found = firstMeetingLink(in: text) {
                return found
            }
        }
        return nil
    }

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "meet.jit.si", "around.co", "slack.com", "discord.gg"
    ]

    private static func isMeetingLink(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func firstMeetingLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, isMeetingLink(url) {
                return url
            }
        }
        return nil
    }

    private func loadAccounts() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            accounts = []
            return
        }
        let hidden = hiddenIDs
        let grouped = Dictionary(grouping: store.calendars(for: .event)) { $0.source?.sourceIdentifier ?? "local" }
        accounts = grouped.map { sourceID, calendars in
            let source = calendars.first?.source
            return Account(
                id: sourceID,
                title: Self.accountTitle(source),
                calendars: calendars
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    .map { CalendarInfo(
                        id: $0.calendarIdentifier,
                        title: $0.title,
                        color: Color(cgColor: $0.cgColor),
                        isVisible: !hidden.contains($0.calendarIdentifier)
                    ) }
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func accountTitle(_ source: EKSource?) -> String {
        guard let source else { return "On My Mac" }
        switch source.sourceType {
        case .local: return "On My Mac"
        case .subscribed: return "Subscribed"
        case .birthdays: return "Other"
        default: return source.title
        }
    }

    private func updateStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: status = .connected
        case .notDetermined: status = .notDetermined
        default: status = .denied
        }
    }
}
