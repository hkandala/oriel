#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// Where a hover panel sits: its `panel` point on the trigger's `trigger` point, moved by `offset`.
    struct PanelPlace {
        let trigger: UnitPoint
        let panel: UnitPoint
        let offset: CGSize

        /// Under the Agents button, the trailing edges lined up.
        static let underTrailing = PanelPlace(trigger: .bottomTrailing, panel: .topTrailing,
                                              offset: CGSize(width: 0, height: 4))
        /// Centered under a tab capsule, 6 pt below the title row.
        static let under = PanelPlace(trigger: .bottom, panel: .top,
                                      offset: CGSize(width: 0, height: (TitleBar.height - TabBar.height) / 2 + 6))
        /// Right of an Agents view row, 6 pt past the sidebar's edge (over the first card): the rows' inset and the
        /// 8 pt handle lie between.
        static let beside = PanelPlace(trigger: .topTrailing, panel: .topLeading,
                                       offset: CGSize(width: Sidebar.rowInsets.trailing + gap + 6, height: 0))
    }

    extension View {
        /// A panel that opens by this view after the pointer rests on it 0.25 s, stays while the pointer moves into
        /// it (0.15 s grace), and closes when the pointer leaves both, on a click or a scroll outside it, or with Esc.
        /// Not while a mouse button is down (a drag), nor while `enabled` is false (nothing to show). In the window,
        /// not a `.popover`: a popover is a window that takes the keyboard when it shows, and a resting pointer must
        /// not take keys from the terminal. `action` names an accessibility action that opens it.
        func hoverPanel(place: PanelPlace, action: String? = nil, enabled: Bool = true,
                        @ViewBuilder _ panel: @escaping (_ close: @escaping () -> Void) -> some View) -> some View
        {
            modifier(HoverPanel(place: place, action: action, enabled: enabled, panel: panel))
        }

        /// Draws the open hover panel over this view, the window's content: no scroll view or mask around its
        /// trigger clips it, and there is one at a time.
        func hoverPanelHost() -> some View {
            overlayPreferenceValue(OpenPanelKey.self) { open in
                // Always here, so the panel is the view inserted and scales about its own edge, not the window's.
                GeometryReader { proxy in
                    PanelLayout(trigger: open.map { proxy[$0.trigger] } ?? .zero, place: open?.place ?? .under) {
                        // In only: the panel would lose its place on the way out.
                        if let open {
                            open.content.transition(.asymmetric(
                                insertion: .opacity.combined(with: NSWorkspace.shared
                                    .accessibilityDisplayShouldReduceMotion ? .identity
                                    : .scale(scale: 0.97, anchor: open.place.panel))
                                    .animation(.easeOut(duration: 0.13)),
                                removal: .identity,
                            ))
                        }
                    }
                }
            }
        }
    }

    private struct OpenPanel {
        let trigger: Anchor<CGRect>
        let place: PanelPlace
        let content: AnyView
    }

    private struct OpenPanelKey: PreferenceKey {
        static var defaultValue: OpenPanel? {
            nil
        }

        static func reduce(value: inout OpenPanel?, nextValue: () -> OpenPanel?) {
            value = nextValue() ?? value
        }
    }

    /// Puts the panel at its place by the trigger, kept inside the window.
    private struct PanelLayout: Layout {
        let trigger: CGRect
        let place: PanelPlace

        func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
            proposal.replacingUnspecifiedDimensions()
        }

        func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
            guard let panel = subviews.first else { return }
            let size = panel.sizeThatFits(.unspecified)
            let left = trigger.minX + trigger.width * place.trigger.x - size.width * place.panel.x + place.offset.width
            let top = trigger.minY + trigger.height * place.trigger.y - size.height * place.panel.y + place.offset
                .height
            panel.place(at: CGPoint(x: bounds.minX + min(max(left, gap), bounds.width - gap - size.width),
                                    y: bounds.minY + min(max(top, gap), bounds.height - gap - size.height)),
                        proposal: ProposedViewSize(size))
        }
    }

    private struct HoverPanel<Panel: View>: ViewModifier {
        let place: PanelPlace
        let action: String?
        let enabled: Bool
        let panel: (_ close: @escaping () -> Void) -> Panel
        @State private var open = false
        @State private var overTrigger = false
        @State private var overPanel = false
        @State private var pending: Task<Void, Never>?
        @State private var monitor: Any?

        func body(content: Content) -> some View {
            content
                .onHover { overTrigger = $0
                    hovered()
                }
                // A click is not a rest: no panel until the pointer comes back (onHover fires only on entering).
                .simultaneousGesture(TapGesture().onEnded {
                    overTrigger = false
                    hovered()
                })
                .anchorPreference(key: OpenPanelKey.self, value: .bounds) { anchor in
                    open ? OpenPanel(trigger: anchor, place: place, content: AnyView(panel { show(false) }
                            .onHover { overPanel = $0
                                hovered()
                            })) : nil
                }
                .accessibilityActions {
                    if let action {
                        Button(action) { show(true) }
                    }
                }
                // Nothing left to show: it goes at once. It opens only on a hover, never under a still pointer.
                .onChange(of: enabled) {
                    if !enabled {
                        show(false)
                    }
                }
                .onDisappear { show(false) }
        }

        private func hovered() {
            pending?.cancel()
            let over = enabled && (overTrigger || overPanel)
            guard over != open, !over || NSEvent.pressedMouseButtons == 0 else { return }
            pending = Task {
                try? await Task.sleep(for: .milliseconds(over ? 250 : 150))
                // A drag may have started meanwhile.
                if !Task.isCancelled, !over || NSEvent.pressedMouseButtons == 0 {
                    show(over)
                }
            }
        }

        private func show(_ value: Bool) {
            pending?.cancel()
            open = value
            if value, monitor == nil {
                let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
                monitor = NSEvent.addLocalMonitorForEvents(matching: events) { event in
                    guard event.type != .keyDown || event.keyCode == 53 else { return event }
                    let escape = event.type == .keyDown
                    let swallow = MainActor.assumeIsolated {
                        if escape || !overPanel {
                            show(false)
                        }
                        // A text field that edits (a rename, a filter) still gets its Esc.
                        return escape && !(NSApp.keyWindow?.firstResponder is NSText)
                    }
                    return swallow ? nil : event
                }
            } else if !value {
                // A panel that goes from under the pointer sends no hover exit.
                overPanel = false
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
        }
    }

    /// Rex's "peek": a tab's title and rolled-up status, a preview of its cards, and a row for each of its first six
    /// panes. A click on a row goes to that pane; on the title or the preview, to the tab. A blocked agent's row shows
    /// its last screen lines (herdr 0.9.5 sends no blocked message), read each second while the card is open.
    struct HoverCard: View {
        let tabID: String
        let page: Page
        let close: () -> Void
        /// Screens read while the card is open: each blocked pane's, and each previewed pane's with no picture.
        @State private var screens: [String: String] = [:]

        var body: some View {
            let store = page.store
            if let workspace = store.workspace(of: tabID), let tab = workspace.tabs.first(where: { $0.id == tabID }) {
                let panes = store.panes.filter { $0.tabID == tabID }
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        page.select(workspace, tab: tabID)
                        close()
                    } label: {
                        HStack(spacing: 8) {
                            FadeText(text: page.titleLabel(tab)).fontWeight(.medium)
                            Spacer(minLength: 0)
                            if let state = store.strongest([tabID])?.state, state != .idle {
                                StateCapsule(state: state)
                            }
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 26)
                    }
                    .buttonStyle(ChromeStyle(radius: 6))
                    .accessibilityIdentifier("hovercard.title")
                    if let tree = tab.tree {
                        TabPreview(tree: tree, page: page, screens: screens)
                            .onTapGesture {
                                page.select(workspace, tab: tabID)
                                close()
                            }
                            .padding(.bottom, 2)
                    }
                    ForEach(panes.prefix(6)) { pane in row(pane) }
                    if panes.count > 6 {
                        Text("+\(panes.count - 6) more").font(.system(size: 11)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(6)
                // Not narrower when it fits: the screen lines come in after it shows and would widen it.
                .frame(width: 280, alignment: .leading)
                .floatingGlass(in: .rect(cornerRadius: 12))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Panes of \(page.titleText(tab))")
                .accessibilityIdentifier("hovercard")
                .task {
                    guard let client = store.client else { return }
                    // Again each second while it is open, so a pane with no picture is live too.
                    repeat {
                        for pane in panes where pane.state == .needsYou || TabPreview.picture(pane, page) == nil {
                            screens[pane.id] = try? await client.screen(pane.id)
                        }
                    } while await (try? Task.sleep(for: .seconds(1))) != nil
                }
            }
        }

        private func row(_ pane: HostStore.Pane) -> some View {
            let shown = pane.state == .needsYou ? Array((screens[pane.id] ?? "").split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(3)) : []
            let name = pane.agentName ?? pane.programName ?? "terminal"
            return Button {
                page.go(to: pane)
                close()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        ProgramGlyph(icon: pane.iconID, letter: pane.letter)
                        Text(name).lineLimit(1).layoutPriority(1)
                        Text(pane.folder ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if pane.state == .working {
                            WorkingDots()
                        } else if let state = pane.state {
                            StateCapsule(state: state)
                        }
                    }
                    ForEach(shown.indices, id: \.self) { index in
                        Text(shown[index]).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(minHeight: 26)
            }
            .buttonStyle(ChromeStyle(radius: 6))
            .accessibilityIdentifier("hovercard.\(pane.id)")
            .accessibilityLabel([name, pane.folder].compactMap(\.self).joined(separator: ", "))
            .accessibilityValue(([pane.state?.capsule].compactMap(\.self) + shown).joined(separator: "\n"))
        }
    }

    /// A tab's cards in their layout, as its page draws them in a 1056 × 660 pt page, at a quarter of that size. A card
    /// in the window shows its terminal's picture: the IOSurface libghostty's layer shows, shared, not copied, and read
    /// again 5 times a second while the preview is open, so it costs nothing while none is. Any other card (another
    /// tab, whose surface draws nothing or was let go) shows its screen's text, read each second (design: hover card).
    struct TabPreview: View {
        let tree: SplitNode
        let page: Page
        /// Screen text for the panes with no picture.
        let screens: [String: String]
        @Environment(\.look) private var look
        private static let scale: CGFloat = 0.25
        /// With its 2 pt padding, the hover card's width inside its own (268 pt).
        private static let size = CGSize(width: 264, height: 165)

        /// The picture libghostty's layer shows now (an IOSurface), while the terminal is in a window (only there does
        /// it draw) and once it showed the pane (a lazy page's terminal that never streamed is blank). Never makes a
        /// terminal.
        static func picture(_ pane: HostStore.Pane?, _ page: Page) -> (terminal: PaneTerminal, picture: Any)? {
            guard let terminal = pane?.terminalID.flatMap({ page.terminals.terminals([$0]).first }), terminal.revealed,
                  terminal.view.window != nil, let picture = terminal.view.layer?.contents,
                  terminal.view.frame.width > 0 else { return nil }
            return (terminal, picture)
        }

        var body: some View {
            let area = CGRect(x: 0, y: 0, width: Self.size.width / Self.scale, height: Self.size.height / Self.scale)
            let zoomed = page.zoomedPaneID.flatMap { tree.paneIDs.contains($0) ? $0 : nil }
            let cards = Parts(tree, in: area, held: [:]).cards.filter { zoomed == nil || $0.id == zoomed }
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                ZStack(alignment: .topLeading) {
                    ForEach(cards, id: \.id) { card in
                        let rect = zoomed == nil ? card.rect : area
                        self.card(card.id, tick: context.date)
                            .frame(width: rect.width * Self.scale, height: rect.height * Self.scale)
                            // By layout, not `.offset`, which leaves the accessibility frame at the corner.
                            .padding(.leading, rect.minX * Self.scale).padding(.top, rect.minY * Self.scale)
                    }
                }
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            }
            .padding(gap * Self.scale)
            .background(look.window, in: .rect(cornerRadius: 6, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hovercard.preview")
        }

        private func card(_ id: String, tick: Date) -> some View {
            let pane = page.store.pane(id), picture = Self.picture(pane, page)
            let shape = RoundedRectangle(cornerRadius: 3, style: .continuous), edge = look.edge(keyboard: false)
            return GeometryReader { proxy in
                let width = max(proxy.size.width - 4, 0)
                Group {
                    if let (terminal, picture) = picture {
                        let size = terminal.view.frame.size
                        TerminalPicture(picture: picture, tick: tick).frame(width: width,
                                                                            height: width * size.height / size.width)
                    } else if let text = screens[id] {
                        Text(text).font(.system(size: 3.25, design: .monospaced)).lineSpacing(0)
                            .fixedSize().frame(width: width, alignment: .topLeading)
                    }
                }
                .padding(2)
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

    /// Shows a terminal's picture: libghostty's IOSurface set as a layer's contents, scaled to the view. A
    /// layer-hosting view, so AppKit never draws over the contents.
    private struct TerminalPicture: NSViewRepresentable {
        let picture: Any
        /// A new tick makes SwiftUI update the view, which reads the surface's latest picture.
        let tick: Date

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            view.layer = CALayer()
            view.wantsLayer = true
            view.layer?.contentsGravity = .resize
            return view
        }

        func updateNSView(_ view: NSView, context _: Context) {
            view.layer?.contents = picture
        }
    }
#endif
