import AppKit

enum NotchGeometry {
    static let expandedWidth: CGFloat = 480
    static let collapsedPillWidth: CGFloat = 200
    static let collapsedPillHeight: CGFloat = 32

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    static func collapsedRect(on screen: NSScreen) -> NSRect {
        if hasNotch(screen) {
            let insets = screen.safeAreaInsets
            let notchHeight = insets.top
            let leftW = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightW = screen.auxiliaryTopRightArea?.width ?? 0
            let notchWidth = screen.frame.width - leftW - rightW
            let x = screen.frame.minX + leftW
            let y = screen.frame.maxY - notchHeight
            return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
        } else {
            let x = screen.frame.midX - collapsedPillWidth / 2
            let y = screen.frame.maxY - collapsedPillHeight
            return NSRect(x: x, y: y, width: collapsedPillWidth, height: collapsedPillHeight)
        }
    }

    static func expandedRect(on screen: NSScreen, contentHeight: CGFloat) -> NSRect {
        let collapsed = collapsedRect(on: screen)
        let totalHeight = collapsed.height + contentHeight
        let x = screen.frame.midX - expandedWidth / 2
        let y = collapsed.maxY - totalHeight
        return NSRect(x: x, y: y, width: expandedWidth, height: totalHeight)
    }

    static func hotZoneRect(on screen: NSScreen) -> NSRect {
        collapsedRect(on: screen).insetBy(dx: -40, dy: -8)
    }
}
