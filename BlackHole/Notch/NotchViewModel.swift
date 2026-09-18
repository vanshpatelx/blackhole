import SwiftUI

@MainActor
@Observable
final class NotchViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case workspace = "Workspace", insights = "Insights", settings = "Settings"
        var id: Self {
            self
        }
    }

    var geometry: NotchGeometry = .preferredScreen().map(NotchGeometry.make) ??
        NotchGeometry(screenFrame: .zero, hasNotch: false, notchSize: CGSize(width: 190, height: 30), topY: 0)
    private(set) var isExpanded = false
    /// Opened with the hotkey: stays open until dismissed instead of closing when the mouse leaves.
    private(set) var isPinned = false
    var tab: Tab = .workspace
    /// Selected tab in the full dashboard window.
    var dashboardTab: Tab = .workspace

    /// The same workspace, opened beside the floating button on whatever screen it's on.
    private(set) var isFloatingOpen = false
    /// Which way the floating workspace opens from the button, so it can grow out of it.
    var floatingOpensLeft = true
    @ObservationIgnored private(set) var floatingAnchor: NSRect = .zero

    @ObservationIgnored var onOpenDashboard: (() -> Void)?
    @ObservationIgnored var onExpansionChange: ((Bool) -> Void)?
    @ObservationIgnored var onFloatingChange: ((Bool) -> Void)?
    /// Fires whenever the workspace is opened from anywhere.
    @ObservationIgnored var onExpansionVisit: (() -> Void)?

    /// macOS-style motion: a long, gentle ease-out that settles without visible bounce.
    static let expandAnimation = Animation.spring(duration: 0.52, bounce: 0.06)
    static let collapseAnimation = Animation.spring(duration: 0.4, bounce: 0)
    /// Content grows with the shape; it only fades a little faster so it never looks washed out.
    static let contentScaleIn = Animation.spring(duration: 0.52, bounce: 0.04)
    static let contentFadeIn = Animation.easeOut(duration: 0.3).delay(0.03)
    static let contentOut = Animation.easeOut(duration: 0.18)

    func expand(pinned: Bool = false) {
        closeFloating()
        isPinned = isPinned || pinned
        onExpansionVisit?()
        guard !isExpanded else { return }
        withAnimation(Self.expandAnimation) { isExpanded = true }
        onExpansionChange?(true)
    }

    func collapse() {
        isPinned = false
        guard isExpanded else { return }
        withAnimation(Self.collapseAnimation) { isExpanded = false }
        onExpansionChange?(false)
    }

    func toggleFromHotKey() {
        if isExpanded {
            collapse()
        } else {
            expand(pinned: true)
        }
    }

    /// Opens the workspace next to `anchor`, a rect in screen coordinates.
    func openFloating(anchor: NSRect) {
        collapse()
        floatingAnchor = anchor
        onExpansionVisit?()
        guard !isFloatingOpen else { return }
        isFloatingOpen = true
        onFloatingChange?(true)
    }

    func closeFloating() {
        guard isFloatingOpen else { return }
        isFloatingOpen = false
        onFloatingChange?(false)
    }

    func openDashboard() {
        collapse()
        closeFloating()
        onOpenDashboard?()
    }
}
