import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    enum Metric: Hashable { case tasks, focus }

    @Query private var tasks: [TaskItem]
    @Query private var sessions: [FocusSession]
    @Environment(DayClock.self) private var clock
    @Environment(FocusEngine.self) private var focus
    @State private var metric: Metric = .focus
    @State private var selectedKey: String?

    var body: some View {
        let calc = calculator
        let week = calc.week(endingOn: DayKey.date(clock.today) ?? .now)
        let selected = week.first { $0.dayKey == selectedKey }

        HStack(spacing: 8) {
            SummaryCard(metric: metric, week: week, selected: selected,
                        streak: calc.currentStreak(today: .now),
                        onShowWeek: { withAnimation { selectedKey = nil } })
                .frame(width: 230)
            WeekChartCard(metric: $metric, week: week, selectedKey: $selectedKey)
        }
    }

    private var calculator: InsightsCalculator {
        var records = sessions.map { InsightsCalculator.SessionRecord(startedAt: $0.startedAt, seconds: $0.accumulatedSec) }
        // Count the running session live instead of only what was last saved.
        if focus.isActive, let i = records.indices.last(where: { sessions[$0].endedAt == nil }) {
            records[i].seconds = focus.elapsed(at: .now)
        }
        return InsightsCalculator(
            tasks: tasks.map { .init(dayKey: $0.dayKey, isDone: $0.isDone, completedAt: $0.completedAt) },
            sessions: records)
    }
}

private struct SummaryCard: View {
    let metric: InsightsView.Metric
    let week: [InsightsCalculator.Day]
    let selected: InsightsCalculator.Day?
    let streak: Int
    let onShowWeek: () -> Void

    var body: some View {
        let days = selected.map { [$0] } ?? week
        let focusSec = days.reduce(0) { $0 + $1.focusSeconds }
        let completed = days.reduce(0) { $0 + $1.completed }
        let planned = days.reduce(0) { $0 + $1.planned }

        Card(tint: Palette.insightsSummary) {
            VStack(alignment: .leading, spacing: 0) {
                Text(selected.map { $0.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) } ?? "Last 7 days")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, 2)

                Group {
                    if metric == .focus {
                        Text(InsightsCalculator.formatDuration(focusSec))
                            .font(.system(size: 36, weight: .semibold))
                        Text("Time focused")
                            .font(.system(size: 12, weight: .medium))
                    } else {
                        Text("\(completed)")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Tasks completed")
                            .font(.system(size: 12, weight: .medium))
                        GeometryReader { p in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.well)
                                Capsule().fill(Palette.ink).frame(width: planned == 0 ? 0 : p.size.width * Double(completed) / Double(planned))
                            }
                        }
                        .frame(height: 4)
                        .padding(.top, 6)
                        Text("of \(planned) planned")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.top, 4)
                    }
                }
                .contentTransition(.numericText())

                Spacer(minLength: 6)

                VStack(spacing: 8) {
                    StatRow(icon: "clock", title: "Focus time", value: InsightsCalculator.formatDuration(week.reduce(0) { $0 + $1.focusSeconds }))
                    StatRow(icon: "calendar", title: "Active days", value: "\(week.filter(\.isActive).count) of 7")
                    StatRow(icon: "flame", title: "Current streak", value: "\(streak)d")
                }

                if selected != nil {
                    Button("Show whole week", action: onShowWeek)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, 8)
                }
            }
        }
    }
}

private struct StatRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .medium)).frame(width: 14)
            Text(title)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 11.5))
    }
}

private struct WeekChartCard: View {
    @Binding var metric: InsightsView.Metric
    let week: [InsightsCalculator.Day]
    @Binding var selectedKey: String?

    var body: some View {
        Card(tint: Palette.insightsChart) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardSegmented(options: [(.tasks, "Tasks"), (.focus, "Focus")], selection: $metric)
                    Spacer()
                    if let first = week.first, let last = week.last {
                        Text("\(first.date.formatted(.dateTime.day().month(.abbreviated))) – \(last.date.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                chart

                HStack(spacing: 10) {
                    if metric == .focus {
                        LegendDot(color: Palette.ink, title: "Focus minutes")
                    } else {
                        LegendDot(color: Palette.ink, title: "Completed")
                        LegendDot(color: Palette.ink.opacity(0.25), title: "Planned")
                    }
                    Spacer()
                    PlainMenu {
                        ForEach(week.reversed()) { day in
                            Button(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) {
                                withAnimation { selectedKey = day.dayKey }
                            }
                        }
                        if selectedKey != nil {
                            Divider()
                            Button("Whole Week") { withAnimation { selectedKey = nil } }
                        }
                    } label: {
                        Label(selectedKey == nil ? "Select a day" : "Change day", systemImage: "chevron.down")
                            .labelStyle(TrailingIconLabelStyle())
                            .font(.system(size: 11.5, weight: .medium))
                    }
                }
            }
        }
    }

    /// Keeps tiny values from filling the chart: at least an hour of focus or four tasks of headroom.
    private var yMax: Double {
        switch metric {
        case .focus: max(60, (week.map(\.focusMinutes).max() ?? 0) * 1.15)
        case .tasks: max(4, Double(week.map(\.planned).max() ?? 0) * 1.15)
        }
    }

    private var chart: some View {
        Chart(week) { day in
            let x = PlottableValue.value("Day", day.dayKey)
            let dimmed = selectedKey != nil && selectedKey != day.dayKey
            if metric == .focus {
                BarMark(x: x, y: .value("Minutes", day.focusMinutes), width: .ratio(0.5))
                    .foregroundStyle(Palette.ink.opacity(dimmed ? 0.35 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                BarMark(x: x, yStart: .value("Start", 0), yEnd: .value("Planned", day.planned), width: .ratio(0.5))
                    .foregroundStyle(Palette.ink.opacity(dimmed ? 0.12 : 0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                BarMark(x: x, yStart: .value("Start", 0), yEnd: .value("Completed", day.completed), width: .ratio(0.5))
                    .foregroundStyle(Palette.ink.opacity(dimmed ? 0.35 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let key = value.as(String.self), let date = DayKey.date(key) {
                        VStack(spacing: 0) {
                            Text(date, format: .dateTime.weekday(.abbreviated))
                            Text(date, format: .dateTime.day())
                        }
                        .font(.system(size: 9, weight: key == week.last?.dayKey ? .bold : .medium))
                        .foregroundStyle(Palette.ink)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel().font(.system(size: 8.5)).foregroundStyle(Palette.inkSecondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geo[plot].origin.x
                        guard let key: String = proxy.value(atX: x) else { return }
                        withAnimation(.easeOut(duration: 0.2)) { selectedKey = selectedKey == key ? nil : key }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: metric)
    }
}

private struct LegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11, weight: .medium))
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
