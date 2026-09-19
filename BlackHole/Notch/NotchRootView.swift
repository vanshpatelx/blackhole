import AppKit
import SwiftUI

struct NotchRootView: View {
    @Environment(NotchViewModel.self) private var model
    @Environment(FocusEngine.self) private var focus
    @Environment(CalendarService.self) private var calendar

    /// Width of each side of the timer "island" around the notch.
    static let islandWing: CGFloat = 78
    /// Meetings need more room than a countdown, because the title goes there too.
    static let meetingWing: CGFloat = 122

    static func collapsedSize(geometry g: NotchGeometry, timerActive: Bool, meetingActive: Bool = false) -> CGSize {
        if timerActive || meetingActive {
            // Dynamic Island style: grow sideways on the notch's own line instead of downward.
            let notchWidth = g.hasNotch ? g.notchSize.width : 0
            let wing = timerActive ? islandWing : meetingWing
            return CGSize(width: notchWidth + wing * 2, height: g.hasNotch ? g.notchSize.height : 30)
        }
        return g.hasNotch ? g.notchSize : CGSize(width: g.notchSize.width, height: 0)
    }

    var body: some View {
        let g = model.geometry
        let expanded = model.isExpanded
        let island = !expanded && focus.isActive
        // A running timer owns the notch; a meeting only takes it when nothing else is using it.
        let meeting = focus.isActive ? nil : calendar.imminentMeeting()
        let meetingIsland = !expanded && meeting != nil
        let size = expanded
            ? g.expandedSize
            : Self.collapsedSize(geometry: g, timerActive: focus.isActive, meetingActive: meeting != nil)
        let visible = expanded || g.hasNotch || focus.isActive || meeting != nil
        let anyIsland = island || meetingIsland
        let shape = NotchShape(
            topRadius: expanded ? NotchGeometry.flare : (anyIsland ? 9 : 7),
            // Concentric with the cards: card radius plus the black border.
            bottomRadius: expanded ? Radius.card + NotchGeometry.inset : (anyIsland ? 13 : 9)
        )

        ZStack(alignment: .top) {
            shape.fill(Palette.panel)

            // Kept in the tree while collapsed so opening never has to build every card mid-animation.
            ExpandedPanel()
                .padding(.horizontal, NotchGeometry.flare + NotchGeometry.inset)
                .frame(width: g.expandedSize.width, height: g.expandedSize.height, alignment: .top)
                .compositingGroup()
                .scaleEffect(expanded ? 1 : 0.94, anchor: .top)
                .animation(expanded ? NotchViewModel.contentScaleIn : NotchViewModel.collapseAnimation, value: expanded)
                .opacity(expanded ? 1 : 0)
                .animation(expanded ? NotchViewModel.contentFadeIn : NotchViewModel.contentOut, value: expanded)
                .allowsHitTesting(expanded)
                .accessibilityHidden(!expanded)

            if focus.isActive {
                IslandTimer(
                    notchWidth: g.hasNotch ? g.notchSize.width : 0,
                    height: Self.collapsedSize(geometry: g, timerActive: true).height
                )
                .opacity(island ? 1 : 0)
                .animation(island ? .easeOut(duration: 0.3).delay(0.18) : .easeOut(duration: 0.12), value: island)
                .allowsHitTesting(false)
            }

            if let meeting {
                MeetingIsland(
                    meeting: meeting,
                    notchWidth: g.hasNotch ? g.notchSize.width : 0,
                    height: Self.collapsedSize(geometry: g, timerActive: false, meetingActive: true).height
                )
                .opacity(meetingIsland ? 1 : 0)
                .animation(
                    meetingIsland ? .easeOut(duration: 0.3).delay(0.18) : .easeOut(duration: 0.12),
                    value: meetingIsland
                )
                .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        // The black shape reveals the content as it grows, like the Dynamic Island.
        .clipShape(shape)
        .opacity(visible ? 1 : 0)
        .overlay {
            if island {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.expand(pinned: true) }
            } else if meetingIsland, let meeting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { join(meeting) }
                    .contextMenu {
                        if meeting.meetingURL != nil {
                            Button("Join \(meeting.title)") { join(meeting) }
                        }
                        Button("Dismiss") { calendar.dismissMeeting(id: meeting.id) }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    /// Opens the invite's video link, or shows the day if the meeting has no link to join.
    private func join(_ meeting: CalendarService.Event) {
        guard let url = meeting.meetingURL else {
            model.expand(pinned: true)
            return
        }
        NSWorkspace.shared.open(url)
        calendar.dismissMeeting(id: meeting.id)
    }
}

/// Live focus timer in the notch's row: progress ring on the left, time on the right.
private struct IslandTimer: View {
    let notchWidth: CGFloat
    let height: CGFloat
    @Environment(FocusEngine.self) private var focus

    private static let accent = Color(hex: 0xFFB36B)
    private static let done = Color(hex: 0x4ADE80)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = focus.displaySeconds(at: context.date)
            let wing = NotchRootView.islandWing

            HStack(spacing: 0) {
                IslandRing(progress: focus.targetSec == nil ? nil : focus.progress(at: context.date), phase: focus.phase)
                    .frame(width: 17, height: 17)
                    .padding(.leading, 14)
                    .frame(width: wing, alignment: .leading)

                Color.clear.frame(width: notchWidth)

                Group {
                    if focus.phase == .finished {
                        Text("Done")
                            .foregroundStyle(Self.done)
                            .modifier(FinishedPulse(active: true))
                    } else {
                        Text(DotMatrixText.format(seconds: seconds))
                            .foregroundStyle(focus.phase == .running ? Self.accent : .white.opacity(0.5))
                            .contentTransition(.numericText(countsDown: focus.targetSec != nil))
                            .animation(.snappy(duration: 0.3), value: seconds)
                    }
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 14)
                .frame(width: wing, alignment: .trailing)
            }
            .frame(height: height)
        }
    }
}

/// The next meeting in the notch's row: what it is on the left, how long you have on the right.
private struct MeetingIsland: View {
    let meeting: CalendarService.Event
    let notchWidth: CGFloat
    let height: CGFloat

    private static let soon = Color(hex: 0xFF5E7E)
    private static let live = Color(hex: 0x4ADE80)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let untilStart = meeting.start.timeIntervalSince(context.date)
            let started = untilStart <= 0
            let wing = NotchRootView.meetingWing

            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: meeting.meetingURL == nil ? "calendar" : "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(meeting.color)
                    Text(meeting.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, 14)
                .frame(width: wing, alignment: .leading)

                Color.clear.frame(width: notchWidth)

                Text(started ? "Now" : DotMatrixText.format(seconds: Int(untilStart.rounded(.up))))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(started ? Self.live : Self.soon)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.3), value: started ? 0 : Int(untilStart))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 14)
                    .frame(width: wing, alignment: .trailing)
            }
            .frame(height: height)
        }
    }
}

private struct IslandRing: View {
    /// `nil` for a stopwatch, which shows a slowly spinning arc instead of progress.
    let progress: Double?
    let phase: FocusEngine.Phase
    @State private var spin = false

    private static let gradient = AngularGradient(
        colors: [Color(hex: 0xFFB36B), Color(hex: 0xFF5E7E), Color(hex: 0xA77BF3), Color(hex: 0x62B6FF), Color(hex: 0xFFB36B)],
        center: .center
    )

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 2.6)
            if phase == .finished {
                Circle().stroke(Color(hex: 0x4ADE80), lineWidth: 2.6)
                Image(systemName: "checkmark").font(.system(size: 7, weight: .black)).foregroundStyle(Color(hex: 0x4ADE80))
            } else {
                Circle()
                    .trim(from: 0, to: progress ?? 0.28)
                    .stroke(Self.gradient, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .rotationEffect(.degrees(progress == nil ? (spin ? 270 : -90) : -90))
                    .opacity(phase == .paused ? 0.45 : 1)
                    .animation(.linear(duration: 1), value: progress)
                if phase == .paused {
                    Image(systemName: "pause.fill").font(.system(size: 6.5, weight: .black)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            guard progress == nil else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

private struct FinishedPulse: ViewModifier {
    let active: Bool
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dim ? 0.35 : 1)
            .onChange(of: active, initial: true) { _, on in
                dim = false
                guard on else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// Top bar plus the selected tab. Shared by the notch panel and the floating workspace.
struct ExpandedPanel: View {
    enum Placement { case notch, floating }

    var placement: Placement = .notch
    @Environment(NotchViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let g = model.geometry
        let gap: CGFloat = placement == .notch && g.hasNotch ? g.notchSize.width : 12
        let barHeight = placement == .notch ? g.topBarHeight : FloatingWorkspaceController.topBarHeight

        VStack(spacing: 0) {
            // The top bar shares the menu-bar row with the notch, split around the camera housing.
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    AppMark(size: 24)
                    Text("Black Hole")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Button { model.openDashboard() } label: {
                        Label("Open app", systemImage: "macwindow")
                    }
                    .buttonStyle(ChromeButtonStyle())
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                Color.clear.frame(width: gap)

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ChromeTabs(tabs: NotchViewModel.Tab.allCases, selection: $model.tab)
                    Button { placement == .notch ? model.collapse() : model.closeFloating() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Palette.chrome.opacity(0.7)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close (Esc)")
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: barHeight)

            Group {
                switch model.tab {
                case .workspace: WorkspaceView()
                case .insights: InsightsView()
                case .settings: SettingsView()
                }
            }
            .padding(.bottom, NotchGeometry.inset)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Black Hole brand mark: the mascot on its deep-space tile.
struct AppMark: View {
    var size: CGFloat
    @Environment(MascotMoodCenter.self) private var mascot
    @Environment(FocusEngine.self) private var focus

    var body: some View {
        MascotTile(size: size, mood: mascot.mood(focusRunning: focus.phase == .running))
            .keyframeAnimator(initialValue: 1.0, trigger: mascot.celebrationCount) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.25, duration: 0.18)
                SpringKeyframe(0.95, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.3)
            }
    }
}
