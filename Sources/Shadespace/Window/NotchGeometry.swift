import AppKit

enum NotchGeometry {
    static let expandedWidth: CGFloat = 380
    static let expandedContentHeight: CGFloat = 170
    static let collapsedPillWidth: CGFloat = 200
    static let collapsedPillHeight: CGFloat = 37
    static let liveStripHeight: CGFloat = 26
    // How far the panel extends into the menubar on each side of the notch
    static let sideExtension: CGFloat = 48
    static let peekWidth: CGFloat = 320
    static let peekContentHeight: CGFloat = 34
    // Room around the island for the spring overshoot so it never gets clipped by the panel
    static let canvasMargin: CGFloat = 12

    /// Prefers the built-in display with a notch; falls back to the main display (external monitor,
    /// lid closed, or a Mac without a notch), where the island becomes a pill at the top edge.
    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    static func physicalNotchHeight(on screen: NSScreen) -> CGFloat {
        hasNotch(screen) ? screen.safeAreaInsets.top : 0
    }

    static func leftExtension(on screen: NSScreen) -> CGFloat {
        guard hasNotch(screen) else { return 0 }
        return min(sideExtension, (screen.auxiliaryTopLeftArea?.width ?? 0) - 4)
    }

    static func rightExtension(on screen: NSScreen) -> CGFloat {
        guard hasNotch(screen) else { return 0 }
        return min(sideExtension, (screen.auxiliaryTopRightArea?.width ?? 0) - 4)
    }

    static func physicalNotchWidth(on screen: NSScreen) -> CGFloat {
        let leftW = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightW = screen.auxiliaryTopRightArea?.width ?? 0
        return screen.frame.width - leftW - rightW
    }

    static func collapsedRect(on screen: NSScreen) -> NSRect {
        if hasNotch(screen) {
            let notchH = physicalNotchHeight(on: screen)
            let extL = leftExtension(on: screen)
            let extR = rightExtension(on: screen)
            let notchW = physicalNotchWidth(on: screen)
            let totalWidth = notchW + extL + extR
            // Center on screen midpoint (same as expanded)
            let x = screen.frame.midX - totalWidth / 2
            let totalHeight = notchH + liveStripHeight
            let y = screen.frame.maxY - totalHeight
            return NSRect(x: x, y: y, width: totalWidth, height: totalHeight)
        } else {
            let x = screen.frame.midX - collapsedPillWidth / 2
            let y = screen.frame.maxY - collapsedPillHeight
            return NSRect(x: x, y: y, width: collapsedPillWidth, height: collapsedPillHeight)
        }
    }

    static func expandedSize(on screen: NSScreen) -> CGSize {
        CGSize(width: expandedWidth, height: collapsedRect(on: screen).height + expandedContentHeight)
    }

    /// Resting size when the island is hidden: exactly the camera housing, so the black shape
    /// disappears into the hardware. Without a notch there is nothing to draw.
    static func hiddenSize(on screen: NSScreen) -> CGSize {
        hasNotch(screen)
            ? CGSize(width: physicalNotchWidth(on: screen), height: physicalNotchHeight(on: screen))
            : CGSize(width: collapsedPillWidth, height: 0)
    }

    /// Live activity (e.g. a running Pomodoro): notch height, with content beside the camera.
    static func activitySize(on screen: NSScreen) -> CGSize {
        hasNotch(screen)
            ? CGSize(width: collapsedRect(on: screen).width, height: physicalNotchHeight(on: screen))
            : CGSize(width: 150, height: 26)
    }

    /// Top part of a peek alert: the notch itself when hidden, the full collapsed row otherwise.
    static func peekHeaderHeight(on screen: NSScreen, liveActivity: Bool) -> CGFloat {
        liveActivity ? collapsedRect(on: screen).height : max(physicalNotchHeight(on: screen), 6)
    }

    /// Size used while a transient alert is showing: wider than the notch, one row taller.
    static func peekSize(on screen: NSScreen, liveActivity: Bool) -> CGSize {
        let collapsed = collapsedRect(on: screen)
        return CGSize(width: max(collapsed.width, peekWidth),
                      height: peekHeaderHeight(on: screen, liveActivity: liveActivity) + peekContentHeight)
    }

    /// Fixed panel frame: large enough for every island size, pinned to the top-center of the screen.
    /// The panel never resizes; SwiftUI animates the island inside it.
    static func canvasRect(on screen: NSScreen) -> NSRect {
        let collapsed = collapsedRect(on: screen)
        let expanded = expandedSize(on: screen)
        let width = max(collapsed.width, expanded.width, peekWidth) + canvasMargin * 2
        let height = max(collapsed.height, expanded.height) + canvasMargin
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height,
                      width: width, height: height)
    }
}
