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
            terminal(pane)?.view.takeKeyboard()
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
        .frame(minWidth: 320, minHeight: 200)
        .windowChrome(look)
        .environment(\.look, look)
        .navigationTitle(pane?.cardTitle ?? "terminal")
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
        let terminal = pane.flatMap(page.terminal)
        let commands = CommandList(pages: pages, palette: $palette, settings: settings,
                                   floating: floating)
        return VStack(spacing: 0) {
            header(page, pane)
            Group {
                if let terminal {
                    TerminalCard(terminal: terminal, watched: page.watched,
                                 alpha: page.store.chooser(pane?.id ?? "") != nil ? 0 : page.watched ? 0.85 : 1)
                        // In this window by now: a claim made while it was still the main window's card would
                        // take that window's keyboard.
                        .onAppear { terminal.view.takeKeyboard() }
                        .overlay {
                            if let find = page.find, find.paneID == pane?.id {
                                FindHighlights(find: find, terminal: terminal)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, gap)
                        .contextMenu { CommandItems(commands: commands.all, sections: [.palette, .close]) }
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let pane {
                    NewPaneOverlay(chooser: page.store.chooser(pane.id), page: page, cardID: pane.id)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let find = page.find, find.paneID == pane?.id {
                    FindBar(find: find, page: page).padding(gap)
                }
            }
            .background(CardSurface(keyboard: terminal?.hasKeyboard == true))
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

    private func header(_ page: Page, _ pane: HostStore.Pane?) -> some View {
        let workspace = pane.flatMap { page.store.workspace(of: $0.tabID) }
        let tab = workspace?.tabs.first { $0.id == pane?.tabID }
        let rest = [workspace?.label, tab.map(page.titleText)]
            .compactMap(\.self).map { " › \($0)" }.joined()
        let pinned = page.floating[floating.terminalID] == true
        let id = "float.\(pane?.id ?? "")"
        return HStack(spacing: gap) {
            if let pane {
                PaneInfo(pane: pane).layoutPriority(1).accessibilityIdentifier("\(id).info")
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
            Spacer(minLength: 0)
            // The title row's buttons.
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
private struct FloatReader: NSViewRepresentable {
    let terminalID: String
    /// The main window that floated the pane, for a new window's frame.
    weak var main: NSWindow?
    let pinned: Bool
    let closed: () -> Void

    func makeNSView(context _: Context) -> Reader {
        let reader = Reader()
        reader.terminalID = terminalID
        reader.main = main
        return reader
    }

    func updateNSView(_ reader: Reader, context _: Context) {
        reader.closed = closed
        // Above every app's windows and on every Space, like picture in picture.
        reader.window?.level = pinned ? .floating : .normal
        let onTop: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if pinned {
            reader.window?.collectionBehavior.formUnion(onTop)
        } else {
            reader.window?.collectionBehavior.subtract(onTop)
        }
    }

    final class Reader: TrafficLights {
        var closed: () -> Void = {}
        var terminalID = ""
        weak var main: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // AppKit keeps the frame for the next time the pane floats. ponytail: one defaults key per terminal
            // ever floated; prune them if that ever matters.
            let name = "float \(terminalID)"
            if !window.setFrameUsingName(name), let main {
                window.setFrame(Self.frame(over: main), display: false)
            }
            window.setFrameAutosaveName(name)
            let center = NotificationCenter.default, close = NSWindow.willCloseNotification
            observers.append(center.addObserver(forName: close, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closed()
                    self?.stop()
                }
            })
        }

        /// A new floating window: 60 % of its main window's width and 75 % of its height, at least 720 × 460 pt,
        /// centered over it. AppKit keeps it on the screen.
        static func frame(over main: NSWindow) -> NSRect {
            let width = max(720, main.frame.width * 0.6), height = max(460, main.frame.height * 0.75)
            let frame = NSRect(x: main.frame.midX - width / 2, y: main.frame.midY - height / 2, width: width,
                               height: height)
            return main.constrainFrameRect(frame, to: main.screen)
        }
    }
}

/// A floated pane's quick info in its window's title row: its icon, its program and folder (or its label), and
/// its agent's state.
private struct PaneInfo: View {
    let pane: HostStore.Pane

    var body: some View {
        HStack(spacing: 6) {
            ProgramTile(icon: pane.iconID, letter: pane.letter)
            PaneTitle(pane: pane).fontWeight(.medium)
            if let state = pane.state {
                StateCapsule(state: state)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension CommandList {
    /// The floating window's commands (D50): only what applies to it.
    func floatingCommands(_ floating: Floating) -> [Command] {
        let terminalID = floating.terminalID
        guard let page = pages?.withFloats.first(where: { $0.id == floating.session }) else { return [] }
        let pane = page.store.panes.first { $0.terminalID == terminalID }
        let terminal = pane.flatMap(page.terminal)
        var main = self
        main.floating = nil
        let sizes = main.all.filter { $0.section == .size || $0.title == "Font Size" }
        func edit(_ title: String, _ action: Selector, _ symbol: String) -> Command {
            Command(section: .palette, title: title, symbol: symbol, enabled: terminal != nil) {
                if let terminal {
                    NSApp.sendAction(action, to: terminal.view, from: nil)
                }
            }
        }
        return [
            Command(section: .close, title: "Detach Pane", key: .closePane, symbol: "pip.exit") {
                page.floating[terminalID] = nil
            },
            Command(section: .view, title: "Command Palette", key: .palette, symbol: "command",
                    enabled: palette != nil) { palette?.wrappedValue.toggle() },
            Command(section: .view, title: "Stay on Top", symbol: "pin", checked: page.floating[terminalID] == true,
                    setting: true) { page.floating[terminalID]?.toggle() },
            Command(section: .edit, title: "Find…", key: .init("f"), symbol: "magnifyingglass",
                    enabled: pane != nil) { page.openFind(pane) },
            Command(section: .edit, title: "Find Next", key: .findNext, symbol: "chevron.down",
                    enabled: page.find != nil) { Task { await page.find?.step(1) } },
            Command(section: .edit, title: "Find Previous", symbol: "chevron.up", enabled: page.find != nil) {
                Task { await page.find?.step(-1) }
            },
            edit("Copy", #selector(NSText.copy(_:)), "doc.on.doc"),
            edit("Paste", #selector(NSText.paste(_:)), "doc.on.clipboard"),
        ] + Self.pane(page, tabs: false) { pane }.filter { $0.section == .close }.map {
            // ⌘W detaches, as the red light.
            var command = $0
            command.key = command.key == .closePane ? .closeTab : command.key
            return command
        } + sizes
    }
}
