import AppKit
import SwiftData
import SwiftUI

struct EventsCard: View {
    @Environment(CalendarService.self) private var calendar
    @Query(filter: #Predicate<TaskItem> { $0.reminderAt != nil && $0.isDone == false }, sort: \TaskItem.createdAt)
    private var remindedTasks: [TaskItem]

    var body: some View {
        Card(tint: Palette.events) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(icon: "calendar", title: "Events") {
                    EllipsisMenu {
                        Button("Refresh") { calendar.refresh() }
                        Button("Open Calendar") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
                        if calendar.status == .denied {
                            Button("Calendar Privacy Settings…") { openPrivacySettings() }
                        }
                    }
                }

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 7) {
                            let reminders = upcomingReminders(now: context.date)
                            if !reminders.isEmpty {
                                SectionLabel(title: "Reminders")
                                ForEach(reminders) { task in
                                    EventTile(
                                        title: task.title,
                                        subtitle: task.reminderAt!.formatted(.dateTime.day().month(.abbreviated).hour().minute()),
                                        highlight: nil
                                    )
                                }
                                DottedDivider().padding(.vertical, 3)
                            }

                            SectionLabel(title: "Today") {
                                Text(context.date, format: .dateTime.weekday(.abbreviated).day())
                            }
                            eventsSection(now: context.date, compact: !reminders.isEmpty)
                        }
                    }
                }

                CardFooter {
                    switch calendar.status {
                    case .connected: Label("Connected", systemImage: "checkmark.circle").labelStyle(CompactLabelStyle())
                    case .denied: Label("No access", systemImage: "exclamationmark.circle").labelStyle(CompactLabelStyle())
                    case .notDetermined: Label("Not set up", systemImage: "circle.dashed").labelStyle(CompactLabelStyle())
                    }
                } trailing: {
                    IconButton(systemName: "arrow.clockwise", size: 20, help: "Refresh") { calendar.refresh() }
                }
            }
        }
    }

    @ViewBuilder
    private func eventsSection(now: Date, compact: Bool) -> some View {
        switch calendar.status {
        case .notDetermined:
            VStack(alignment: .leading, spacing: 6) {
                if !compact {
                    Text("See today's events from Apple, Google and Outlook calendars.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Button("Connect") { calendar.connect() }
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
            }
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text("Calendar access is off.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.inkSecondary)
                Button("Allow") { openPrivacySettings() }
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
            }
        case .connected:
            if calendar.events.isEmpty {
                Text(calendar.accounts.isEmpty ? "No calendars yet. Add Google or Outlook in Settings." : "No more events today.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(calendar.events) { event in
                    EventTile(
                        title: event.title,
                        subtitle: event
                            .isAllDay ? "All day" :
                            event.start.formatted(date: .omitted, time: .shortened)
                            + " – " + event.end.formatted(date: .omitted, time: .shortened),
                        highlight: event.isHappening(at: now) && !event.isAllDay ? "Happening now" : nil,
                        color: event.color
                    )
                }
            }
        }
    }

    private func upcomingReminders(now: Date) -> [TaskItem] {
        remindedTasks
            .filter { ($0.reminderAt ?? .distantPast) > now }
            .sorted { $0.reminderAt! < $1.reminderAt! }
    }

    private func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}

private struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.3)
            Spacer()
            trailing.font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(Palette.inkSecondary)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

private struct EventTile: View {
    let title: String
    let subtitle: String
    let highlight: String?
    var color: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            if let highlight {
                Text(highlight)
                    .font(.system(size: 10.5, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, color == nil ? 9 : 13)
        .padding(.trailing, 9)
        .padding(.vertical, 8)
        .overlay(alignment: .leading) {
            if let color {
                // Calendar color, so events from different accounts are easy to tell apart.
                Capsule().fill(color).frame(width: 3.5).padding(.vertical, 8).padding(.leading, 5)
            }
        }
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.wellStrong))
    }
}
