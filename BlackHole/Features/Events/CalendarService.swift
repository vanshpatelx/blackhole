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

        func isHappening(at date: Date) -> Bool { start <= date && date < end }
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
        if visible { hidden.remove(calendarID) } else { hidden.insert(calendarID) }
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
                Event(id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)",
                      title: e.title ?? "Untitled", start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                      calendarTitle: e.calendar?.title ?? "",
                      color: e.calendar?.cgColor.map { Color(cgColor: $0) } ?? Palette.ink)
            }
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
                    .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title,
                                        color: Color(cgColor: $0.cgColor), isVisible: !hidden.contains($0.calendarIdentifier)) })
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
