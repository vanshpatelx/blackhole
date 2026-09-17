import SwiftUI

struct NotchRootView: View {
    @Environment(NotchViewModel.self) private var model
    @Environment(FocusEngine.self) private var focus

    static func collapsedSize(geometry g: NotchGeometry, timerActive: Bool) -> CGSize {
        if timerActive {
            return CGSize(width: g.notchSize.width + 36, height: g.notchSize.height + 26)
        }
        return g.hasNotch ? g.notchSize : CGSize(width: g.notchSize.width, height: 0)
    }

    var body: some View {
        let g = model.geometry
        let size = model.isExpanded ? g.expandedSize : Self.collapsedSize(geometry: g, timerActive: focus.isActive)
        let visible = model.isExpanded || g.hasNotch || focus.isActive

        ZStack(alignment: .top) {
            NotchShape(topRadius: model.isExpanded ? NotchGeometry.flare : 7,
                       // Concentric with the cards: card radius plus the black border.
                       bottomRadius: model.isExpanded ? Radius.card + NotchGeometry.inset : (focus.isActive ? 14 : 9))
                .fill(Palette.panel)
                .shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 18, y: 8)

            if model.isExpanded {
                ExpandedPanel()
                    .padding(.horizontal, NotchGeometry.flare + NotchGeometry.inset)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(.easeOut(duration: 0.22).delay(0.06)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))))
            } else if focus.isActive {
                CollapsedTimer()
                    .frame(height: size.height, alignment: .bottom)
                    .padding(.bottom, 7)
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .opacity(visible ? 1 : 0)
        .overlay {
            if !model.isExpanded && focus.isActive {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.expand(pinned: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }
}

/// Countdown shown under the camera while a focus session runs and the panel is closed.
private struct CollapsedTimer: View {
    @Environment(FocusEngine.self) private var focus

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                if focus.phase == .paused {
                    Image(systemName: "pause.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                }
                DotMatrixText(text: DotMatrixText.format(seconds: focus.displaySeconds(at: context.date)),
                              dot: 1.7, spacing: 0.8,
                              color: .white.opacity(focus.phase == .running ? 0.95 : 0.55))
            }
            .modifier(FinishedPulse(active: focus.phase == .finished))
        }
    }
}

private struct FinishedPulse: ViewModifier {
    let active: Bool
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dim ? 0.3 : 1)
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
