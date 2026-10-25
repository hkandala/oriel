#if os(macOS)
    import AppKit
    import HerdrKit
    import SwiftUI

    /// A tab's page at the size it is given: its cards in herdr's layout (or its zoomed card), each with its terminal
    /// live at its place in the card, scaled from the strip's page (`size`).
    struct Miniature: View {
        let tab: HostStore.Tab
        let page: Page
        let size: CGSize

        var body: some View {
            GeometryReader { proxy in
                let scale = proxy.size.width / size.width, area = CGRect(origin: .zero, size: size)
                if let tree = tab.tree {
                    let zoomed = page.zoomedPaneID.flatMap { tree.paneIDs.contains($0) ? $0 : nil }
                    let cards = Parts(tree, in: area, held: [:]).cards.filter { zoomed == nil || $0.id == zoomed }
                    ZStack(alignment: .topLeading) {
                        ForEach(cards, id: \.id) { card in
                            let rect = zoomed == nil ? card.rect : area
                            MiniCard(id: card.id, page: page, size: rect.size, scale: scale)
                                .frame(width: rect.width * scale, height: rect.height * scale)
                                .position(x: rect.midX * scale, y: rect.midY * scale)
                        }
                    }
                }
            }
        }
    }

    /// A card at `scale`: its fill and edge, and its terminal where the page's card has it (under the header, 10 pt
    /// in, 8 pt up from the bottom). A floated pane's shows the float icon.
    private struct MiniCard: View {
        let id: String
        let page: Page
        /// The card in the strip's page.
        let size: CGSize
        let scale: CGFloat
        @Environment(\.look) private var look

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 10 * scale, style: .continuous),
                edge = look.edge(keyboard: false)
            let pane = page.store.pane(id)
            let terminal = CGSize(width: max(size.width - 2 * PaneCard.inset, 1),
                                  height: max(size.height - PaneCard.header - gap, 1))
            shape.fill(look.cardFill)
                .overlay(shape.stroke(edge.color, lineWidth: edge.width))
                .overlay(alignment: .topLeading) {
                    if let pane, page.floats(pane) {
                        Image(systemName: "pip").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let view = pane.flatMap(page.terminal) {
                        MiniTerminal(terminal: view, size: terminal)
                            .frame(width: terminal.width * scale, height: terminal.height * scale)
                            .padding(.leading, PaneCard.inset * scale)
                            .padding(.top, PaneCard.header * scale)
                    }
                }
        }
    }

    /// The pane's own terminal view, drawn at the miniature's size: its bounds are the card's terminal size, so
    /// AppKit scales the layer and libghostty keeps its grid (herdr's PTY never resizes). Clicks and scrolls go to
    /// the tile. The newest host adopts the view, as `TerminalHost`'s do.
    struct MiniTerminal: NSViewRepresentable {
        let terminal: PaneTerminal
        let size: CGSize

        func makeNSView(context _: Context) -> Mini {
            let mini = Mini()
            mini.size = size
            mini.wantsLayer = true
            mini.clipsToBounds = true
            mini.addSubview(terminal.view)
            return mini
        }

        func updateNSView(_ mini: Mini, context _: Context) {
            mini.size = size
            mini.fit()
        }

        final class Mini: NSView {
            var size = CGSize.zero
            private var fitting: Task<Void, Never>?

            override var isFlipped: Bool {
                true
            }

            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }

            override func setFrameSize(_ newSize: NSSize) {
                super.setFrameSize(newSize)
                fit()
            }

            override func viewDidEndLiveResize() {
                super.viewDidEndLiveResize()
                fitting?.cancel()
                fit(now: true)
            }

            /// The bounds at once; the terminal's size as the card's host fits it: at once for one with no grid yet
            /// (it opens at this size), else 150 ms after the last change, so a window drag reflows nothing meanwhile.
            func fit(now: Bool = false) {
                guard !frame.isEmpty, size.width > 0, size.height > 0 else { return }
                setBoundsSize(size)
                fitting?.cancel()
                guard let view = subviews.first as? PaneSurfaceView, view.frame.size != size else { return }
                guard now || view.terminal?.grid == nil || view.frame.isEmpty else {
                    fitting = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(150))
                        if !Task.isCancelled {
                            self?.fit(now: true)
                        }
                    }
                    return
                }
                // Before libghostty hears of the size, as the card's host does.
                view.terminal?.hold()
                view.frame = CGRect(origin: .zero, size: size)
            }
        }
    }
#endif
