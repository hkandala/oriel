#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// The selected workspace's tabs in the title row (D42): equal widths on a track, one marker that follows the
    /// strip's scroll, dividers, hover and close. It takes the row's free space and scrolls when tabs would be narrower
    /// than 64 pt.
    struct TabBar: View {
        static let height: CGFloat = 34
        /// min(height / 2, 16.5), as in Rex.
        static let radius: CGFloat = 16.5

        let workspace: HostStore.Workspace
        let page: Page
        /// A pane dragged over the `+`; with one over the track's end, a ghost capsule at the end, when it fits.
        let plus: Bool
        @State private var end = false
        /// A drag over the track: the capsule a pane is over, or the place a dragged tab goes.
        @State private var over: Int?
        @State private var spring: Task<Void, Never>?
        /// The capsule that just spring-loaded, scaled up for a moment.
        @State private var pulsing: String?
        /// The row's free space.
        @State private var space: CGFloat = 0
        @State private var hovered: String?
        /// The width before a close, kept while the pointer stays in the bar, so the next × is under it (Safari).
        @State private var kept: CGFloat?
        /// ⌘ held for 0.7 s: keycaps on the first nine tabs.
        @State private var hints = false
        @State private var pendingHints: Task<Void, Never>?
        @State private var monitor: Any?
        @State private var insideBar = false
        @Environment(\.appearsActive) private var appearsActive
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let tabs = workspace.tabs, count = CGFloat(tabs.count)
            let width = kept ?? min(max((space - (count - 1)) / count, 64), 220)
            let content = count * width + count - 1
            // Pages floor(x/w) through ceil((x+w)/w) − 1, that is floor(page)...ceil(page).
            let lit = Int(page.stripPage.rounded(.down)) ... Int(page.stripPage.rounded(.up))
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            // One view per tab, so a scroll to its id shows the tab, not the divider before it.
                            HStack(spacing: 0) {
                                if index > 0 {
                                    // Hidden next to the marker, the selected tab and the pointer.
                                    let quiet = lit.contains(index) || lit.contains(index - 1)
                                        || [tab.id, tabs[index - 1].id]
                                        .contains { $0 == hovered || $0 == page.selectedTabIDs[workspace.id] }
                                    Rectangle().fill(.separator).frame(width: 1, height: Self.height - 18)
                                        .opacity(quiet ? 0 : 1)
                                        .animation(.easeInOut(duration: 0.2), value: quiet)
                                }
                                TabButton(tab: tab, workspace: workspace, page: page, lit: lit.contains(index),
                                          hovering: hovered == tab.id, width: width,
                                          keycap: hints && index < 9 ? index + 1 : nil) { kept = width }
                                    .onHover { hovered = $0 ? tab.id : hovered == tab.id ? nil : hovered }
                                    .overlay {
                                        if page.dragging?.paneID != nil, over == index {
                                            DropIndicator(radius: Self.radius)
                                        }
                                    }
                                    .scaleEffect(pulsing == tab.id ? 1.04 : 1)
                                    .opacity(page.dragging == .tab(tab.id) ? 0.4 : 1)
                                    .offset(x: shift(index, width: width))
                            }
                        }
                    }
                    // In the content's space: the capsule under the pointer, wherever the track scrolled.
                    .onDrop(of: [.orielDrag], delegate: TrackDrop(tabs: tabs, page: page, slot: width + 1,
                                                                  over: $over, spring: $spring, springLoad: springLoad))
                    .background {
                        ZStack(alignment: .leading) {
                            Capsule().fill(.primary.opacity(0.05)).opacity(tabs.count > 1 ? 1 : 0)
                            marker(count: tabs.count, width: width)
                        }
                    }
                    // Room for the Classic pill's shadow (radius 3.5, y 1.5): the scroll view clips.
                    .padding(.vertical, 5)
                }
                .scrollIndicators(.never)
                // Tabs that do not fit fade out at the edges instead of being cut.
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 8)
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                    }
                    .padding(content > space ? 0 : -16)
                }
                .frame(width: max(min(content, space), 0))
                .onHover { inside in
                    insideBar = inside
                    // Not while the close dialog is up: a Return there keeps the pointer over the next ×.
                    if !inside, page.store.closing == nil {
                        settle()
                    }
                }
                .onChange(of: page.store.closing == nil) { _, closed in
                    if closed, !insideBar {
                        settle()
                    }
                }
                // minWidth 0: the row's free space, not the tabs' width, which follows it; else the bar never
                // shrinks (a workspace button that appears pushed ⌘ and + out of the window).
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                // The track's empty end, after the tabs (not behind them: a `.forbidden` over the pane's own capsule
                // would fall through to it): a new tab in the workspace, shown as a ghost capsule.
                .overlay(alignment: .leading) {
                    // It takes the clicks of the row's empty space, so it moves the window as that space does.
                    Color.clear.contentShape(.rect).gesture(WindowDragGesture())
                        .overlay(alignment: .leading) {
                            if end || plus, content + 1 + width <= space {
                                DropIndicator(radius: Self.radius).frame(width: width, height: Self.height)
                                    .padding(.leading, 1)
                            }
                        }
                        .onDrop(of: [.orielDrag], delegate: PaneDrop(page: page,
                                                                     target: .move(.newTab(workspaceID: workspace.id)),
                                                                     over: $end))
                        .padding(.leading, min(content, space))
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { space = $0 }
                .onChange(of: page.selectedTabIDs[workspace.id], initial: true) { old, new in
                    if let new {
                        withAnimation(old != new && !reduceMotion ? .tab : nil) { proxy.scrollTo(new) }
                    }
                }
            }
            .frame(height: Self.height + 10)
            .onAppear {
                if monitor == nil {
                    monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: watch)
                }
            }
            .onDisappear {
                spring?.cancel()
                pendingHints?.cancel()
                monitor.map(NSEvent.removeMonitor)
                monitor = nil
            }
            // ⌘-Tab away: the ⌘ release goes to the other app.
            .onChange(of: appearsActive) {
                if !appearsActive {
                    pendingHints?.cancel()
                    hints = false
                }
            }
        }

        /// A tab dragged along the track: it and the tabs it passes trade places as it goes (the others slide apart).
        private func shift(_ index: Int, width: CGFloat) -> CGFloat {
            guard case let .tab(id) = page.dragging, let slot = over,
                  let from = workspace.tabs.firstIndex(where: { $0.id == id }) else { return 0 }
            let place = slot > from ? slot - 1 : slot
            return (width + 1) * CGFloat(index == from ? place - from
                : from < index && index <= place ? -1 : place <= index && index < from ? 1 : 0)
        }

        /// Holding a pane over a capsule selects its tab, which pulses once.
        private func springLoad(_ tabID: String) {
            page.select(workspace, tab: tabID)
            withAnimation(.easeOut(duration: 0.1)) { pulsing = tabID }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeOut(duration: 0.1)) { pulsing = nil }
            }
        }

        /// Back to widths for the space, once the pointer left after a close.
        private func settle() {
            if kept != nil {
                withAnimation(reduceMotion ? nil : .tab) { kept = nil }
            }
        }

        /// The look's pill on the page in view, between two tabs while the strip is between their pages. The strip
        /// moves with Rex's spring after a click or a key, so the marker does too.
        private func marker(count: Int, width: CGFloat) -> some View {
            let offset = min(max(page.stripPage, 0), Double(max(count - 1, 0)))
            return Pill(shape: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                .frame(width: width, height: Self.height)
                .offset(x: offset * (width + 1))
                .allowsHitTesting(false)
        }

        /// ⌘ alone held 0.7 s with the window key shows the keycaps; releasing it hides them. A key pressed first
        /// (⌘T) cancels.
        private func watch(_ event: NSEvent) -> NSEvent? {
            MainActor.assumeIsolated {
                pendingHints?.cancel()
                let command = event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
                // ponytail: any key window of the app; phase 16's windows need this bar's own window here.
                if event.type == .flagsChanged, command, event.window?.isKeyWindow == true {
                    pendingHints = Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        if !Task.isCancelled {
                            hints = true
                        }
                    }
                } else if !command {
                    hints = false
                }
            }
            return event
        }
    }

    /// One tab's capsule: its program icons and title, × while hovered. Its own view, so a status change redraws this
    /// tab only (design D6).
    private struct TabButton: View {
        let tab: HostStore.Tab
        let workspace: HostStore.Workspace
        let page: Page
        /// Its page is in view.
        let lit: Bool
        let hovering: Bool
        let width: CGFloat
        /// ⌘1…⌘9 while ⌘ is held.
        let keycap: Int?
        /// Before a close from its ×.
        let closing: () -> Void
        @State private var renaming = false
        @State private var draft = ""
        /// "codex needs you" for 3 s in place of the title.
        @State private var announcement: String?
        @State private var announcing: Task<Void, Never>?
        @State private var bounces = 0
        @FocusState private var focused: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let store = page.store
            let selected = workspace.id == page.selectedWorkspaceID && tab.id == page.selectedTabIDs[workspace.id]
            let stack = page.stack(tab)
            let agent = store.strongest([tab.id])
            let working = !selected && store.panes.contains { $0.tabID == tab.id && $0.state == .working }
            // The strip scrolls to the new selection and the marker follows, as during a swipe.
            Button { page.select(workspace, tab: tab.id) } label: {
                HStack(spacing: 8) {
                    IconStack(panes: stack, badge: agent?.state)
                        .keyframeAnimator(initialValue: 1.0, trigger: bounces) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            SpringKeyframe(1.15, duration: 0.15)
                            SpringKeyframe(1, duration: 0.3)
                        }
                        .overlay(alignment: .leading) {
                            if let keycap {
                                Text("⌘\(keycap)").font(.system(size: 10, weight: .semibold)).fixedSize().padding(
                                    .horizontal,
                                    4,
                                )
                                .padding(.vertical, 1).glassEffect(.regular, in: .rect(cornerRadius: 4))
                                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.13)),
                                                        removal: .opacity.animation(.easeOut(duration: 0.1))))
                            }
                        }
                    // Not once the user selected the tab.
                    FadeText(text: announcement.flatMap { selected ? nil : Text($0) } ?? page.titleLabel(tab))
                        .opacity(renaming ? 0 : 1)
                }
                .padding(.leading, 8)
                // The title's fade ends under the ×'s 28 pt.
                .padding(.trailing, 12)
                .frame(width: width, height: TabBar.height, alignment: .leading)
            }
            // The selection is the tab bar's marker.
            .buttonStyle(ChromeStyle(radius: TabBar.radius))
            .dragSource(.tab(tab.id), page: page)
            // Anywhere on the capsule, beside the click that selects (a tap gesture in the label missed clicks past a
            // short title).
            .simultaneousGesture(TapGesture(count: 2).onEnded { startRenaming() })
            // On the capsule alone: the rename field and the × over it have their own.
            .accessibilityIdentifier("tab.\(tab.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue([lit ? "in view" : nil, agent.flatMap { agent in
                agent.state == .idle ? nil : "\(agent.agentName ?? "agent"), \(agent.state?.word ?? "")"
            }, "icons: " + stack.map(\.iconID).joined(separator: ", ")].compactMap(\.self).joined(separator: "; "))
            .accessibilityAction(named: "Close Tab") { store.closing = .tab(tab.id) }
            .hoverPanel(place: .under, action: "Show Panes") { close in
                HoverCard(tabID: tab.id, page: page, close: close)
            }
            // Over the button, after the icons: in the button's label it could not take the keyboard.
            .overlay(alignment: .leading) {
                if renaming {
                    TextField("Tab Name", text: $draft).textFieldStyle(.plain).focused($focused)
                        .onSubmit { rename() }
                        .onExitCommand { stopRenaming() }
                        .onChange(of: focused) { _, now in
                            if !now {
                                stopRenaming()
                            }
                        }
                        .focusSoon($focused)
                        .padding(.leading, 8 + 22 + CGFloat(max(stack.count - 1, 0)) * 4 + 8)
                        .padding(.trailing, 8)
                        .accessibilityIdentifier("tab.\(tab.id).rename")
                }
            }
            // The status slot: × while hovered, else the working dots (not on the selected tab).
            .overlay(alignment: .trailing) {
                if working, !hovering || renaming || width < 52 {
                    WorkingDots().padding(.trailing, 10)
                        .accessibilityElement().accessibilityLabel("working")
                        .accessibilityIdentifier("tab.\(tab.id).working")
                }
            }
            .overlay(alignment: .trailing) {
                // Over the title's fade, so it never changes the tab's width.
                if hovering, !renaming, width >= 52 {
                    Button {
                        closing()
                        store.closing = .tab(tab.id)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(ChromeStyle(radius: 11))
                    .help("Close Tab")
                    .accessibilityLabel("Close Tab")
                    .accessibilityIdentifier("tab.\(tab.id).close")
                    .padding(.trailing, 6)
                }
            }
            .contextMenu { menu }
            .onChange(of: agent?.state) { _, new in
                guard let new, new >= .finishedUnseen, !selected else { return }
                announce("\(agent?.agentName ?? "agent") \(new.word)")
            }
        }

        /// The front icon bounces once and the title says what happened for 3 s.
        private func announce(_ text: String) {
            if !reduceMotion {
                bounces += 1
            }
            announcement = text
            announcing?.cancel()
            announcing = Task {
                if await (try? Task.sleep(for: .seconds(3))) != nil {
                    announcement = nil
                }
            }
        }

        @ViewBuilder
        private var menu: some View {
            let tabs = workspace.tabs, store = page.store
            Button("Rename Tab") { startRenaming() }
            Button("Move Tab Left") { Task { await store.move(tab: tab.id, by: -1) } }
                .disabled(tabs.first?.id == tab.id)
            Button("Move Tab Right") { Task { await store.move(tab: tab.id, by: 1) } }
                .disabled(tabs.last?.id == tab.id)
            Divider()
            Button("Close Tab") { store.closing = .tab(tab.id) }
            Button("Close Other Tabs") { store.closing = .otherTabs(tabs.map(\.id).filter { $0 != tab.id }) }
                .disabled(tabs.count < 2)
        }

        private func startRenaming() {
            draft = tab.label
            renaming = true
        }

        /// Enter: herdr's label, unless empty or the same; the snapshot after it shows it.
        private func rename() {
            let label = draft.trimmingCharacters(in: .whitespaces)
            if !label.isEmpty, label != tab.label {
                Task { await page.store.rename(tab: tab.id, label: label) }
            }
            stopRenaming()
        }

        /// The keyboard goes back to the tab's card.
        private func stopRenaming() {
            guard renaming else { return }
            renaming = false
            page.focusKeyboardCard()
        }
    }

    extension Page {
        /// The title with its folder dimmed, for the capsule and the hover card.
        func titleLabel(_ tab: HostStore.Tab) -> Text {
            let title = title(tab)
            return Text("\(title.name)\(Text(title.folder.map { " \($0)" } ?? "").foregroundStyle(.secondary))")
        }
    }
#endif
