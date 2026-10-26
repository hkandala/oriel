#if os(macOS)
    import AppKit
    import HerdrKit
    import SwiftUI

    /// A tab's page at the size it is given: its cards in herdr's layout (or its zoomed card), each with its terminal
    /// at its place in the card, live or its snapshot (`live`), scaled from the strip's page (`size`).
    struct Miniature: View {
        let tab: HostStore.Tab
        let page: Page
        let size: CGSize
        /// The terminals that stream and draw here; the others show their snapshot.
        let live: Set<String>

        var body: some View {
            GeometryReader { proxy in
                let scale = proxy.size.width / size.width, area = CGRect(origin: .zero, size: size)
                if let tree = tab.tree {
                    let zoomed = page.zoomedPaneID.flatMap { tree.paneIDs.contains($0) ? $0 : nil }
                    let cards = Parts(tree, in: area, held: [:]).cards.filter { zoomed == nil || $0.id == zoomed }
                    ZStack(alignment: .topLeading) {
                        ForEach(cards, id: \.id) { card in
                            let rect = zoomed == nil ? card.rect : area
                            MiniCard(id: card.id, page: page, size: rect.size, scale: scale, live: live)
                                .frame(width: rect.width * scale, height: rect.height * scale)
                                .position(x: rect.midX * scale, y: rect.midY * scale)
                        }
                    }
                }
            }
        }
    }

    /// A card at `scale`: its fill and edge, and its terminal where the page's card has it (under the header, 10 pt
    /// in, 8 pt up from the bottom): live (its snapshot until it drew), or its snapshot, or for a terminal never shown
    /// the fill.
    /// A floated pane's shows the float icon.
    private struct MiniCard: View {
        let id: String
        let page: Page
        /// The card in the strip's page.
        let size: CGSize
        let scale: CGFloat
        let live: Set<String>
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
                    } else if let pane, let id = pane.terminalID {
                        let isLive = live.contains(id)
                        // Not made for a tile that is not live (a view and a session each, while it scrolls).
                        let view = isLive ? page.terminal(pane) : page.terminals.terminals([id]).first
                        ZStack {
                            Color.clear
                            if isLive, let view {
                                // Its snapshot is its picture until it drew (`dropPicture`).
                                MiniTerminal(terminal: view, size: terminal)
                            } else if let snapshot = view?.snapshot {
                                Snapshot(surface: snapshot)
                            }
                        }
                        .accessibilityElement()
                        // A group's value does not reach XCUITest; static text's does (as the pane card's).
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier("overview.card.\(pane.id)")
                        // e2e: and its snapshot's width in pixels.
                        .accessibilityValue("\(view?.pictured != true ? "loading" : isLive ? "live" : "snapshot") "
                            + "\(view?.snapshot?.width ?? 0)")
                        .frame(width: terminal.width * scale, height: terminal.height * scale)
                        .padding(.leading, PaneCard.inset * scale)
                        .padding(.top, PaneCard.header * scale)
                    }
                }
        }
    }

    /// A terminal's snapshot, stretched to the tile's terminal (it keeps the terminal's proportions).
    private struct Snapshot: NSViewRepresentable {
        let surface: IOSurface

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.contentsGravity = .resize
            return view
        }

        func updateNSView(_ view: NSView, context _: Context) {
            view.layer?.contents = surface
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

        static func dismantleNSView(_ mini: Mini, coordinator _: ()) {
            Mini.most = max(Mini.most, mini.sizes)
        }

        final class Mini: NSView {
            var size = CGSize.zero
            private var fitting: Task<Void, Never>?
            /// e2e (`-recordMotion YES`): the most sizes a miniature took, the zoom's among them (many when it grows
            /// frame by frame, one or two when it jumps).
            static var most = 0
            private(set) var sizes = 0

            override var isFlipped: Bool {
                true
            }

            override func hitTest(_: NSPoint) -> NSView? {
                nil
            }

            override func setFrameSize(_ newSize: NSSize) {
                super.setFrameSize(newSize)
                sizes += 1
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
