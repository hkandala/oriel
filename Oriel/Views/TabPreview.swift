#if os(macOS)
    import AppKit
    import HerdrKit
    import SwiftUI

    /// A tab's cards in their layout, as its page draws them in a 1056 × 660 pt page, at a quarter of that size. A card
    /// that draws (the shown tab's, or a floated one) shows its terminal's picture: the IOSurface libghostty's layer
    /// shows, shared, not copied, and read again 5 times a second while the preview is open (`TerminalPicture`), so it
    /// costs nothing while none is. Any other card (another tab, whose surface draws nothing or was let go) shows its
    /// screen's text, read each second (design: hover card).
    struct TabPreview: View {
        let tree: SplitNode
        let page: Page
        /// Screen text for the panes with no picture.
        let screens: [String: String]
        @Environment(\.look) private var look
        /// The terminals' text size: text cards draw at a quarter of it, as the pictures do.
        @AppStorage("fontSize") private var fontSize = PaneTerminal.fontSize
        private static let scale: CGFloat = 0.25
        /// With its 2 pt padding, the hover card's width inside its own (268 pt).
        private static let size = CGSize(width: 264, height: 165)

        /// The picture libghostty's layer shows now (an IOSurface), while the terminal draws (its window's shown tab or
        /// floated: others keep an old picture) and once it showed the pane (a lazy page's terminal that never streamed
        /// is blank). Never makes a terminal.
        static func picture(_ pane: HostStore.Pane?, _ page: Page) -> (terminal: PaneTerminal, picture: Any)? {
            guard let terminal = pane?.terminalID.flatMap({ page.terminals.terminals([$0]).first }), terminal.revealed,
                  terminal.inView, let picture = terminal.view.picture,
                  terminal.view.frame.width > 0 else { return nil }
            return (terminal, picture)
        }

        var body: some View {
            let area = CGRect(x: 0, y: 0, width: Self.size.width / Self.scale, height: Self.size.height / Self.scale)
            let zoomed = page.zoomedPaneID.flatMap { tree.paneIDs.contains($0) ? $0 : nil }
            let cards = Parts(tree, in: area, held: [:]).cards.filter { zoomed == nil || $0.id == zoomed }
            ZStack(alignment: .topLeading) {
                ForEach(cards, id: \.id) { card in
                    let rect = zoomed == nil ? card.rect : area
                    self.card(card.id)
                        .frame(width: rect.width * Self.scale, height: rect.height * Self.scale)
                        // By layout, not `.offset`, which leaves the accessibility frame at the corner.
                        .padding(.leading, rect.minX * Self.scale).padding(.top, rect.minY * Self.scale)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .padding(gap * Self.scale)
            // The opaque window (Classic's) under the cards: the card's material would make them lighter than the
            // page's.
            .background(Look(style: .classic, dark: look.dark).window, in: .rect(cornerRadius: 6, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hovercard.preview")
        }

        private func card(_ id: String) -> some View {
            let pane = page.store.pane(id), picture = Self.picture(pane, page), inset = 10 * Self.scale
            let shape = RoundedRectangle(cornerRadius: 10 * Self.scale, style: .continuous)
            let edge = look.edge(keyboard: false)
            // Picture and text alike as the page's card at a quarter: cells at a quarter of their size, from the top
            // left, cut at the card's edge. Text past its card would widen the card's accessibility frame, though
            // clipped, so it keeps only the cells that fit (SF Mono: 0.6 em wide, lines about 1.2 em).
            return GeometryReader { proxy in
                let room = CGSize(width: max(proxy.size.width - 2 * inset, 0),
                                  height: max(proxy.size.height - 2 * inset, 0))
                Group {
                    if let (terminal, _) = picture {
                        TerminalPicture(terminal: terminal, scale: Self.scale)
                    } else if let text = screens[id] {
                        let size = CGFloat(fontSize) * Self.scale
                        let columns = Int(room.width / (size * 0.6)), rows = Int(room.height / (size * 1.2))
                        Text(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(rows)
                            .map { $0.prefix(columns) }.joined(separator: "\n"))
                            .font(.system(size: size, design: .monospaced))
                    }
                }
                .frame(width: room.width, height: room.height, alignment: .topLeading)
                .padding(inset)
            }
            .clipShape(shape)
            .background(shape.fill(look.cardFill))
            .overlay(shape.stroke(edge.color, lineWidth: edge.width / 2))
            .accessibilityElement()
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(pane?.cardTitle ?? "terminal")
            .accessibilityValue(picture != nil ? "picture" : screens[id] != nil ? "text" : "empty")
            .accessibilityIdentifier("hovercard.preview.\(id)")
        }
    }

    /// Shows a terminal's picture: libghostty's IOSurface set as a layer's contents, from the top left at `scale` of
    /// its size, read again 5 times a second while it is in a window. In AppKit: a SwiftUI timeline laid out the whole
    /// window at each tick (about 20 % CPU in a debug build). A layer-hosting view, so AppKit never draws over it.
    private struct TerminalPicture: NSViewRepresentable {
        let terminal: PaneTerminal
        let scale: CGFloat

        func makeNSView(context _: Context) -> Picture {
            Picture(terminal: terminal, scale: scale)
        }

        func updateNSView(_ view: Picture, context _: Context) {
            view.terminal = terminal
        }

        final class Picture: NSView {
            var terminal: PaneTerminal
            private let scale: CGFloat
            private var timer: Timer?

            init(terminal: PaneTerminal, scale: CGFloat) {
                self.terminal = terminal
                self.scale = scale
                super.init(frame: .zero)
                layer = CALayer()
                wantsLayer = true
                layer?.contentsGravity = .topLeft
                layer?.masksToBounds = true
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                nil
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                timer?.invalidate()
                timer = nil
                guard window != nil else { return }
                show()
                timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.show() }
                }
            }

            private func show() {
                layer?.contentsScale = (terminal.view.layer?.contentsScale ?? 2) / scale
                layer?.contents = terminal.view.picture
            }
        }
    }
#endif
