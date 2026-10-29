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

/// A card at `scale`: its fill and edge, and what the page's card shows under its header: its terminal (10 pt in,
/// 8 pt up from the bottom) live (its snapshot until it drew), or its snapshot, or for a terminal never shown the
/// fill; any other card's own view, live, once the strip made it (a browser's page, a chat), else its kind's
/// symbol. A floated pane's shows the float icon.
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
        let pane = page.store.pane(id), header = page.headerHeight(pane)
        let terminal = CGSize(width: max(size.width - 2 * PaneCard.inset, 1),
                              height: max(size.height - header - gap, 1))
        let content = CGSize(width: size.width, height: max(size.height - header, 1))
        shape.fill(look.cardFill)
            .overlay(shape.stroke(edge.color, lineWidth: edge.width))
            .overlay(alignment: .topLeading) {
                if let pane, page.floats(pane) || pane.plugin.map({ $0.kind != .browser }) == true {
                    // A plugin's card stays in its card: its symbol here.
                    Image(systemName: page.floats(pane) ? "pip" : pane.iconID).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let pane, pane.browser != nil || page.shownChat(pane) != nil {
                    // Not a terminal: its own view once the strip made it, else its kind's symbol. A tile makes no
                    // web view, proxy or transcript read: unlike a terminal's, it has no cap to keep.
                    if let browser = pane.terminalID.flatMap(page.terminals.built) {
                        // Its web view moves here, as a terminal's does, and back to the card after.
                        scaled(BrowserCard(browser: browser).miniCard(pane.id, "browser"), content, under: header)
                    } else if let chat = page.shownChat(pane), !chat.history.entries.isEmpty {
                        scaled(ChatView(chat: chat, page: page, terminal: nil).miniCard(pane.id, "chat"), content,
                               under: header)
                    } else {
                        Image(systemName: pane.browser != nil ? "globe" : "bubble.left.and.bubble.right")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .miniCard(pane.id, "symbol")
                    }
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
                    // e2e: and its snapshot's width in pixels.
                    .miniCard(pane.id, "\(view?.pictured != true ? "loading" : isLive ? "live" : "snapshot") "
                        + "\(view?.snapshot?.width ?? 0)")
                    .frame(width: terminal.width * scale, height: terminal.height * scale)
                    .padding(.leading, PaneCard.inset * scale)
                    .padding(.top, header * scale)
                }
            }
    }

    /// A card's own view at the card's size under its header, scaled to the tile. The tile takes its clicks, wheel
    /// and keyboard.
    private func scaled(_ view: some View, _ content: CGSize, under header: CGFloat) -> some View {
        view.frame(width: content.width, height: content.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: content.width * scale, height: content.height * scale, alignment: .topLeading)
            // `WebHost` reads this as "in a tile" (`BrowserView.inTile`): no other card is disabled.
            .disabled(true)
            .allowsHitTesting(false)
            .padding(.top, header * scale)
    }
}

private extension View {
    /// A card's element in its tile, with a value for the tests; its children are not elements (the tile is a button).
    /// A group's value does not reach XCUITest; static text's does (as the pane card's).
    func miniCard(_ paneID: String, _ value: String) -> some View {
        accessibilityElement()
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("overview.card.\(paneID)")
            .accessibilityValue(value)
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
