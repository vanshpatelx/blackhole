import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shows the full workspace beside the floating button, on whichever display the button is on.
@MainActor
final class FloatingWorkspaceController {
    static let topBarHeight: CGFloat = 44
    /// Space between the button and the workspace.
    private static let gap: CGFloat = 10
    /// Keeps the workspace off the very edge of the screen.
    private static let screenMargin: CGFloat = 8

    static var size: CGSize {
        CGSize(width: NotchGeometry.contentWidth + 2 * NotchGeometry.inset,
               height: topBarHeight + NotchGeometry.cardsHeight)
    }

    private let model: NotchViewModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var unmountWork: DispatchWorkItem?

    init(services: AppServices) {
        model = services.notch
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.size))
        panel.level = .statusBar
        panel.ignoresMouseEvents = false
        // The window shadow follows the rounded content's alpha, so no transparent margin is needed.
        panel.hasShadow = true

        let hosting = NSHostingView(rootView: FloatingWorkspaceRoot().blackHoleEnvironment(services))
        hosting.sizingOptions = []
        panel.contentView = hosting

        model.onFloatingChange = { [weak self] open in open ? self?.present() : self?.dismiss() }
        installMonitors()
    }

    private func installMonitors() {
        // Clicking in another app closes it, like a popover.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.isFloatingOpen,
                      !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.model.closeFloating()
            }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.model.isFloatingOpen, self.panel.isKeyWindow else { return false }
                self.model.closeFloating()
                return true
            }
            return handled ? nil : event
        }) { monitors.append(m) }
    }

    private func present() {
        unmountWork?.cancel()
        let anchor = model.floatingAnchor
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = Self.size
        let opensLeft = anchor.midX > visible.midX
        var x = opensLeft ? anchor.minX - Self.gap - size.width : anchor.maxX + Self.gap
        var y = anchor.midY - size.height / 2
        x = min(max(x, visible.minX + Self.screenMargin), visible.maxX - Self.screenMargin - size.width)
        y = min(max(y, visible.minY + Self.screenMargin), visible.maxY - Self.screenMargin - size.height)

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        model.floatingOpensLeft = opensLeft
        panel.allowsKey = true
        panel.orderFrontRegardless()
        panel.makeKey()
        // The shadow is traced from the rendered content, so recompute it once the grow-in has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.panel.invalidateShadow() }
    }

    private func dismiss() {
        panel.makeFirstResponder(nil)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.isFloatingOpen else { return }
                self.panel.allowsKey = false
                self.panel.orderOut(nil)
            }
        }
        unmountWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
    }
}

private struct FloatingWorkspaceRoot: View {
    @Environment(NotchViewModel.self) private var model
    @State private var shown = false

    var body: some View {
        let radius = Radius.card + NotchGeometry.inset
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        // Built once at launch and only shown/hidden, so opening never waits on view creation.
        ExpandedPanel(placement: .floating)
            .padding(.horizontal, NotchGeometry.inset)
            .background(shape.fill(Palette.panel).overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5)))
            .clipShape(shape)
            .compositingGroup()
            // Grow out of the side facing the button.
            .scaleEffect(shown ? 1 : 0.92, anchor: model.floatingOpensLeft ? .trailing : .leading)
            .animation(shown ? NotchViewModel.contentScaleIn : NotchViewModel.collapseAnimation, value: shown)
            .opacity(shown ? 1 : 0)
            .animation(shown ? NotchViewModel.contentFadeIn : NotchViewModel.contentOut, value: shown)
            .allowsHitTesting(shown)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(.dark)
            .onChange(of: model.isFloatingOpen) { _, open in
                if open {
                    // Wait one runloop so the window is on screen before the spring starts.
                    DispatchQueue.main.async { shown = model.isFloatingOpen }
                } else {
                    shown = false
                }
            }
    }
}
