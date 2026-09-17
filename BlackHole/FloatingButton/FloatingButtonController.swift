import AppKit
import SwiftUI

/// AssistiveTouch-style button that floats above every app. Click it to open the workspace,
/// drag it anywhere and it snaps to the nearest side of the screen, right-click for more.
@MainActor
final class FloatingButtonController {
    static let enabledKey = "floatingButton.enabled"
    private static let edgeKey = "floatingButton.edge"
    private static let yRatioKey = "floatingButton.yRatio"
    private static let screenKey = "floatingButton.screen"

    /// Visible button size; the window is larger so the shadow isn't clipped.
    static let buttonSize: CGFloat = 52
    private static let shadowPad: CGFloat = 14
    private static let edgeMargin: CGFloat = 8
    private var windowSize: CGFloat { Self.buttonSize + Self.shadowPad * 2 }

    private let services: AppServices
    private let state = FloatingButtonState()
    private let panel: NSPanel
    private var idleWork: DispatchWorkItem?

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    init(services: AppServices) {
        self.services = services
        let size = Self.buttonSize + Self.shadowPad * 2
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let container = FloatingButtonContainer(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let hosting = NSHostingView(rootView: FloatingButtonView(state: state).blackHoleEnvironment(services))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.onClick = { [weak self] in self?.click() }
        container.onDragMoved = { [weak self] delta in self?.drag(by: delta) }
        container.onDragEnded = { [weak self] in self?.snapToEdge(animated: true) }
        container.onHover = { [weak self] hovering in self?.setHovering(hovering) }
        container.onPress = { [weak self] pressed in self?.state.pressed = pressed }
        container.menuProvider = { [weak self] in self?.makeMenu() }
        panel.contentView = container

        restorePosition()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyVisibility() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restorePosition() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restorePosition() }
        }
        applyVisibility()
        scheduleIdle()
    }

    // MARK: Visibility

    private func applyVisibility() {
        if Self.isEnabled {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    // MARK: Interaction

    /// The visible button in screen coordinates.
    private var buttonRect: NSRect {
        panel.frame.insetBy(dx: Self.shadowPad, dy: Self.shadowPad)
    }

    private func click() {
        let notch = services.notch
        notch.isFloatingOpen ? notch.closeFloating() : notch.openFloating(anchor: buttonRect)
        scheduleIdle()
    }

    private func setHovering(_ hovering: Bool) {
        state.hovering = hovering
        if hovering {
            services.mascot.poke()
            idleWork?.cancel()
            state.idle = false
        } else {
            scheduleIdle()
        }
    }

    private func scheduleIdle() {
        idleWork?.cancel()
        state.idle = false
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.state.hovering, !self.state.pressed else { return }
                self.state.idle = true
            }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func drag(by delta: CGSize) {
        services.notch.closeFloating()
        state.idle = false
        idleWork?.cancel()
        var origin = panel.frame.origin
        origin.x += delta.width
        origin.y += delta.height
        panel.setFrameOrigin(origin)
    }

    // MARK: Positioning

    private var currentScreen: NSScreen? {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func frame(onLeft left: Bool, centerY: CGFloat, in visible: NSRect) -> NSRect {
        let half = Self.buttonSize / 2
        let x = left
            ? visible.minX + Self.edgeMargin - Self.shadowPad
            : visible.maxX - Self.edgeMargin - Self.buttonSize - Self.shadowPad
        let clampedY = min(max(centerY, visible.minY + Self.edgeMargin + half), visible.maxY - Self.edgeMargin - half)
        return NSRect(x: x, y: clampedY - half - Self.shadowPad, width: windowSize, height: windowSize)
    }

    private func snapToEdge(animated: Bool) {
        guard let screen = currentScreen else { return }
        let visible = screen.visibleFrame
        let left = panel.frame.midX < visible.midX
        let target = frame(onLeft: left, centerY: panel.frame.midY, in: visible)

        let defaults = UserDefaults.standard
        defaults.set(left ? "left" : "right", forKey: Self.edgeKey)
        defaults.set(screen.localizedName, forKey: Self.screenKey)
        defaults.set(Double((target.midY - visible.minY) / max(1, visible.height)), forKey: Self.yRatioKey)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.05)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
        scheduleIdle()
    }

    private func restorePosition() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Self.screenKey)
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == saved }) ?? NotchGeometry.preferredScreen() else { return }
        let visible = screen.visibleFrame
        let left = defaults.string(forKey: Self.edgeKey) == "left"
        let ratio = defaults.object(forKey: Self.yRatioKey) as? Double ?? 0.6
        panel.setFrame(frame(onLeft: left, centerY: visible.minY + visible.height * ratio, in: visible), display: true)
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let notch = services.notch
        let focus = services.focus
        let rect = buttonRect
        for tab in NotchViewModel.Tab.allCases {
            menu.addItem(ClosureMenuItem(tab.rawValue) {
                notch.tab = tab
                notch.openFloating(anchor: rect)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Open at Notch") { notch.expand(pinned: true) })
        menu.addItem(ClosureMenuItem("Open Dashboard") { notch.openDashboard() })
        menu.addItem(.separator())
        let focusTitle = switch focus.phase {
        case .idle: "Start Focus"
        case .running: "Pause Focus"
        case .paused: "Resume Focus"
        case .finished: "Add 5 Minutes"
        }
        menu.addItem(ClosureMenuItem(focusTitle) { focus.toggle() })
        if focus.isActive {
            menu.addItem(ClosureMenuItem("Stop Focus") { focus.stop() })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Hide Floating Button") {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
        })
        return menu
    }
}

@MainActor
@Observable
final class FloatingButtonState {
    var hovering = false
    var pressed = false
    var idle = false
}

/// Hosts the SwiftUI visuals but takes every mouse event itself, since the window moves while dragging.
final class FloatingButtonContainer: NSView {
    var onClick: (() -> Void)?
    var onDragMoved: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onPress: ((Bool) -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private var lastMouse: NSPoint?
    private var travelled: CGFloat = 0
    private var dragging = false
    private static let dragThreshold: CGFloat = 3

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only the visible button is clickable; the shadow margin passes clicks through visually.
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let inset = (bounds.width - FloatingButtonController.buttonSize) / 2
        addTrackingArea(NSTrackingArea(rect: bounds.insetBy(dx: inset, dy: inset),
                                       options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { if !dragging { onHover?(false) } }

    override func mouseDown(with event: NSEvent) {
        lastMouse = NSEvent.mouseLocation
        travelled = 0
        dragging = false
        onPress?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastMouse else { return }
        let now = NSEvent.mouseLocation
        let delta = CGSize(width: now.x - last.x, height: now.y - last.y)
        travelled += hypot(delta.width, delta.height)
        lastMouse = now
        if travelled > Self.dragThreshold {
            dragging = true
            onDragMoved?(delta)
        }
    }

    override func mouseUp(with event: NSEvent) {
        onPress?(false)
        if dragging {
            onDragEnded?()
        } else {
            onClick?()
        }
        dragging = false
        lastMouse = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

struct FloatingButtonView: View {
    let state: FloatingButtonState
    @Environment(FocusEngine.self) private var focus
    @Environment(NotchViewModel.self) private var notch
    @Environment(MascotMoodCenter.self) private var mascot

    private static let ringGradient = AngularGradient(
        colors: [Color(hex: 0xFFB36B), Color(hex: 0xFF5E7E), Color(hex: 0xA77BF3), Color(hex: 0x62B6FF), Color(hex: 0xFFB36B)],
        center: .center)

    var body: some View {
        let size = FloatingButtonController.buttonSize
        let mood = mascot.mood(focusRunning: focus.phase == .running)
        let active = state.hovering || notch.isFloatingOpen

        ZStack {
            // A little round window into space with Holey inside.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x3A2A63), Color(hex: 0x150F2A), Color(hex: 0x07060D)],
                                     center: UnitPoint(x: 0.5, y: 0.35), startRadius: 2, endRadius: size * 0.62))
                .overlay(StarField(size: size).clipShape(Circle()).opacity(0.8))
                .overlay(
                    Mascot(size: size * 0.98, blinks: true, lookUp: active, mood: mood)
                        .offset(y: -size * 0.01)
                )
                .clipShape(Circle())
                // Glassy rim: brighter at the top like light catching an edge.
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.2)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                )

            if focus.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let progress = focus.targetSec == nil ? 1 : focus.progress(at: context.date)
                    ZStack(alignment: .bottom) {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Self.ringGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .opacity(focus.phase == .running ? 1 : 0.5)
                            .animation(.linear(duration: 1), value: progress)
                            .padding(-2.5)
                        Group {
                            if focus.phase == .paused {
                                Image(systemName: "pause.fill").font(.system(size: 6.5, weight: .black))
                            } else {
                                Text("\(focus.displaySeconds(at: context.date) / 60)m")
                                    .font(.system(size: 8.5, weight: .heavy, design: .rounded).monospacedDigit())
                            }
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 5)
                        .frame(height: 13)
                        .background(Capsule().fill(Color(hex: 0xFFD7A8)))
                        .offset(y: 7)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        // Soft violet glow that brightens on hover.
        .shadow(color: Color(hex: 0x8B5CF6).opacity(active ? 0.75 : 0.35), radius: active ? 12 : 7)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        .keyframeAnimator(initialValue: 1.0, trigger: mascot.celebrationCount) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.3, duration: 0.18)
            SpringKeyframe(0.94, duration: 0.14)
            SpringKeyframe(1.0, duration: 0.3)
        }
        .scaleEffect(state.pressed ? 0.9 : state.hovering ? 1.08 : 1)
        .opacity(state.idle && !active && !focus.isActive && !mascot.isCelebrating ? 0.55 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.3), value: state.pressed)
        .animation(.spring(duration: 0.35, bounce: 0.35), value: state.hovering)
        .animation(.easeInOut(duration: 0.5), value: state.idle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .help("Black Hole: click to open, drag to move, right-click for more")
    }
}
