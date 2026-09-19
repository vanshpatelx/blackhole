import AppKit

/// Screen-space measurements for the notch (or a stand-in on displays without one).
struct NotchGeometry: Equatable {
    /// Screen the panel lives on.
    let screenFrame: NSRect
    let hasNotch: Bool
    /// Size of the hardware notch, or of the virtual notch drawn under the menu bar.
    let notchSize: CGSize
    /// Top edge of the panel in screen coordinates. Screen top for notched displays,
    /// just below the menu bar otherwise.
    let topY: CGFloat

    /// Width of the concave flare where the expanded shape meets the top of the screen.
    static let flare: CGFloat = 14
    /// Black border between the cards and the edge of the panel, on the sides and bottom.
    static let inset: CGFloat = 10
    /// Width of the card row itself.
    static let contentWidth: CGFloat = 1016
    static let expandedWidth: CGFloat = contentWidth + 2 * (flare + inset)
    static let cardsHeight: CGFloat = 266
    /// Extra transparent room around the drawn shape so shadows aren't clipped.
    static let shadowPadding: CGFloat = 36

    var expandedSize: CGSize {
        CGSize(width: Self.expandedWidth, height: topBarHeight + Self.cardsHeight)
    }

    var topBarHeight: CGFloat {
        max(notchSize.height, 44)
    }

    var panelFrame: NSRect {
        let w = expandedSize.width + Self.shadowPadding * 2
        let h = expandedSize.height + Self.shadowPadding
        return NSRect(x: screenFrame.midX - w / 2, y: topY - h, width: w, height: h)
    }

    /// Screen rect for a shape of `size` hanging from the top center.
    func rect(for size: CGSize) -> NSRect {
        NSRect(x: screenFrame.midX - size.width / 2, y: topY - size.height, width: size.width, height: size.height)
    }

    /// Where hovering opens the panel. Slightly wider than the notch so it's easy to hit.
    var hoverZone: NSRect {
        let zoneHeight = hasNotch ? notchSize.height : (screenFrame.maxY - topY)
        let w = notchSize.width + 24
        return NSRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - zoneHeight - 2, width: w, height: zoneHeight + 2)
    }

    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    static func make(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(screenFrame: frame, hasNotch: true, notchSize: CGSize(width: width, height: inset), topY: frame.maxY)
        }
        let menuBar = max(frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchGeometry(screenFrame: frame, hasNotch: false, notchSize: CGSize(width: 190, height: 30), topY: frame.maxY - menuBar)
    }
}
