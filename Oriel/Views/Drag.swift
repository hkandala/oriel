#if os(macOS)
    import AppKit
    import HerdrKit
    import SwiftUI
    import UniformTypeIdentifiers

    /// What a drag in a window carries (phase 18). The page holds it; the pasteboard only routes the drag to the
    /// app's drop targets.
    enum Dragged: Equatable {
        case pane(String)
        case tab(String)
        case workspace(String)

        var paneID: String? {
            if case let .pane(id) = self {
                id
            } else {
                nil
            }
        }
    }

    extension UTType {
        static let orielDrag = UTType(exportedAs: "dev.hkandala.oriel.drag")
    }

    /// The system drag: an AppKit session from the window's content view, which outlives the view that started it
    /// (spring-loading pages the strip away from the dragged card, and a `DragGesture` would be cancelled). It gives
    /// the preview and Esc; its end clears the page's drag, whatever view is left.
    @MainActor
    final class DragSource: NSObject, NSDraggingSource {
        private static let shared = DragSource()
        private weak var page: Page?

        /// From a `DragGesture`'s change: starts the drag once (the session takes the mouse from there). `frame`: the
        /// dragged view in the window (SwiftUI's global space), snapshotted as the preview.
        static func begin(_ item: Dragged, page: Page, frame: CGRect) {
            // The gesture runs while SwiftUI handles the drag event.
            // Not on a stopped session's last rows and cards: a drop could not write.
            guard page.dragging == nil, page.store.state == .live, let event = NSApp.currentEvent,
                  event.type == .leftMouseDragged,
                  let view = event.window?.contentView else { return }
            let pasteboard = NSPasteboardItem()
            pasteboard.setString("", forType: NSPasteboard.PasteboardType(UTType.orielDrag.identifier))
            let dragging = NSDraggingItem(pasteboardWriter: pasteboard)
            let rect = view.isFlipped ? frame : NSRect(x: frame.minX, y: view.bounds.height - frame.maxY,
                                                       width: frame.width, height: frame.height)
            if case .pane = item, let card = snapshot(view, rect) {
                let lifted = lift(card, from: rect, under: view.convert(event.locationInWindow, from: nil),
                                  flipped: view.isFlipped)
                dragging.setDraggingFrame(lifted.frame, contents: lifted.image)
            } else {
                dragging.setDraggingFrame(rect, contents: snapshot(view, rect))
            }
            shared.page = page
            page.dragging = item
            view.beginDraggingSession(with: [dragging], event: event, source: shared)
        }

        private static func snapshot(_ view: NSView, _ rect: NSRect) -> NSImage? {
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
            view.cacheDisplay(in: rect, to: bitmap)
            let image = NSImage(size: rect.size)
            image.addRepresentation(bitmap)
            return image
        }

        /// A dragged card as a lifted card (user): one small card shape, 240 × 150 pt, filled with the card's top
        /// (header and terminal) scaled to cover it, its corners rounded, at 0.85 with a soft shadow; the pointer sits
        /// over the header where it grabbed it. The terminal's Metal layer may not draw into the snapshot: the card's
        /// fill shows there then.
        private static func lift(_ card: NSImage, from rect: NSRect, under point: NSPoint,
                                 flipped: Bool) -> (frame: NSRect, image: NSImage)
        {
            let size = NSSize(width: 240, height: 150), margin: CGFloat = 20
            let scale = max(size.width / rect.width, size.height / rect.height)
            // The grab point from the lifted card's top left, in its scaled points.
            let grab = NSPoint(x: min((point.x - rect.minX) * scale, size.width - 8),
                               y: min((flipped ? point.y - rect.minY : rect.maxY - point.y) * scale, size.height - 8))
            let frame = NSRect(x: point.x - grab.x - margin,
                               y: (flipped ? point.y - grab.y : point.y - (size.height - grab.y)) - margin,
                               width: size.width + 2 * margin, height: size.height + 2 * margin)
            let image = NSImage(size: frame.size, flipped: false) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                let inside = NSRect(origin: NSPoint(x: margin, y: margin), size: size)
                context.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: CGColor(gray: 0, alpha: 0.35))
                context.setAlpha(0.85)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                NSBezierPath(roundedRect: inside, xRadius: 10, yRadius: 10).addClip()
                // Top aligned: the header always shows.
                card.draw(in: NSRect(x: margin, y: margin + size.height - rect.height * scale,
                                     width: rect.width * scale, height: rect.height * scale))
                context.endTransparencyLayer()
                return true
            }
            return (frame, image)
        }

        nonisolated func draggingSession(_: NSDraggingSession,
                                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation
        {
            context == .withinApplication ? .move : []
        }

        nonisolated func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
            MainActor.assumeIsolated {
                page?.dragging = nil
                page = nil
            }
        }
    }

    /// Holding a dragged pane over a tab's capsule or a workspace's row 0.65 s selects it (Rex's spring-loading), and a
    /// pane or a tab over the workspace button opens its menu; not after the drag ended (a late update).
    func springTask(_ page: Page, _ select: @escaping () -> Void) -> Task<Void, Never> {
        Task {
            if await (try? Task.sleep(for: .milliseconds(650))) != nil, page.dragging != nil {
                select()
            }
        }
    }

    enum DropTarget {
        /// A card: its center (nil) or an edge.
        case card(String, edge: Heading?)
        case tab(String)
        /// A new tab or a new workspace.
        case move(Destination)
    }

    struct DropIndicator: View {
        var radius: CGFloat = 10

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(Color.accentColor.opacity(0.2)).overlay(shape.strokeBorder(Color.accentColor, lineWidth: 2))
                .allowsHitTesting(false)
                .accessibilityElement().accessibilityLabel("Drop target").accessibilityIdentifier("drop.indicator")
        }
    }

    /// A card's drop zones: the outer quarter on each side is that edge (the nearest one in a corner), the rest is
    /// the center (nil).
    func dropEdge(_ point: CGPoint, in size: CGSize) -> Heading? {
        let across = point.x / max(size.width, 1), down = point.y / max(size.height, 1)
        let distances: [(Heading, Double)] = [(.left, across), (.right, 1 - across), (.up, down), (.down, 1 - down)]
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 < 0.25 else { return nil }
        return nearest.0
    }

    /// A pane dragged over a card: the center of another card in its tab swaps, an edge of any other card places it
    /// beside; its own card and another tab's center are not targets.
    struct CardDrop: DropDelegate {
        let paneID: String
        let page: Page
        let size: CGSize
        @Binding var zone: Heading??

        func validateDrop(info _: DropInfo) -> Bool {
            page.dragging?.paneID != nil
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            let target = target(info.location)
            if zone != target {
                withAnimation(.highlight) { zone = target }
            }
            return DropProposal(operation: target == nil ? .forbidden : .move)
        }

        func dropExited(info _: DropInfo) {
            withAnimation(.highlight) { zone = nil }
        }

        func performDrop(info: DropInfo) -> Bool {
            zone = nil
            guard let dragged = page.dragging?.paneID, let edge = target(info.location) else { return false }
            Task { await page.drop(dragged, on: .card(paneID, edge: edge)) }
            return true
        }

        /// The edge or the center (`.some(nil)`), nil when not a target.
        private func target(_ point: CGPoint) -> Heading?? {
            guard let dragged = page.dragging?.paneID, dragged != paneID,
                  let source = page.store.pane(dragged), let pane = page.store.pane(paneID) else { return nil }
            let edge = dropEdge(point, in: size)
            return edge == nil && source.tabID != pane.tabID ? nil : .some(edge)
        }
    }

    /// A pane dragged over a place with one target (the `+`, the tab track's end, a sidebar's empty space, a workspace
    /// menu row), or a tab over a new tab in another workspace (a workspace menu row).
    struct PaneDrop: DropDelegate {
        let page: Page
        let target: DropTarget
        @Binding var over: Bool

        func validateDrop(info _: DropInfo) -> Bool {
            takes
        }

        func dropEntered(info _: DropInfo) {
            if takes {
                withAnimation(.highlight) { over = true }
            }
        }

        func dropUpdated(info _: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func dropExited(info _: DropInfo) {
            withAnimation(.highlight) { over = false }
        }

        func performDrop(info _: DropInfo) -> Bool {
            over = false
            switch (page.dragging, target) {
            case let (.pane(id), _):
                Task { await page.drop(id, on: target) }
            case let (.tab(id), .move(.newTab(workspaceID, _))) where takes:
                Task { await page.drop(tab: id, on: workspaceID) }
            default:
                return false
            }
            return true
        }

        private var takes: Bool {
            switch (page.dragging, target) {
            case (.pane, _): true
            case let (.tab(id), .move(.newTab(workspaceID, _))): page.store.workspace(of: id)?.id != workspaceID
            default: false
            }
        }
    }

    /// A drag held over the collapsed sidebar's workspace button opens the workspace menu after 0.65 s, so the drop
    /// can go on a row there; a drop on the button itself is none. Any drag here is a pane's or a tab's: workspace
    /// rows are in the sidebar, which is closed while the button shows.
    struct SpringDrop: DropDelegate {
        let page: Page
        @Binding var over: Bool
        @Binding var spring: Task<Void, Never>?
        let open: () -> Void

        func validateDrop(info _: DropInfo) -> Bool {
            page.dragging != nil
        }

        func dropEntered(info _: DropInfo) {
            withAnimation(.highlight) { over = true }
            spring?.cancel()
            spring = springTask(page, open)
        }

        func dropExited(info _: DropInfo) {
            spring?.cancel()
            withAnimation(.highlight) { over = false }
        }

        func performDrop(info: DropInfo) -> Bool {
            dropExited(info: info)
            return false
        }
    }

    extension Animation {
        /// A drop target's highlight.
        static let highlight = Animation.easeOut(duration: 0.12)

        /// Rex's insertion timing: 0.22 s on its "production" curve. Tabs and rows slide apart with it; none with
        /// Reduce Motion (from AppKit: a drop delegate has no environment).
        static var slide: Animation? {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil
                : .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.22)
        }
    }

    extension View {
        /// Clears a target's drop state when a drag starts or ends: after a drop, a `dropUpdated` can come after
        /// `performDrop` with no `dropExited` to follow (seen by hand: the highlight stayed), even after the session
        /// ended.
        func clearsDrop(_ page: Page, _ clear: @escaping () -> Void) -> some View {
            onChange(of: page.dragging == nil) { clear() }
        }

        /// Starts a drag of `item` after 4 pt; the view's frame is the preview, or `previewSize` from its top left.
        func dragSource(_ item: Dragged, page: Page, previewSize: CGSize? = nil) -> some View {
            modifier(DragSourceModifier(item: item, page: page, previewSize: previewSize))
        }
    }

    private struct DragSourceModifier: ViewModifier {
        let item: Dragged
        let page: Page
        let previewSize: CGSize?
        @State private var frame = CGRect.zero

        func body(content: Content) -> some View {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in
                    let preview = CGRect(origin: frame.origin, size: previewSize ?? frame.size)
                    DragSource.begin(item, page: page, frame: preview)
                })
        }
    }
#endif
