import SwiftUI

@MainActor
@Observable
final class NotchViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case workspace = "Workspace", insights = "Insights", settings = "Settings"
        var id: Self { self }
    }

    var geometry: NotchGeometry = NotchGeometry.preferredScreen().map(NotchGeometry.make) ??
        NotchGeometry(screenFrame: .zero, hasNotch: false, notchSize: CGSize(width: 190, height: 30), topY: 0)
    private(set) var isExpanded = false
    /// Opened with the hotkey: stays open until dismissed instead of closing when the mouse leaves.
    private(set) var isPinned = false
    var tab: Tab = .workspace

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

    /// A touch of bounce on the way out, none on the way back in, like the Dynamic Island.
    static let expandAnimation = Animation.spring(duration: 0.48, bounce: 0.2)
    static let collapseAnimation = Animation.spring(duration: 0.34, bounce: 0)

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
        isExpanded ? collapse() : expand(pinned: true)
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
