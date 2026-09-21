import Foundation

/// How often a task comes back.
///
/// Deliberately small: these three cover nearly everything people actually repeat, and each one can
/// be explained in a single word in the menu. Anything more elaborate belongs in a calendar.
enum Recurrence: String, CaseIterable, Identifiable, Codable {
    case daily
    case weekdays
    case weekly

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        }
    }

    /// Short form for the badge on a task row, where there is no space for a sentence.
    var badge: String {
        switch self {
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        }
    }

    /// Phrases someone might type into quick capture.
    static func spoken(_ text: String) -> Recurrence? {
        switch text {
        case "every day", "everyday", "daily": .daily
        case "every weekday", "weekdays", "every weekdays": .weekdays
        case "every week", "weekly": .weekly
        default: nil
        }
    }

    /// Whether an occurrence anchored on `anchor` should also appear on `day`.
    func occurs(on day: Date, anchor: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        let from = calendar.startOfDay(for: anchor)
        guard start > from else { return false }
        switch self {
        case .daily:
            return true
        case .weekdays:
            // Monday to Friday, deliberately, rather than `isDateInWeekend`: that follows the
            // system locale, so "every weekday" would quietly mean something different depending on
            // where the Mac thinks it is. People setting this mean the working week they picture.
            let weekday = calendar.component(.weekday, from: start)
            return weekday != 1 && weekday != 7
        case .weekly:
            return calendar.component(.weekday, from: start) == calendar.component(.weekday, from: from)
        }
    }
}
