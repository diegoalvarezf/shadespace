import AppKit

/// Panel content view that receives file drags with AppKit's NSDraggingDestination.
/// SwiftUI's `onDrop` proved unreliable in a non-activating panel that toggles
/// `ignoresMouseEvents`, so drags are handled here and SwiftUI only draws the zones.
@MainActor
final class DropCatcherView: NSView {
    var onEnter: (([URL]) -> Void)?
    /// Pointer position in this view's coordinates while dragging.
    var onMove: ((NSPoint) -> Void)?
    var onExit: (() -> Void)?
    /// Returns whether the drop was accepted.
    var onDrop: (([URL]) -> Bool)?
    /// Area (in this view's coordinates) that accepts drops; the rest of the panel is transparent.
    var acceptsDrop: ((NSPoint) -> Bool)?

    private var isInside = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        leave()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isInside && !Self.fileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(from: sender)
        let accepted = onDrop?(urls) ?? false
        isInside = false
        return accepted
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        leave()
    }

    // MARK: - Private

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let urls = Self.fileURLs(from: sender)
        guard !urls.isEmpty, acceptsDrop?(point) ?? true else {
            leave()
            return []
        }
        if !isInside {
            isInside = true
            onEnter?(urls)
        }
        onMove?(point)
        return .copy
    }

    private func leave() {
        guard isInside else { return }
        isInside = false
        onExit?()
    }

    private static func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
