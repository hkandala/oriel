#if os(macOS)
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

    /// The floating window: traffic lights, "session › workspace › tab", Stay on Top, Close and Detach, then the
    /// pane's terminal in a card. It closes when its page lets the pane go (Detach, herdr closed the pane, the main
    /// window closed).
    struct FloatingWindow: View {
        let floating: Floating
        @State private var palette = false
        private var settings = AppSettings()
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.openWindow) private var openWindow
        @Environment(\.dismissWindow) private var dismissWindow

        var body: some View {
            let look = Look(style: settings.style, dark: colorScheme == .dark)
            let pages = WindowPages.windows.first { $0.list.contains { $0.floating[floating.terminalID] != nil } }
            let page = pages?.list.first { $0.id == floating.session && $0.floating[floating.terminalID] != nil }
            let pane = page?.store.panes.first { $0.terminalID == floating.terminalID }
            Group {
                if let pages, let page {
                    content(pages, page, pane)
                }
            }
            .frame(minWidth: 320, minHeight: 200)
            .ignoresSafeArea(edges: .top)
            .containerBackground(for: .window) { WindowBackground(look: look) }
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .environment(\.look, look)
            .navigationTitle(pane?.cardTitle ?? "terminal")
            .background(FloatReader(terminalID: floating.terminalID,
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
            let commands = CommandList(pages: pages, palette: $palette, openWindow: openWindow, settings: settings,
                                       floating: floating)
            return VStack(spacing: 0) {
                header(page, pane)
                Group {
                    if let terminal {
                        TerminalCard(terminal: terminal, watched: page.watched, alpha: page.watched ? 0.85 : 1)
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
            .focusedSceneValue(\.commands, commands)
            .modifier(CloseDialog(page: page, floated: pane?.id))
        }

        private func header(_ page: Page, _ pane: HostStore.Pane?) -> some View {
            let workspace = pane.flatMap { page.store.workspace(of: $0.tabID) }
            let tab = workspace?.tabs.first { $0.id == pane?.tabID }
            let rest = [workspace?.label, tab.map(page.titleText)]
                .compactMap(\.self).map { " › \($0)" }.joined()
            let pinned = page.floating[floating.terminalID] == true
            let id = "float.\(pane?.id ?? "")"
            return HStack(spacing: 2) {
                // One line; the session's name gives way first, in its middle.
                HStack(spacing: 0) {
                    Text(page.id).truncationMode(.middle)
                    Text(rest).layoutPriority(1)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityValue(page.id + rest)
                .accessibilityIdentifier("\(id).place")
                Spacer(minLength: 8)
                IconButton(symbol: pinned ? "pin.fill" : "pin", help: "Stay on Top", size: 22, accent: pinned) {
                    page.floating[floating.terminalID]?.toggle()
                }
                .accessibilityValue(pinned ? "on" : "off")
                .accessibilityIdentifier("\(id).pin")
                IconButton(symbol: "xmark", help: "Close Pane", key: .closePane, size: 22) {
                    if let pane {
                        page.close(.pane(pane.id))
                    }
                }
                .accessibilityIdentifier("\(id).close")
                IconButton(symbol: "pip.exit", help: "Detach Pane", key: .closeWindow, size: 22) {
                    page.floating[floating.terminalID] = nil
                }
                .accessibilityIdentifier("\(id).detach")
            }
            .foregroundStyle(page.store.writing ? .secondary : .primary)
            // Right of the traffic lights, in the title bar's 28 pt.
            .padding(.leading, 78).padding(.trailing, gap)
            .frame(height: 28)
        }
    }

    /// The floating window's AppKit side: Stay on Top, and its close, which detaches the pane.
    private struct FloatReader: NSViewRepresentable {
        let terminalID: String
        let pinned: Bool
        let closed: () -> Void

        func makeNSView(context _: Context) -> Reader {
            let reader = Reader()
            reader.terminalID = terminalID
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

        final class Reader: NSView {
            var closed: () -> Void = {}
            var terminalID = ""
            private var observer: NSObjectProtocol?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window, observer == nil else { return }
                // AppKit keeps the frame for the next time the pane floats. ponytail: one defaults key per terminal
                // ever floated; prune them if that ever matters.
                window.setFrameAutosaveName("float \(terminalID)")
                let close = NSWindow.willCloseNotification, center = NotificationCenter.default
                observer = center.addObserver(forName: close, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.closed()
                        self?.observer.map(center.removeObserver)
                    }
                }
            }
        }
    }

    /// A floated pane's card in its tab: its icon, its name and Show, which brings its window to the front.
    struct FloatedPlaceholder: View {
        let page: Page
        let pane: HostStore.Pane

        var body: some View {
            VStack(spacing: 10) {
                ProgramTile(icon: pane.iconID, letter: pane.letter).scaleEffect(1.5)
                Text(pane.cardTitle).foregroundStyle(.secondary).lineLimit(1)
                Button("Show") { page.float(pane) }
                    .accessibilityIdentifier("pane.\(pane.id).show")
            }
            .padding(gap)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    extension CommandList {
        /// The floating window's commands (D50): only what applies to it.
        func floatingCommands(_ floating: Floating) -> [Command] {
            let terminalID = floating.terminalID
            guard let page = pages?.list.first(where: { $0.id == floating.session }) else { return [] }
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
                Command(section: .close, title: "Detach Pane", key: .closeWindow, symbol: "pip.exit") {
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
            ] + Self.pane(page) { pane }.filter { $0.title == "Close Pane" } + sizes
        }
    }
#endif
