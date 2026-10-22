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
            dragging.setDraggingFrame(rect, contents: snapshot(view, rect))
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

    /// Holding a dragged pane over a tab's capsule or a workspace's row this long selects it (Rex's spring-loading).
    let springDelay = Duration.milliseconds(650)

    /// Where a drop lands, as the targets see it.
    enum DropTarget {
        /// A card: its center (nil) or an edge.
        case card(String, edge: Heading?)
        case tab(String)
        /// A new tab or a new workspace.
        case move(Destination)
    }

    /// The drop indicator: a rounded rect in the accent at 0.2 with a 2 pt accent stroke.
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
                withAnimation(.easeOut(duration: 0.12)) { zone = target }
            }
            return DropProposal(operation: target == nil ? .forbidden : .move)
        }

        func dropExited(info _: DropInfo) {
            withAnimation(.easeOut(duration: 0.12)) { zone = nil }
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

    /// A pane dragged over a place with one target (the `+`, the tab track's end, a sidebar's empty space).
    struct PaneDrop: DropDelegate {
        let page: Page
        let target: DropTarget
        @Binding var over: Bool

        func validateDrop(info _: DropInfo) -> Bool {
            page.dragging?.paneID != nil
        }

        func dropEntered(info _: DropInfo) {
            withAnimation(.easeOut(duration: 0.12)) { over = true }
        }

        func dropUpdated(info _: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func dropExited(info _: DropInfo) {
            withAnimation(.easeOut(duration: 0.12)) { over = false }
        }

        func performDrop(info _: DropInfo) -> Bool {
            over = false
            guard let id = page.dragging?.paneID else { return false }
            Task { await page.drop(id, on: target) }
            return true
        }
    }

    extension Animation {
        /// Rex's insertion timing: 0.22 s on its "production" curve. Tabs and rows slide apart with it.
        static let slide = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.22)
    }

    extension View {
        /// Clears a target's drop state when the drag ends: after a drop, a `dropUpdated` can come after `performDrop`
        /// with no `dropExited` to follow (seen by hand: the highlight stayed).
        func clearsDrop(_ page: Page, _ clear: @escaping () -> Void) -> some View {
            onChange(of: page.dragging == nil) { _, ended in
                if ended {
                    clear()
                }
            }
        }

        /// Starts a drag of `item` after 4 pt; the view's frame is the preview.
        func dragSource(_ item: Dragged, page: Page) -> some View {
            modifier(DragSourceModifier(item: item, page: page))
        }
    }

    private struct DragSourceModifier: ViewModifier {
        let item: Dragged
        let page: Page
        @State private var frame = CGRect.zero

        func body(content: Content) -> some View {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in
                    DragSource.begin(item, page: page, frame: frame)
                })
        }
    }
#endif
