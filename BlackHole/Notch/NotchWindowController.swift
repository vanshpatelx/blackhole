import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless panel that floats above the menu bar, on every Space and over full-screen apps,
/// and never activates Black Hole when clicked.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    /// Only takes keyboard focus while expanded so typing into tasks and notes works.
    var allowsKey = false
    override var canBecomeKey: Bool {
        allowsKey
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// Owns the notch panel and decides when it expands and collapses.
@MainActor
final class NotchWindowController {
    private let model: NotchViewModel
    private let focus: FocusEngine
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var menuDepth = 0
    private var hotKey: HotKey?
    /// Mouse-moved events aren't delivered reliably to a non-key panel, so poll while it's open.
    private var pollTimer: Timer?

    private let hoverDelay: TimeInterval = 0.12
    private let leaveDelay: TimeInterval = 0.3

    init(services: AppServices) {
        model = services.notch
        focus = services.focus
        panel = NotchPanel(contentRect: model.geometry.panelFrame)

        let root = NotchRootView().blackHoleEnvironment(services)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        model.onExpansionChange = { [weak self] expanded in self?.expansionChanged(expanded) }
        layout()
        panel.orderFrontRegardless()
        installMonitors()

        hotKey = HotKey(keyCode: kVK_ANSI_N, modifiers: optionKey) { [weak self] in
            MainActor.assumeIsolated { self?.model.toggleFromHotKey() }
        }
    }

    // MARK: Layout

    private func layout() {
        if let screen = NotchGeometry.preferredScreen() {
            model.geometry = NotchGeometry.make(for: screen)
        }
        panel.setFrame(model.geometry.panelFrame, display: true)
    }

    /// Screen rect that should currently receive clicks.
    private var interactiveRect: NSRect {
        let g = model.geometry
        if model.isExpanded {
            return g.rect(for: g.expandedSize)
        }
        if focus.isActive {
            return g.rect(for: NotchRootView.collapsedSize(geometry: g, timerActive: true))
        }
        return .zero
    }

    // MARK: Events

    private func installMonitors() {
        let mouseMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) {
            monitors.append(m)
        }

        // Clicking anywhere else dismisses the panel, including a hotkey-pinned one.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.isExpanded, self.menuDepth == 0,
                      !self.interactiveRect.contains(NSEvent.mouseLocation) else { return }
                self.model.collapse()
            }
        }) {
            monitors.append(m)
        }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.model.isExpanded else { return false }
                self.model.collapse()
                return true
            }
            return handled ? nil : event
        }) {
            monitors.append(m)
        }

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        // Screen geometry can be stale if we launched while displays were asleep or reconfiguring.
        NSWorkspace.shared.notificationCenter
            .addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layout() }
            }
        nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuDepth += 1
                self?.collapseWork?.cancel()
            }
        }
        nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuDepth = max(0, self.menuDepth - 1)
                self.mouseMoved()
            }
        }
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        let g = model.geometry
        let overPanel = interactiveRect.contains(point)
        panel.ignoresMouseEvents = !overPanel

        if model.isExpanded {
            if overPanel || g.hoverZone.contains(point) {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil, shouldAutoCollapse {
                schedule(&collapseWork, after: leaveDelay) { [weak self] in
                    guard let self, shouldAutoCollapse,
                          !self.interactiveRect.contains(NSEvent.mouseLocation) else { return }
                    model.collapse()
                }
            }
        } else if g.hoverZone.contains(point) || overPanel {
            if expandWork == nil {
                schedule(&expandWork, after: hoverDelay) { [weak self] in
                    guard let self else { return }
                    let p = NSEvent.mouseLocation
                    if model.geometry.hoverZone.contains(p) || interactiveRect.contains(p) {
                        model.expand()
                    }
                }
            }
        } else {
            expandWork?.cancel()
            expandWork = nil
        }
    }

    private var shouldAutoCollapse: Bool {
        !model.isPinned && menuDepth == 0 && !isEditingText
    }

    /// True while the user has unsaved text in a field, so a stray mouse move doesn't throw it away.
    private var isEditingText: Bool {
        guard panel.isKeyWindow, let editor = panel.firstResponder as? NSTextView else { return false }
        return editor.isFieldEditor && !editor.string.isEmpty
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        slot?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.expandWork = nil
                self?.collapseWork = nil
                block()
            }
        }
        slot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func expansionChanged(_ expanded: Bool) {
        expandWork?.cancel()
        collapseWork?.cancel()
        expandWork = nil
        collapseWork = nil
        panel.allowsKey = expanded
        pollTimer?.invalidate()
        pollTimer = nil
        if expanded {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseMoved() }
            }
            panel.ignoresMouseEvents = false
            if model.isPinned {
                panel.makeKey()
            }
        } else {
            panel.makeFirstResponder(nil)
            if panel.isKeyWindow {
                // Hand keyboard focus back to whatever app the user was in.
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
            panel.ignoresMouseEvents = !interactiveRect.contains(NSEvent.mouseLocation)
        }
    }
}
