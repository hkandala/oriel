import AppKit
import HerdrKit
import SwiftUI

/// A floated pane's window (D50), by its session and terminal: opening one that is open brings it to the front.
struct Floating: Codable, Hashable {
    let session: String
    let terminalID: String
}

extension Page {
    func floats(_ pane: HostStore.Pane) -> Bool {
        pane.terminalID.map { floating[$0] != nil } ?? false
    }

    /// Floats the pane in a window of its own, or brings its window to the front, with the keyboard (its window
    /// takes it as it shows). herdr keeps the pane in its tab. One window per terminal: one another main window
    /// floats comes to the front.
    func float(_ pane: HostStore.Pane) {
        guard let terminalID = pane.terminalID else { return }
        if floating[terminalID] != nil {
            terminals.focus(terminalID)
        } else if !WindowPages.windows.contains(where: { $0.floats(terminalID) }) {
            floating[terminalID] = false
            if zoomedPaneID == pane.id {
                zoomedPaneID = nil
            }
            // The main window's keyboard leaves it for another card of the tab.
            focusKeyboardCard()
        }
        WindowPages.openWindow?(id: "float", value: Floating(session: id, terminalID: terminalID))
    }

    /// "New Pane" while it asks what it runs (as the card's header says), a browser's "Browser" and its page, a
    /// plugin's kind and title, an agent's name and session title; nil for a terminal.
    func kindTitle(_ pane: HostStore.Pane) -> (name: String, detail: String?)? {
        if store.chooser(pane.id) != nil {
            return ("New Pane", nil)
        }
        if let label = pane.browser {
            return ("Browser", browserTitle(pane, label))
        }
        if let label = pane.plugin, let kind = label.kind {
            return (kind.name, label.title)
        }
        return pane.agentTitle.map { (pane.agentLabel ?? "", $0) }
    }
}

extension WindowPages {
    /// `oriel://float?session=‹herdr session›&pane=‹pane id›`, optionally `&machine=‹machine id›` (This Mac's
    /// otherwise), from pi-herd or any tool: floats the pane over the machine's front main window, also when the
    /// session is not open there; again for the same pane brings its window forward.
    static func float(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard url.host() == "float", let session = value("session"), let pane = value("pane") else { return }
        float(session: session, pane: pane, machine: value("machine") ?? Machine.thisMac.id)
    }

    /// Also a float request on a session a store follows (talking-to-herdr#float-requests), from pi-herd on any
    /// machine: over the window the user last typed or clicked in a card of that store (`over`).
    static func float(session: String, pane: String, machine: String, over: WindowPages? = nil) {
        // Any app or pane can ask: the name goes into a herdr argv.
        guard Session.isValidName(session) else {
            windows.first?.cannotFloat(pane, of: session, "not a session name.")
            return
        }
        guard let window = over ?? windows.first(where: { $0.machine.id == machine }) else {
            if windows.isEmpty {
                early = { float(session: session, pane: pane, machine: machine) }
            } else {
                windows.first?.cannotFloat(pane, of: session, "no window of machine \(machine).")
            }
            return
        }
        // One still waiting gives way.
        if let old = window.floatPending?.page, old.floating.isEmpty {
            window.dropFloatOnly(old)
        }
        window.floatPending = (window.pageToFloat(session), pane)
        window.showFloatPending()
    }

    /// The terminal shows in a floating window (D50).
    func floats(_ terminalID: String) -> Bool {
        withFloats.contains { $0.floating[terminalID] != nil }
    }

    /// The pages and the float-only ones.
    var withFloats: [Page] {
        list + floatOnly
    }

    /// The session's page, else a new float-only one, its store connecting.
    private func pageToFloat(_ session: String) -> Page {
        if let page = withFloats.first(where: { $0.id == session }) {
            return page
        }
        let store = HostStore.named(session, on: machine)
        store.windows.append(self)
        let page = Page(store: store, terminals: terminals)
        floatOnly.append(page)
        return page
    }

    /// A float-only page with no float left leaves.
    func dropFloatOnly(_ page: Page) {
        guard let index = floatOnly.firstIndex(where: { $0 === page }) else { return }
        floatOnly.remove(at: index)
        leave(page.store)
        showTerminals()
    }

    /// The URL's pane floats once its session answered; a session or pane that is not there says so.
    func showFloatPending() {
        guard let (page, paneID) = floatPending, page.store.state != .connecting else { return }
        floatPending = nil
        if let pane = page.store.panes.first(where: { $0.id == paneID && $0.terminalID != nil }) {
            page.float(pane)
            // It streams now, not at the next snapshot: its page may not be in view.
            showTerminals()
        } else {
            let why = if case let .failed(error) = page.store.state {
                error.localizedDescription
            } else {
                "no such pane."
            }
            cannotFloat(paneID, of: page.id, why)
        }
        // A float that failed, or went to another main window's floating window.
        if page.floating.isEmpty {
            dropFloatOnly(page)
        }
    }

    private func cannotFloat(_ pane: String, of session: String, _ why: String) {
        let notice = Notice(text: "Can't float pane \(pane) of \(session): \(why)", tone: .warning)
        Task { await current?.store.show(notice) }
    }
}

/// The floating window: traffic lights, "session › workspace › tab", Stay on Top, Close and Detach, then the
/// pane's terminal in a card. It closes when its page lets the pane go (Detach, herdr closed the pane, the main
/// window closed).
struct FloatingWindow: View {
    let floating: Floating
    @State private var palette = false
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dismissWindow) private var dismissWindow

    private var look: Look {
        Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
    }

    var body: some View {
        let pages = WindowPages.windows.first { $0.floats(floating.terminalID) }
        let page = pages?.withFloats.first { $0.id == floating.session && $0.floating[floating.terminalID] != nil }
        let pane = page?.store.panes.first { $0.terminalID == floating.terminalID }
        Group {
            if let pages, let page {
                content(pages, page, pane)
            }
        }
        .frame(minHeight: 200)
        .windowChrome(look)
        .environment(\.look, look)
        .navigationTitle(pane.map { pane in
            page?.kindTitle(pane).map { [$0, $1].plainTitle } ?? pane.cardTitle
        } ?? "terminal")
        .background(FloatReader(terminalID: floating.terminalID, main: pages?.window,
                                pinned: page?.floating[floating.terminalID] == true,
                                closed: { page?.floating[floating.terminalID] = nil }))
        // Also gone before it first drew (a Detach right after the Float).
        .onChange(of: page == nil, initial: true) { _, gone in
            if gone {
                dismissWindow(id: "float", value: floating)
            }
        }
    }

    private func content(_ pages: WindowPages, _ page: Page, _ pane: HostStore.Pane?) -> some View {
        let terminal = pane.flatMap(page.terminal), chooser = pane.flatMap { page.store.chooser($0.id) }
        let browser = pane.flatMap(page.browser), plugin = pane.flatMap(page.plugin)
        let chat = chooser == nil ? pane.flatMap(page.chat) : nil
        let commands = CommandList(pages: pages, palette: $palette, settings: settings,
                                   floating: floating)
        return VStack(spacing: 0) {
            header(page, pane, chat: chat)
            // Not a Group, whose modifiers go on each child: the chooser's overlay would be made again as they change.
            ZStack {
                if let browser {
                    FloatingBrowser(browser: browser, page: page)
                } else if let plugin {
                    FloatingPlugin(plugin: plugin, page: page)
                } else if let chat, chat.showsChat {
                    ChatView(chat: chat, page: page, terminal: terminal)
                } else if let terminal {
                    terminalCard(terminal, page, pane, faded: chooser != nil, commands)
                } else {
                    Color.clear
                }
            }
            // Not on the window: a frame's minimum width hides its content's, and the title row's buttons (a chat's
            // switch too) can need more.
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let pane {
                    NewPaneOverlay(chooser: chooser, page: page, cardID: pane.id)
                        .contextMenu { CommandItems(commands: commands.all, sections: [.palette, .close]) }
                }
            }
            .overlay(alignment: .topTrailing) {
                if let find = page.find, find.paneID == pane?.id {
                    FindBar(find: find, page: page).padding(gap)
                }
            }
            .background(CardSurface(keyboard: terminal?.hasKeyboard == true || chat?.showsChat == true))
            .clipShape(CardSurface.shape)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("float.\(pane?.id ?? "")")
            .padding([.horizontal, .bottom], gap)
        }
        .overlay {
            if palette {
                Palette(pages: pages, page: page, commands: commands, open: $palette, height: 400)
                    .padding(.top, 40).floatingPanel(open: $palette, alignment: .top)
            }
        }
        .menuBar(commands)
        .modifier(CloseDialog(page: page, floated: pane?.id))
    }

    private func terminalCard(_ terminal: PaneTerminal, _ page: Page, _ pane: HostStore.Pane?, faded: Bool,
                              _ commands: CommandList) -> some View
    {
        TerminalCard(terminal: terminal, watched: page.watched, alpha: faded ? 0 : page.watched ? 0.85 : 1)
            // In this window by now: a claim made while it was still the main window's card would take that window's
            // keyboard.
            .onAppear { terminal.view.takeKeyboard() }
            .overlay {
                if let find = page.find, find.paneID == pane?.id {
                    FindHighlights(find: find, terminal: terminal)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, gap)
            .contextMenu { CommandItems(commands: commands.all, sections: [.palette, .close]) }
    }

    /// A plugin's pane (a browser) shows no place: its tab's title is another pane's program and folder.
    private func header(_ page: Page, _ pane: HostStore.Pane?, chat: Chat?) -> some View {
        let workspace = pane.flatMap { page.store.workspace(of: $0.tabID) }
        let tab = workspace?.tabs.first { $0.id == pane?.tabID }
        let rest = [workspace?.label, tab.map(page.titleText)]
            .compactMap(\.self).map { " › \($0)" }.joined()
        let pinned = page.floating[floating.terminalID] == true
        let id = "float.\(pane?.id ?? "")"
        return HStack(spacing: gap) {
            if let pane {
                PaneInfo(pane: pane, page: page, chat: chat).layoutPriority(1).accessibilityIdentifier("\(id).info")
            }
            if PaneLabel(pane?.label) == nil {
                if pane != nil {
                    Rectangle().fill(look.divider).frame(width: 1, height: 12)
                }
                // One line; the session's name gives way first, in its middle.
                HStack(spacing: 0) {
                    Text(page.store.title).truncationMode(.middle)
                    Text(rest).layoutPriority(1)
                }
                .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityValue(page.store.title + rest)
                .accessibilityIdentifier("\(id).place")
            }
            Spacer(minLength: 0)
            if let chat {
                ChatSwitch(chat: chat, page: page)
            }
            IconButton(symbol: pinned ? "pin.fill" : "pin", help: "Stay on Top", accent: pinned) {
                page.floating[floating.terminalID]?.toggle()
            }
            .accessibilityValue(pinned ? "on" : "off")
            .accessibilityIdentifier("\(id).pin")
            IconButton(symbol: "xmark", help: "Close Pane", key: .closeTab) {
                if let pane {
                    page.close(.pane(pane.id))
                }
            }
            .accessibilityIdentifier("\(id).close")
            IconButton(symbol: "pip.exit", help: "Detach Pane", key: .closePane) {
                page.floating[floating.terminalID] = nil
            }
            .accessibilityIdentifier("\(id).detach")
        }
        .foregroundStyle(look.chrome)
        // The main window's title row: its height, and its start after the traffic lights.
        .padding(.leading, TitleBar.inset(fullScreen: false)).padding(.trailing, gap)
        .frame(height: TitleBar.height)
        // The title bar is hidden, so the row's empty space moves the window.
        .background { Color.clear.contentShape(.rect).gesture(WindowDragGesture()) }
    }
}

/// The floating window's AppKit side: Stay on Top, and its close, which detaches the pane.
/// A floated pane's icon, title and agent state, in its window's title row.
private struct PaneInfo: View {
    let pane: HostStore.Pane
    let page: Page
    let chat: Chat?

    var body: some View {
        HStack(spacing: 6) {
            ProgramTile(icon: pane.iconID, letter: pane.letter)
            Group {
                if let (name, detail) = page.kindTitle(pane) {
                    Text("\(name)\(Text(detail.map { " \($0)" } ?? "").foregroundStyle(.secondary))").lineLimit(1)
                    if page.plugin(pane)?.dirty == true {
                        DirtyDot(paneID: pane.id)
                    }
                } else {
                    PaneTitle(pane: pane)
                }
            }
            .fontWeight(.medium)
            CardState(chat: chat, state: pane.state, paneID: pane.id)
        }
        .accessibilityElement(children: .combine)
    }
}
