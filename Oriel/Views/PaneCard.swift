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
            // The card that has the keyboard is lit; herdr's focus until a terminal exists.
            let lit = terminal?.hasKeyboard ?? pane?.focused ?? true
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
                    .accessibilityValue("content \(Int((content * 100).rounded()))%")
                    .accessibilityIdentifier("pane.\(id)")
                    // The buttons show on hover only; VoiceOver splits from the card.
                    .accessibilityAction(named: "Split Right") { Task { await page.split(id, .right) } }
                    .accessibilityAction(named: "Split Down") { Task { await page.split(id, .down) } }
                    .accessibilityAction(named: zoomed ? "Restore" : "Zoom") { page.zoom(id) }
                    .accessibilityAction(named: "Close") { Task { await store.close(pane: id) } }
            }
            .onHover { hovering = $0 }
            .task(id: hovering && followMouse && !lit) {
                // Focus follows mouse: a pointer resting 0.15 s, no button down, no text field typing, a key window.
                guard hovering, followMouse, !lit, active, let pane,
                      await (try? Task.sleep(for: .milliseconds(150))) != nil, NSEvent.pressedMouseButtons == 0,
                      !(NSApp.keyWindow?.firstResponder is NSText) else { return }
                page.go(to: pane)
            }
            .accessibilityHidden(zoomedAway)
        }

        /// 36 pt: the glyph and title (or the rename field), then the buttons; the context menu has the pane's actions.
        private func header(_ pane: HostStore.Pane?, zoomed: Bool, showsButtons: Bool) -> some View {
            let store = page.store
            // The label wins; else the program in primary text and the folder in secondary, as in Rex ("zsh ~").
            let name = pane?.label == nil ? pane?.programName : nil
            let folder = pane?.label ?? pane?.folder ?? (name == nil ? "terminal" : "")
            let alone = store.panes.count { $0.tabID == pane?.tabID } < 2
            return HStack(spacing: 8) {
                // Clicks pass through to the header's double-click.
                ProgramGlyph(icon: pane?.iconID ?? "terminal", letter: pane?.letter).allowsHitTesting(false)
                if page.renamingPaneID == id {
                    TextField("Pane Name", text: $draft).textFieldStyle(.plain).focused($renaming)
                        .onSubmit { rename(pane) }
                        .onExitCommand { stopRenaming(pane) }
                        .onChange(of: renaming) { _, now in
                            if !now {
                                stopRenaming(pane)
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
                    buttons(zoomed: zoomed, alone: alone)
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
                let commands = AppCommands.pane(page, pane)
                CommandItems(commands: commands.filter { $0.section == .pane })
                Divider()
                CommandItems(commands: commands.filter { $0.section == .paneMove })
                Divider()
                CommandItems(commands: commands.filter { $0.section == .close })
            }
        }

        /// Split Right, Split Down, Zoom and Close, 22 pt and 2 pt apart; only Restore and Close on a zoomed card.
        private func buttons(zoomed: Bool, alone: Bool) -> some View {
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
                    .disabled(alone && !zoomed)
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
