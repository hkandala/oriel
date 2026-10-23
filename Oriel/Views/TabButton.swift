#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// One tab's capsule: its program icons and title, × while hovered. Its own view, so a status change redraws this
    /// tab only (design D6).
    struct TabButton: View {
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
        @Environment(\.look) private var look

        var body: some View {
            let store = page.store
            let selected = workspace.id == page.selectedWorkspaceID && tab.id == page.selectedTabIDs[workspace.id]
            let stack = page.stack(tab)
            let agent = store.strongest([tab.id])
            let working = !selected && store.panes.contains { $0.tabID == tab.id && $0.state == .working }
            // The strip scrolls to the new selection and the marker follows, as during a swipe.
            Button { page.select(workspace, tab: tab.id) } label: {
                HStack(spacing: 10) {
                    IconStack(panes: stack, badge: agent?.state)
                        .keyframeAnimator(initialValue: 1.0, trigger: bounces) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            SpringKeyframe(1.15, duration: 0.15)
                            SpringKeyframe(1, duration: 0.3)
                        }
                        .overlay(alignment: .leading) {
                            if let keycap {
                                Text("⌘\(keycap)").font(.system(size: 10, weight: .semibold)).fixedSize()
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .glassEffect(.regular, in: .rect(cornerRadius: 4))
                                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.13)),
                                                            removal: .opacity.animation(.easeOut(duration: 0.1))))
                            }
                        }
                    // Not once the user selected the tab.
                    FadeText(text: announcement.flatMap { selected ? nil : Text($0) } ?? page.titleLabel(tab))
                        .opacity(renaming ? 0 : 1)
                        .foregroundStyle(selected ? look.selected : look.chrome)
                }
                .padding(.leading, 11)
                // The title's fade ends under the ×'s 28 pt.
                .padding(.trailing, 12)
                .frame(width: width, height: TabBar.height, alignment: .leading)
            }
            // The selection is the tab bar's marker.
            .buttonStyle(ChromeStyle(radius: TabBar.radius, inset: TabBar.inset))
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
            .accessibilityAction(named: "Close Tab") { page.closing = .tab(tab.id) }
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
                        .padding(.leading, 11 + 22 + CGFloat(max(stack.count - 1, 0)) * 4 + 10)
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
                        page.closing = .tab(tab.id)
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
            Button("Close Tab") { page.closing = .tab(tab.id) }
            Button("Close Other Tabs") { page.closing = .otherTabs(tabs.map(\.id).filter { $0 != tab.id }) }
                .disabled(tabs.count < 2)
        }

        private func startRenaming() {
            draft = tab.label
            renaming = true
        }

        /// Enter: herdr's label; the snapshot after it shows it.
        private func rename() {
            Task { [draft] in await page.store.rename(tab: tab.id, label: draft) }
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
