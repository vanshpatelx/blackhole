import SwiftData
import SwiftUI

struct WorkspaceView: View {
    var body: some View {
        HStack(spacing: 8) {
            TasksCard()
            TimerCard().frame(width: 146)
            NotepadCard().frame(width: 140)
            EventsCard().frame(width: 150)
        }
    }
}

struct TasksCard: View {
    @Environment(DayClock.self) private var clock

    var body: some View {
        TaskList(dayKey: clock.today)
    }
}

private struct TaskList: View {
    let dayKey: String
    @Query private var tasks: [TaskItem]
    @Environment(TaskActions.self) private var actions
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    init(dayKey: String) {
        self.dayKey = dayKey
        _tasks = Query(filter: #Predicate<TaskItem> { $0.dayKey == dayKey }, sort: \.sortIndex, animation: .spring(response: 0.3, dampingFraction: 0.85))
    }

    var body: some View {
        Card(tint: Palette.tasks) {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: "checklist", title: "Today's tasks") {
                    Text("\(tasks.filter(\.isDone).count) / \(tasks.count)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.inkSecondary)
                        .contentTransition(.numericText())
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                    TextField("", text: $draft, prompt: Text("What needs doing?").foregroundStyle(Palette.inkTertiary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($inputFocused)
                        .onSubmit(submit)
                    Image(systemName: "return")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(draft.isEmpty ? Palette.inkTertiary : Palette.ink)
                }
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: Radius.well, style: .continuous).fill(Palette.well))
                .onTapGesture { inputFocused = true }

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(tasks) { task in
                            TaskRow(task: task)
                            DottedDivider().padding(.horizontal, 12)
                        }
                    }
                }
                .overlay {
                    if tasks.isEmpty {
                        Text("Nothing planned yet.\nAdd the one thing that matters most.")
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }

                CardFooter {
                    Text(tasks.count > 1 ? "Drag to reorder" : "Right-click for more")
                } trailing: {
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                }
            }
        }
    }

    private func submit() {
        guard actions.add(draft, dayKey: dayKey) != nil else { return }
        draft = ""
        inputFocused = true
    }
}

struct TaskRow: View {
    let task: TaskItem
    @Environment(TaskActions.self) private var actions
    @Environment(FocusEngine.self) private var focus
    @State private var hovering = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var dropTargeted = false
    @FocusState private var renameFocused: Bool

    private var isFocusTask: Bool { focus.taskID == task.id && focus.isActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { actions.setDone(task, !task.isDone) }
                } label: {
                    ZStack {
                        Circle().strokeBorder(Palette.ink.opacity(0.55), lineWidth: 1.3)
                        if task.isDone {
                            Circle().fill(Palette.ink)
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.tasks)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)

                if renaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($renameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { renaming = false }
                        .onChange(of: renameFocused) { _, focused in if !focused { commitRename() } }
                } else {
                    Text(task.title)
                        .font(.system(size: 13))
                        .strikethrough(task.isDone, color: Palette.inkSecondary)
                        .foregroundStyle(task.isDone ? Palette.inkSecondary : Palette.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) { startRename() }
                }

                if !task.isDone {
                    IconButton(systemName: isFocusTask && focus.phase == .running ? "pause.fill" : "play.fill", size: 22, help: "Focus") {
                        actions.focus(on: task)
                    }
                    .opacity(hovering || isFocusTask ? 1 : 0)
                }

                EllipsisMenu {
                    TaskMenuItems(task: task, onRename: startRename)
                }
            }

            if hasMeta {
                HStack(spacing: 8) {
                    if let limit = task.timeLimitSec {
                        Label("\(limit / 60)m", systemImage: "timer")
                    }
                    if let reminder = task.reminderAt, reminder > .now {
                        Label(reminder.formatted(date: Calendar.current.isDateInToday(reminder) ? .omitted : .abbreviated, time: .shortened), systemImage: "bell")
                    }
                    Spacer(minLength: 0)
                    if isFocusTask {
                        Label(focus.phase == .paused ? "Paused" : focus.phase == .finished ? "Time's up" : "Active session",
                              systemImage: focus.phase == .paused ? "pause.circle" : "scope")
                            .fontWeight(.semibold)
                    }
                }
                .labelStyle(CompactLabelStyle())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .padding(.leading, 28)
                .padding(.trailing, 4)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.well, style: .continuous)
                .fill(isFocusTask ? Palette.wellStrong : (hovering || dropTargeted) ? Palette.well : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { TaskMenuItems(task: task, onRename: startRename) }
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { actions.move(id, before: task) }
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var hasMeta: Bool {
        task.timeLimitSec != nil || (task.reminderAt.map { $0 > .now } ?? false) || isFocusTask
    }

    private func startRename() {
        renameText = task.title
        renaming = true
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        guard renaming else { return }
        actions.rename(task, to: renameText)
        renaming = false
    }
}

struct TaskMenuItems: View {
    let task: TaskItem
    var onRename: () -> Void
    @Environment(TaskActions.self) private var actions

    var body: some View {
        Button { actions.focus(on: task) } label: { Label("Focus", systemImage: "scope") }
        Button { actions.setDone(task, !task.isDone) } label: {
            Label(task.isDone ? "Mark as Not Done" : "Mark as Done", systemImage: "checkmark")
        }
        Button(action: onRename) { Label("Rename…", systemImage: "pencil") }
        Menu {
            ForEach([15, 25, 45, 60, 90], id: \.self) { m in
                Button("\(m) minutes") { actions.setTimeLimit(task, minutes: m) }
            }
            Divider()
            Button("No Time Limit") { actions.setTimeLimit(task, minutes: nil) }
        } label: { Label("Set Time Limit", systemImage: "timer") }
        Menu {
            ForEach(ReminderPreset.allCases) { preset in
                Button(preset.title) { actions.setReminder(task, at: preset.date()) }
            }
            if task.reminderAt != nil {
                Divider()
                Button("Clear Reminder") { actions.setReminder(task, at: nil) }
            }
        } label: { Label("Remind Me", systemImage: "bell") }
        Button { actions.moveToTomorrow(task) } label: { Label("Move to Tomorrow", systemImage: "arrow.right") }
        Button { actions.duplicate(task) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Divider()
        Button(role: .destructive) { actions.delete(task) } label: { Label("Delete", systemImage: "trash") }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
