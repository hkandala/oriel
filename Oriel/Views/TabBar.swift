#if os(macOS)
    import SwiftUI

    /// The selected workspace's tabs in the title row (D42): equal widths on a track, one marker that follows the
    /// strip's scroll, dividers, hover and close. It takes the row's free space and scrolls when tabs would be narrower
    /// than 64 pt.
    struct TabBar: View {
        static let height: CGFloat = 34
        /// min(height / 2, 16.5), as in Rex.
        static let radius: CGFloat = 16.5

        let workspace: HostStore.Workspace
        let store: HostStore
        /// The row's free space.
        @State private var space: CGFloat = 0
        @State private var hovered: String?
        /// The width before a close, kept while the pointer stays in the bar, so the next × is under it (Safari).
        @State private var kept: CGFloat?
        /// ⌘ held for 0.7 s: keycaps on the first nine tabs.
        @State private var hints = false
        @State private var pendingHints: Task<Void, Never>?
        @State private var monitor: Any?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let tabs = workspace.tabs, count = CGFloat(tabs.count)
            let width = kept ?? min(max((space - (count - 1)) / count, 64), 220)
            let content = count * width + count - 1
            // Pages floor(x/w) through ceil((x+w)/w) − 1, that is floor(page)...ceil(page).
            let lit = Int(store.page.rounded(.down)) ... Int(store.page.rounded(.up))
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            // One view per tab, so a scroll to its id shows the tab, not the divider before it.
                            HStack(spacing: 0) {
                                if index > 0 {
                                    // Hidden next to the marker and the pointer.
                                    let quiet = lit.contains(index) || lit.contains(index - 1)
                                        || [tab.id, tabs[index - 1].id].contains(hovered)
                                    Rectangle().fill(.separator).frame(width: 1, height: Self.height - 18)
                                        .opacity(quiet ? 0 : 1)
                                        .animation(.easeInOut(duration: 0.2), value: quiet)
                                }
                                TabButton(tab: tab, workspace: workspace, store: store, lit: lit.contains(index),
                                          hovering: hovered == tab.id, width: width,
                                          keycap: hints && index < 9 ? index + 1 : nil) { kept = width }
                                    .onHover { hovered = $0 ? tab.id : hovered == tab.id ? nil : hovered }
                            }
                        }
                    }
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
                    if !inside, kept != nil {
                        withAnimation(reduceMotion ? nil : .tab) { kept = nil }
                    }
                }
                // minWidth 0: the row's free space, not the tabs' width, which follows it; else the bar never
                // shrinks (a workspace button that appears pushed ⌘ and + out of the window).
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { space = $0 }
                .onChange(of: workspace.selectedTabID, initial: true) { old, new in
                    if let new {
                        withAnimation(old != new && !reduceMotion ? .default : nil) { proxy.scrollTo(new) }
                    }
                }
            }
            .frame(height: Self.height + 10)
            .onAppear { monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: watch)
            }
            .onDisappear {
                monitor.map(NSEvent.removeMonitor)
                monitor = nil
            }
        }

        /// The look's pill on the page in view, between two tabs while the strip is between their pages. The strip
        /// moves with Rex's spring after a click or a key, so the marker does too.
        private func marker(count: Int, width: CGFloat) -> some View {
            let page = min(max(store.page, 0), Double(max(count - 1, 0)))
            return Pill(shape: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                .frame(width: width, height: Self.height)
                .offset(x: page * (width + 1))
                .allowsHitTesting(false)
        }

        /// ⌘ alone held 0.7 s with the window key shows the keycaps; releasing it hides them. A key pressed first
        /// (⌘T) cancels.
        private func watch(_ event: NSEvent) -> NSEvent? {
            MainActor.assumeIsolated {
                pendingHints?.cancel()
                let command = event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
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
        let store: HostStore
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
        @FocusState private var focused: Bool

        var body: some View {
            let selected = workspace.id == store.selectedWorkspaceID && tab.id == workspace.selectedTabID
            let stack = store.stack(tab)
            let title = store.title(tab)
            Button {
                store.selectedWorkspaceID = workspace.id
                // The strip scrolls to the new selection and the marker follows, as during a swipe.
                workspace.selectedTabID = tab.id
            } label: {
                HStack(spacing: 8) {
                    IconStack(panes: stack)
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
                    FadeText(
                        text: Text(
                            "\(title.name)\(Text(title.folder.map { " \($0)" } ?? "").foregroundStyle(.secondary))",
                        ),
                    )
                    .opacity(renaming ? 0 : 1)
                    .onTapGesture(count: 2) { startRenaming() }
                }
                .padding(.horizontal, 8)
                .frame(width: width, height: TabBar.height, alignment: .leading)
            }
            // The selection is the tab bar's marker.
            .buttonStyle(ChromeStyle(radius: TabBar.radius))
            // On the capsule alone: the rename field and the × over it have their own.
            .accessibilityIdentifier("tab.\(tab.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue((lit ? "in view; " : "") + "icons: " + stack.map(\.iconID).joined(separator: ", "))
            .accessibilityAction(named: "Close Tab") { store.closing = .tab(tab.id) }
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
        }

        @ViewBuilder
        private var menu: some View {
            let tabs = workspace.tabs
            Button("Rename Tab") { startRenaming() }
            Button("Move Tab Left") { Task { await store.move(tab: tab.id, by: -1) } }
                .disabled(tabs.first?.id == tab.id)
            Button("Move Tab Right") { Task { await store.move(tab: tab.id, by: 1) } }
                .disabled(tabs.last?.id == tab.id)
            Divider()
            Button("Close Tab") { store.closing = .tab(tab.id) }
            Button("Close Other Tabs") { store.closing = .otherTabs(tab.id) }
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
                Task { await store.rename(tab: tab.id, label: label) }
            }
            stopRenaming()
        }

        /// The keyboard goes back to the tab's card.
        private func stopRenaming() {
            guard renaming else { return }
            renaming = false
            store.focusKeyboardCard()
        }
    }
#endif
