import SwiftUI

struct TimerCard: View {
    @Environment(FocusEngine.self) private var focus
    @Environment(TaskActions.self) private var actions

    var body: some View {
        Card(tint: Palette.timer) {
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let text = DotMatrixText.format(seconds: focus.displaySeconds(at: context.date))
                    VStack(spacing: 8) {
                        DotMatrixText(text: text, dot: text.count > 5 ? 2.2 : 3.2, spacing: text.count > 5 ? 0.9 : 1.3)
                            .frame(height: 32)
                        Text(stateLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                        ProgressTrack(value: focus.progress(at: context.date))
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 18)
                .help(taskTitle ?? "")

                Spacer(minLength: 10)

                HStack(spacing: 8) {
                    Button { focus.toggle() } label: {
                        Label(primaryTitle, systemImage: focus.phase == .running ? "pause.fill" : "play.fill")
                            .labelStyle(CompactLabelStyle())
                    }
                    .buttonStyle(PillButtonStyle())

                    Button(action: complete) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(focus.isActive ? 1 : 0.7))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color(hex: 0x2E2A36).opacity(focus.isActive ? 1 : 0.35)))
                            .shadow(color: .black.opacity(focus.isActive ? 0.25 : 0), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(!focus.isActive)
                    .help(focus.taskID == nil ? "End session" : "Finish session and complete task")
                }

                HStack(spacing: 10) {
                    PlainMenu {
                        ForEach([5, 15, 25, 45, 60, 90], id: \.self) { m in
                            Button("\(m) minutes") { focus.setPreset(minutes: m) }
                        }
                        Divider()
                        Button("Stopwatch") { focus.setPreset(minutes: nil) }
                    } label: {
                        Label("Set time", systemImage: "slider.horizontal.3")
                            .labelStyle(CompactLabelStyle())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .disabled(focus.isActive)
                    .opacity(focus.isActive ? 0.5 : 1)

                    EllipsisMenu {
                        Button("Add 5 Minutes") { focus.addFiveMinutes() }.disabled(!focus.isActive)
                        Button("Reset Timer") { focus.stop() }.disabled(!focus.isActive)
                    }
                }
                .padding(.top, 8)

                Spacer(minLength: 14)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var taskTitle: String? { focus.taskID.flatMap { actions.task(with: $0)?.title } }

    private var stateLabel: String {
        switch focus.phase {
        case .idle: focus.presetSec == nil ? "Stopwatch" : "Ready"
        case .running: focus.targetSec == nil ? "Elapsed" : "Remaining"
        case .paused: "Paused"
        case .finished: "Time's up"
        }
    }

    private var primaryTitle: String {
        switch focus.phase {
        case .idle: "Start"
        case .running: "Pause"
        case .paused: "Resume"
        case .finished: "+5 min"
        }
    }

    private func complete() {
        guard let id = focus.stop(), let task = actions.task(with: id) else { return }
        actions.setDone(task, true)
    }
}

private struct ProgressTrack: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well)
                Capsule().fill(Palette.ink.opacity(0.7))
                    .frame(width: proxy.size.width * value)
                    .animation(.linear(duration: 1), value: value)
            }
        }
        .frame(height: 3)
    }
}
