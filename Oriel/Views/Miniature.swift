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
    /// in, 8 pt up from the bottom): live, or its snapshot until it drew (none for a terminal never shown: the fill).
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
                    } else if let pane, let id = pane.terminalID, let view = live.contains(id) ? page.terminal(pane)
                        // Not made for a tile that is not live (a view and a session each, while it scrolls).
                        : page.terminals.terminals([id]).first
                    {
                        let drawn = live.contains(id) && view.ready
                        ZStack {
                            // Under a live one too, until it drew: a terminal's background may be clear.
                            if !drawn, let snapshot = view.snapshot {
                                Snapshot(surface: snapshot)
                            }
                            if live.contains(id) {
                                MiniTerminal(terminal: view, size: terminal, alpha: drawn ? 1 : 0)
                            }
                        }
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
        /// 0 until it drew: its snapshot shows meanwhile. On the view, as `TerminalHost`'s dim.
        let alpha: CGFloat

        func makeNSView(context _: Context) -> Mini {
            let mini = Mini()
            mini.size = size
            mini.wantsLayer = true
            mini.clipsToBounds = true
            mini.addSubview(terminal.view)
            return mini
        }

        func updateNSView(_ mini: Mini, context _: Context) {
            mini.alphaValue = alpha
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

    /// e2e (`-recordMotion YES`): the overview's frames, as "‹frames› ‹hitches› ‹snapshots›": a hitch is a display
    /// frame the main
    /// thread delivered over 25 ms after the one before (a dropped frame at 60 Hz), so a scroll's hitch rate shows.
    struct FrameMeter: NSViewRepresentable {
        func makeNSView(context _: Context) -> Meter {
            Meter()
        }

        func updateNSView(_: Meter, context _: Context) {}

        final class Meter: NSView {
            private var link: CADisplayLink?
            private var last: CFTimeInterval = 0
            private var frames = 0, hitches = 0

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                link?.invalidate()
                link = window == nil ? nil : displayLink(target: self, selector: #selector(tick))
                link?.add(to: .main, forMode: .common)
                setAccessibilityElement(true)
                setAccessibilityRole(.staticText)
                setAccessibilityIdentifier("overview.frames")
            }

            @objc private func tick(_ link: CADisplayLink) {
                if last > 0 {
                    frames += 1
                    hitches += link.timestamp - last > 0.025 ? 1 : 0
                }
                last = link.timestamp
                setAccessibilityValue("\(frames) \(hitches) \(PaneTerminal.snapshots.count)")
            }
        }
    }
#endif
