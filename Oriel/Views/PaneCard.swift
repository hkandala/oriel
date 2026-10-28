import HerdrKit
import SwiftUI

/// A translucent card: a header with the pane's title and buttons, and its terminal.
struct PaneCard: View {
    /// The header's height, and the terminal's inset from the card's sides (the overview's miniatures too).
    static let header: CGFloat = 36
    static let inset: CGFloat = 10
    let id: String
    let page: Page
    /// Under a zoomed card: hidden, but there, so its terminal keeps its size.
    let away: Bool
    @State private var hovering = false
    /// A dragged pane over this card: an edge, or the center (`.some(nil)`).
    @State private var zone: Heading??
    @State private var size = CGSize.zero
    @Environment(\.appearsActive) private var active
    @Environment(\.look) private var look
    private var settings = AppSettings()

    var body: some View {
        let store = page.store
        let pane = store.pane(id)
        let zoomed = page.zoomedPaneID == id
        let terminal = pane.flatMap(page.terminal)
        // The tab's keyboard card is lit, also while a text field has the keyboard; herdr's focus until one had it.
        // A split's new card at once, its stand-in too, among the shown tab's cards.
        let shown = page.selectedTab?.tree?.paneIDs ?? []
        let newest = page.newest.flatMap { newest in
            shown.contains(id) && shown.contains { $0 == newest.id || store.ahead.splitPanes[$0] == newest.id }
                ? newest.id : nil
        }
        let lit = newest.map { $0 == id || store.ahead.splitPanes[id] == $0 }
            ?? pane.map { page.keyboardCard($0.tabID) === $0 } ?? false
        let floated = pane.map(page.floats) ?? false
        let follow = hovering && settings.followMouse && !away && active && !floated
        // The watching window's dim (D66), on the header and the terminal.
        let content = page.watched ? 0.85 : 1
        // A new pane's chooser hides its terminal (ui/new-pane).
        let chooser = store.chooser(id), browser = pane.flatMap(page.browser)
        VStack(spacing: 0) {
            header(
                pane ?? store.parked[id],
                zoomed: zoomed,
                showsButtons: lit || hovering || zoomed,
                new: chooser != nil,
            )
            .opacity(content)
            Group {
                if let pane, floated {
                    FloatedPlaceholder(page: page, pane: pane)
                } else if let browser {
                    BrowserCard(browser: browser)
                } else if let terminal {
                    // Rex's text starts 12 pt in from the card's edge.
                    TerminalCard(terminal: terminal, watched: page.watched, alpha: chooser == nil ? content : 0)
                        .overlay {
                            if let find = page.find, find.paneID == id {
                                FindHighlights(find: find, terminal: terminal)
                            }
                        }
                        .padding(.horizontal, Self.inset).padding(.bottom, gap)
                        // The terminal sends a right click here (without ⌥, see `PaneSurfaceView`), as herdr opens
                        // its pane menu. Copy and the rest act on this terminal, not on the keyboard card.
                        .contextMenu {
                            edit("Copy", #selector(NSText.copy(_:)), terminal)
                            edit("Paste", #selector(NSText.paste(_:)), terminal)
                            edit("Select All", #selector(NSText.selectAll(_:)), terminal)
                            Divider()
                            PaneItems(page: page, pane: pane)
                        }
                } else {
                    // A stand-in's card, before herdr made its pane: an empty `Group` drops its overlays, and the
                    // chooser showed only once the terminal came.
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The card's menu also over the chooser, which takes the terminal's clicks.
            .overlay {
                NewPaneOverlay(chooser: floated ? nil : chooser, page: page, cardID: id)
                    .contextMenu { PaneItems(page: page, pane: pane) }
            }
            .overlay(alignment: .topTrailing) {
                if !floated, let find = page.find, find.paneID == id {
                    FindBar(find: find, page: page).padding(gap)
                }
            }
        }
        // The whole card, also with no terminal (a split's stand-in): an empty `Group` takes no room, and the card
        // was a header-high band.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // As the card shows: what runs in it now, for its icon (the snapshot's ask was when the pane was new). Not
        // the view's task: a lazy page that leaves at once would cancel it.
        .onAppear { Task { await store.askProgram(id, soon: true) } }
        .clipShape(CardSurface.shape)
        // The card's element is its background: a container would merge into a one-pane page's.
        .background {
            CardSurface(keyboard: lit).accessibilityElement().accessibilityLabel(pane?.cardTitle ?? "terminal")
                // A plain element has no value in XCUITest; the static text trait gives it one.
                .accessibilityAddTraits(.isStaticText)
                // "loading" until herdr's frames settled at the card's size.
                .accessibilityValue(terminal.map { !$0.ready && !$0.state.isFailed } == true ? "loading" : "")
                .accessibilityIdentifier("pane.\(id)")
                // The buttons show on hover only and the context menu is on the header: VoiceOver acts on the card,
                // and VO-Shift-M opens its menu, which has every tab (made only when it opens).
                .accessibilityActions { PaneActions(page: page, pane: pane) }
                .contextMenu { PaneItems(page: page, pane: pane) }
        }
        .opacity(page.dragging == .pane(id) ? 0.4 : 1)
        .overlay(alignment: .topLeading) {
            if let zone, page.dragging != nil {
                let half = CGSize(width: size.width / 2, height: size.height / 2)
                DropIndicator()
                    .frame(width: zone == .left || zone == .right ? half.width : size.width,
                           height: zone == .up || zone == .down ? half.height : size.height)
                    .offset(x: zone == .right ? half.width : 0, y: zone == .down ? half.height : 0)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onDrop(of: [.orielDrag], delegate: CardDrop(paneID: id, page: page, size: size, zone: $zone))
        .clearsDrop(page) { zone = nil }
        .onHover { hovering = $0 }
        .task(id: follow) {
            // Focus follows mouse: a pointer resting 0.15 s on another card, in a key window, no mouse button
            // down, no text field typing, not under a zoomed card. Checked every 0.15 s while it rests, so a
            // rename or a drag that ends under it still counts; once (keys may move the keyboard away again).
            guard follow, !lit else { return }
            while await (try? Task.sleep(for: .milliseconds(150))) != nil {
                // Not after the page went to another tab (a palette pick): hover lasts until the mouse moves.
                guard let pane = store.pane(id), pane.tabID == page.selectedTab?.id,
                      page.keyboardCard(pane.tabID) !== pane else { return }
                // No button down, no open menu (hover stays on while one tracks), no text field typing.
                if NSEvent.pressedMouseButtons == 0, RunLoop.main.currentMode != .eventTracking,
                   !(NSApp.keyWindow?.firstResponder is NSText)
                {
                    page.go(to: pane)
                    return
                }
            }
        }
        .accessibilityHidden(away)
    }

    /// `new`: the chooser shows (ui/new-pane), and the title says so.
    private func header(_ pane: HostStore.Pane?, zoomed: Bool, showsButtons: Bool, new: Bool) -> some View {
        // A browser card's header is its toolbar (future-work/web-page#the-card), unless it is renamed.
        let browser = pane.flatMap { page.renamingPaneID != id && !page.floats($0) ? page.browser($0) : nil }
        return HStack(spacing: 3) {
            if let browser {
                BrowserToolbar(browser: browser, page: page)
            } else {
                // Clicks pass through to the header's double-click.
                ProgramGlyph(icon: pane?.iconID ?? "terminal", letter: pane?.letter).allowsHitTesting(false)
                if page.renamingPaneID == id {
                    // Enter: herdr's label (an empty one clears it); the snapshot after it shows it. A click elsewhere
                    // keeps the keyboard and the selection where it went.
                    RenameField(prompt: "Pane Name", initial: pane?.label ?? "", commit: { label in
                        Task { await page.store.rename(pane: id, label: label) }
                    }, end: { stopRenaming(pane) }, blur: { page.renamingPaneID = nil })
                        .accessibilityIdentifier("pane.\(id).rename")
                } else {
                    Group {
                        if new {
                            Text("New Pane").lineLimit(1)
                        } else {
                            PaneTitle(pane: pane)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("pane.\(id).title")
                }
            }
            Spacer(minLength: 0)
            // Hidden, they take no width from a narrow card. A zoomed card has only Restore and Close.
            // Not on a split's or a new tab's empty card before herdr has its pane (`Ahead`).
            if showsButtons, pane != nil {
                buttons(zoomed: zoomed)
            }
        }
        .fontWeight(.medium)
        // Rex's glyph sits 13.5 pt in and its title 30.5 pt.
        .padding(.leading, 11)
        .padding(.trailing, 8)
        // A card narrower than its header cuts the header (the card clips) instead of growing.
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.header,
            maxHeight: Self.header,
            alignment: .leading,
        )
        // Behind the header, so its buttons still take their own clicks.
        .background {
            Color.clear.contentShape(.rect).onTapGesture(count: 2) { page.zoom(id) }
                // The drag image is the whole card: the header starts at its top left.
                .dragSource(.pane(id), page: page, previewSize: size)
        }
        .contextMenu { PaneItems(page: page, pane: pane) }
    }

    private func edit(_ title: String, _ action: Selector, _ terminal: PaneTerminal) -> some View {
        Button(title) { NSApp.sendAction(action, to: terminal.view, from: nil) }
    }

    private func buttons(zoomed: Bool) -> some View {
        let store = page.store
        return HStack(spacing: 2) {
            if !zoomed {
                // Lit on a floated pane's card, where it brings the window to the front.
                IconButton(symbol: "pip.enter", help: "Float Pane", size: 22,
                           accent: store.pane(id).map(page.floats) == true, action: {
                               if let pane = store.pane(id) {
                                   page.float(pane)
                               }
                           })
                           .accessibilityIdentifier("pane.\(id).float")
                IconButton(symbol: "rectangle.split.2x1", help: "Split Right", key: .splitRight, size: 22) {
                    Task { await page.split(id, .right) }
                }
                .accessibilityIdentifier("pane.\(id).split-right")
                IconButton(symbol: "rectangle.split.1x2", help: "Split Down", key: .splitDown, size: 22) {
                    Task { await page.split(id, .down) }
                }
                .accessibilityIdentifier("pane.\(id).split-down")
            }
            IconButton(symbol: zoomed ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right", help: zoomed ? "Restore Pane" : "Zoom Pane", key: .zoom,
                size: 22,
                accent: zoomed) { page.zoom(id) }
                .accessibilityIdentifier("pane.\(id).zoom")
                .disabled(!page.canZoom(id))
            IconButton(symbol: "xmark", help: "Close Pane", key: .closePane, size: 22) {
                page.close(.pane(id))
            }
            .accessibilityIdentifier("pane.\(id).close")
        }
        .foregroundStyle(look.paneButton)
    }

    /// The keyboard goes back to the card.
    private func stopRenaming(_ pane: HostStore.Pane?) {
        guard page.renamingPaneID == id else { return }
        page.renamingPaneID = nil
        if let pane {
            page.go(to: pane)
        }
    }
}

/// The label; else the program in primary text and the folder in secondary, as in Rex ("zsh ~"). A label keeps
/// its start, a path its end. The card's header and the floating window's title row.
struct PaneTitle: View {
    let pane: HostStore.Pane?

    var body: some View {
        let (name, folder) = pane?.header ?? (nil, "terminal")
        let lead = name.map { "\($0) " } ?? ""
        Text("\(lead)\(Text(folder).foregroundStyle(name == nil ? .primary : .secondary))")
            .lineLimit(1)
            .truncationMode(pane?.label != nil ? .tail : name == nil ? .head : .middle)
    }
}

/// A floated pane's card in its tab, under its header: a line that says where the pane is, Show Window, which
/// brings its window to the front, and Bring Back Here, which detaches it into this card with the keyboard.
private struct FloatedPlaceholder: View {
    let page: Page
    let pane: HostStore.Pane

    var body: some View {
        VStack(spacing: 12) {
            Text("This pane is open in a floating window.").foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("pane.\(pane.id).floating")
            HStack(spacing: gap) {
                Button("Show Window") { page.float(pane) }
                    .accessibilityIdentifier("pane.\(pane.id).show")
                Button("Bring Back Here") {
                    if let terminalID = pane.terminalID {
                        page.floating[terminalID] = nil
                    }
                    page.go(to: pane)
                }
                .accessibilityIdentifier("pane.\(pane.id).back")
            }
            .buttonStyle(.glass)
        }
        .padding(gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The pane's menu items, with Move Pane to Tab's every tab of the session: their own view, so they are made when
/// the menu opens, not in each card's body (300 tab titles per card, at every change of one).
private struct PaneItems: View {
    let page: Page
    let pane: HostStore.Pane?

    var body: some View {
        CommandItems(commands: CommandList.pane(page) { pane }, sections: [.pane, .paneMove, .close])
    }
}

/// VoiceOver's actions on the card, Move Pane to Tab ▸ flattened to New Tab and New Workspace: any accessibility
/// client makes SwiftUI build them with the card, and one per tab made a switch to a big session 3 times
/// slower. Their own view, as the menu items are.
private struct PaneActions: View {
    let page: Page
    let pane: HostStore.Pane?

    var body: some View {
        let commands = CommandList.pane(page, tabs: false) { pane }.filter(\.enabled).flatMap { command in
            command.menu.isEmpty ? [(command.title, command.action)]
                : command.menu.map { ("\(command.title) \($0.title)", $0.action) }
        }
        ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
            Button(command.0, action: command.1)
        }
    }
}
