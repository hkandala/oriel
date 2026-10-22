#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// A translucent card: a header with the pane's title and buttons, and its terminal. Cards without the keyboard
    /// fade (D64).
    struct PaneCard: View {
        let id: String
        let page: Page
        @State private var hovering = false
        @State private var draft = ""
        @FocusState private var renaming: Bool
        @Environment(\.zoomedAway) private var zoomedAway
        @Environment(\.appearsActive) private var active
        @Environment(\.colorScheme) private var scheme
        @AppStorage("fadeInactivePanes") private var fade = true
        @AppStorage("focusFollowsMouse") private var followMouse = false

        var body: some View {
            let store = page.store
            let pane = store.pane(id)
            let zoomed = page.zoomedPaneID == id
            let terminal = pane.flatMap(page.terminal)
            // The tab's keyboard card is lit, also while a text field has the keyboard; herdr's focus until one had it.
            let keyboard = pane.flatMap { page.keyboardTerminals[$0.tabID] }
            let lit = keyboard.map { $0 == pane?.terminalID } ?? pane?.focused ?? false
            // Rex's content opacities; the watching window's dim (D66) multiplies.
            let content = (fade ? lit ? active ? 1 : scheme == .dark ? 0.8 : 0.85 : active ? 0.7 : 0.5 : 1)
                * (page.watched ? 0.85 : 1)
            VStack(spacing: 0) {
                header(pane, zoomed: zoomed, showsButtons: lit || hovering || zoomed)
                Group {
                    if let terminal {
                        TerminalCard(terminal: terminal, watched: page.watched, alpha: content)
                            .padding([.horizontal, .bottom], gap)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // As the card shows: what runs in it now, for its icon (the snapshot's ask was when the pane was new). Not
            // the view's task: a lazy page that leaves at once would cancel it.
            .onAppear { Task { await store.askProgram(id) } }
            .clipShape(CardSurface.shape)
            // The card's element is its background: a container would merge into a one-pane page's.
            .background {
                CardSurface(keyboard: lit).accessibilityElement().accessibilityLabel(pane?.cardTitle ?? "terminal")
                    // A plain element has no value in XCUITest (phase 10); the static text trait gives it one.
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityValue("content \(Int((content * 100).rounded()))%")
                    .accessibilityIdentifier("pane.\(id)")
                    // The buttons show on hover only and the context menu is on the header: VoiceOver acts on the card.
                    .accessibilityActions {
                        let commands = AppCommands.pane(page) { pane }.filter { $0.enabled && $0.menu.isEmpty }
                        ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                            Button(command.title, action: command.action)
                        }
                    }
            }
            .onHover { hovering = $0 }
            .task(id: hovering && followMouse && !zoomedAway && active) {
                // Focus follows mouse: a pointer resting 0.15 s on another card, in a key window, no mouse button
                // down, no text field typing, not under a zoomed card. Checked every 0.15 s while it rests, so a
                // rename or a drag that ends under it still counts; once (keys may move the keyboard away again).
                guard hovering, followMouse, !zoomedAway, active, !lit else { return }
                while await (try? Task.sleep(for: .milliseconds(150))) != nil {
                    guard let pane = store.pane(id),
                          page.keyboardTerminals[pane.tabID] != pane.terminalID else { return }
                    if NSEvent.pressedMouseButtons == 0, !(NSApp.keyWindow?.firstResponder is NSText) {
                        page.go(to: pane)
                        return
                    }
                }
            }
            .accessibilityHidden(zoomedAway)
        }

        /// 36 pt: the glyph and title (or the rename field), then the buttons; the context menu has the pane's actions.
        private func header(_ pane: HostStore.Pane?, zoomed: Bool, showsButtons: Bool) -> some View {
            // The label wins; else the program in primary text and the folder in secondary, as in Rex ("zsh ~").
            let (name, folder) = pane?.header ?? (nil, "terminal")
            return HStack(spacing: 8) {
                // Clicks pass through to the header's double-click.
                ProgramGlyph(icon: pane?.iconID ?? "terminal", letter: pane?.letter).allowsHitTesting(false)
                if page.renamingPaneID == id {
                    TextField("Pane Name", text: $draft).textFieldStyle(.plain).focused($renaming)
                        .onSubmit { rename(pane) }
                        .onExitCommand { stopRenaming(pane) }
                        // A click elsewhere keeps the keyboard and the selection where it went.
                        .onChange(of: renaming) { _, now in
                            if !now {
                                page.renamingPaneID = nil
                            }
                        }
                        .onAppear { draft = pane?.label ?? "" }
                        .focusSoon($renaming)
                        .accessibilityIdentifier("pane.\(id).rename")
                } else {
                    let lead = name.map { "\($0) " } ?? ""
                    Text("\(lead)\(Text(folder).foregroundStyle(name == nil ? .primary : .secondary))")
                        .lineLimit(1)
                        // A path keeps its end, a label its start.
                        .truncationMode(pane?.label != nil ? .tail : name == nil ? .head : .middle)
                        .allowsHitTesting(false)
                }
                Spacer(minLength: 0)
                // Hidden, they take no width from a narrow card. A zoomed card has only Restore and Close.
                if showsButtons {
                    buttons(zoomed: zoomed)
                }
            }
            .fontWeight(.medium)
            .padding(.leading, 6)
            .padding(.trailing, 8)
            // A card narrower than its header cuts the header (the card clips) instead of growing.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
            // Behind the header, so its buttons still take their own clicks.
            .background { Color.clear.contentShape(.rect).onTapGesture(count: 2) { page.zoom(id) } }
            .contextMenu {
                CommandItems(commands: AppCommands.pane(page) { pane }, sections: [.pane, .paneMove, .close])
            }
        }

        /// Split Right, Split Down, Zoom and Close, 22 pt and 2 pt apart; only Restore and Close on a zoomed card.
        private func buttons(zoomed: Bool) -> some View {
            let store = page.store
            return HStack(spacing: 2) {
                if !zoomed {
                    IconButton(symbol: "rectangle.split.2x1", help: "Split Right", size: 22) {
                        Task { await page.split(id, .right) }
                    }
                    .accessibilityIdentifier("pane.\(id).split-right")
                    IconButton(symbol: "rectangle.split.1x2", help: "Split Down", size: 22) {
                        Task { await page.split(id, .down) }
                    }
                    .accessibilityIdentifier("pane.\(id).split-down")
                }
                IconButton(symbol: zoomed ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right", help: zoomed ? "Restore" : "Zoom", size: 22,
                    accent: zoomed) { page.zoom(id) }
                    .accessibilityIdentifier("pane.\(id).zoom")
                    .disabled(!page.canZoom(id))
                IconButton(symbol: "xmark", help: "Close", size: 22) { Task { await store.close(pane: id) } }
                    .accessibilityIdentifier("pane.\(id).close")
            }
            .disabled(store.writing)
        }

        /// Enter: herdr's label (an empty one clears it), unless unchanged; the snapshot after it shows it.
        private func rename(_ pane: HostStore.Pane?) {
            let label = draft.trimmingCharacters(in: .whitespaces)
            if label != pane?.label ?? "" {
                Task { await page.store.rename(pane: id, label: label) }
            }
            stopRenaming(pane)
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
#endif
