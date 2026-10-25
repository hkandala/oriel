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
        /// 1…9 while ⌘ is held: "⌘1" at the end.
        let keycap: Int?
        /// Before a click selects it.
        let clicked: () -> Void
        @State private var renaming = false
        /// "codex needs you" for 3 s in place of the title.
        @State private var announcement: String?
        @State private var announcing: Task<Void, Never>?
        @State private var bounces = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.look) private var look

        var body: some View {
            let store = page.store
            let selected = workspace.id == page.selectedWorkspaceID && tab.id == page.selectedTabIDs[workspace.id]
            let stack = page.stack(tab)
            let agent = store.strongest([tab.id])
            let working = store.panes.contains { $0.tabID == tab.id && $0.state == .working }
            // The strip scrolls to the new selection and the marker follows, as during a swipe.
            Button {
                clicked()
                page.select(workspace, tab: tab.id)
            } label: {
                HStack(spacing: 10) {
                    IconStack(panes: stack, badge: agent?.state)
                        .keyframeAnimator(initialValue: 1.0, trigger: bounces) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            SpringKeyframe(1.15, duration: 0.15)
                            SpringKeyframe(1, duration: 0.3)
                        }
                    // Not once the user selected the tab.
                    FadeText(text: announcement.flatMap { selected ? nil : Text($0) } ?? page.titleLabel(tab))
                        .opacity(renaming ? 0 : 1)
                        .foregroundStyle(selected ? look.selected : look.chrome)
                    // The keycap's room: the title gives way to it.
                    if let keycap {
                        Keycap(text: "⌘\(keycap)").hidden()
                    }
                }
                .padding(.leading, 11)
                // The title's fade ends under the ×'s 28 pt.
                .padding(.trailing, keycap == nil ? 12 : keycapInset)
                .frame(width: TabBar.width, height: TabBar.height, alignment: .leading)
            }
            // The selection is the tab bar's marker.
            .buttonStyle(ChromeStyle(radius: TabBar.radius, inset: TabBar.inset))
            .dragSource(.tab(tab.id), page: page)
            // Anywhere on the capsule, beside the click that selects (a tap gesture in the label missed clicks past a
            // short title).
            .simultaneousGesture(TapGesture(count: 2).onEnded { renaming = true })
            // On the capsule alone: the rename field and the × over it have their own.
            .accessibilityIdentifier("tab.\(tab.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue([lit ? "in view" : nil, agent.flatMap { agent in
                agent.state == .idle ? nil : "\(agent.agentName ?? "agent"), \(agent.state?.word ?? "")"
            }, "icons: " + stack.map(\.iconID).joined(separator: ", ")].compactMap(\.self).joined(separator: "; "))
            .accessibilityAction(named: "Close Tab") { page.close(.tab(tab.id)) }
            .hoverPanel(place: .under, action: "Show Panes") { close in
                HoverCard(tabID: tab.id, page: page, close: close)
            }
            // Over the button, after the icons: in the button's label it could not take the keyboard.
            .overlay(alignment: .leading) {
                if renaming {
                    // Enter: herdr's label; the snapshot after it shows it.
                    RenameField(prompt: "Tab Name", initial: tab.label, commit: { label in
                        Task { await page.store.rename(tab: tab.id, label: label) }
                    }, end: stopRenaming)
                        .padding(.leading, 11 + 22 + CGFloat(max(stack.count - 1, 0)) * 4 + 10)
                        .padding(.trailing, 8)
                        .accessibilityIdentifier("tab.\(tab.id).rename")
                }
            }
            // The status slot: × while hovered, else the working dots (the selected tab too, user, phase 25) unless a
            // keycap is in it.
            .overlay(alignment: .trailing) {
                if working, keycap == nil, !hovering || renaming {
                    WorkingDots().padding(.trailing, 10)
                        .accessibilityElement().accessibilityLabel("working")
                        .accessibilityIdentifier("tab.\(tab.id).working")
                }
            }
            // At the end, beside the ×: never over the icon or the title (user, phase 25). Over the button, so a test
            // sees its frame.
            .overlay(alignment: .trailing) {
                if let keycap, !renaming {
                    Keycap(text: "⌘\(keycap)").padding(.trailing, keycapInset)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.13)),
                                                removal: .opacity.animation(.easeOut(duration: 0.1))))
                        .accessibilityIdentifier("tab.\(tab.id).keycap")
                }
            }
            .overlay(alignment: .trailing) {
                // Over the title's fade, so it never changes the tab's width.
                if hovering, !renaming {
                    Button { page.close(.tab(tab.id)) } label: {
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

        /// The keycap's end: the status slot, or left of the × while hovered.
        private var keycapInset: CGFloat {
            hovering && !renaming ? 32 : 10
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
            Button("Rename Tab") { renaming = true }
            Button("Move Tab Left") { Task { await store.move(tab: tab.id, by: -1) } }
                .disabled(tabs.first?.id == tab.id)
            Button("Move Tab Right") { Task { await store.move(tab: tab.id, by: 1) } }
                .disabled(tabs.last?.id == tab.id)
            Divider()
            Button("Close Tab") { page.close(.tab(tab.id)) }
            Button("Close Other Tabs") { page.closeTabs(besides: tab.id, right: false) }
                .disabled(tabs.count < 2)
            Button("Close Tabs to the Right") { page.closeTabs(besides: tab.id, right: true) }
                .disabled(tabs.last?.id == tab.id)
        }

        /// The keyboard goes back to the tab's card.
        private func stopRenaming() {
            guard renaming else { return }
            renaming = false
            page.focusKeyboardCard()
        }
    }

    /// A jump key's hint ("⌘1") on a tab or a workspace row while its modifiers are held.
    struct Keycap: View {
        let text: String

        var body: some View {
            Text(text).font(.system(size: 10, weight: .semibold)).fixedSize()
                .padding(.horizontal, 4).padding(.vertical, 1)
                .glassEffect(.regular, in: .rect(cornerRadius: 4))
        }
    }

    extension View {
        /// `shown` turns on once `modifiers` alone are held 0.7 s with the window key, and off when they change; a key
        /// pressed first (⌘T) cancels. ⌘ for the tabs' keycaps, ⌃⌘ for the workspace rows'.
        func keycapHints(_ modifiers: NSEvent.ModifierFlags, _ shown: Binding<Bool>) -> some View {
            modifier(KeycapHints(modifiers: modifiers, shown: shown))
        }
    }

    private struct KeycapHints: ViewModifier {
        let modifiers: NSEvent.ModifierFlags
        @Binding var shown: Bool
        @State private var pending: Task<Void, Never>?
        @State private var monitor: Any?
        @Environment(\.appearsActive) private var appearsActive

        func body(content: Content) -> some View {
            content
                .onAppear {
                    if monitor == nil {
                        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: watch)
                    }
                }
                .onDisappear {
                    pending?.cancel()
                    monitor.map(NSEvent.removeMonitor)
                    monitor = nil
                }
                // ⌘-Tab away: the ⌘ release goes to the other app.
                .onChange(of: appearsActive) {
                    if !appearsActive {
                        pending?.cancel()
                        shown = false
                    }
                }
        }

        private func watch(_ event: NSEvent) -> NSEvent? {
            MainActor.assumeIsolated {
                pending?.cancel()
                let held = event.modifierFlags.intersection([.command, .shift, .option, .control]) == modifiers
                // ponytail: any key window of the app, so keys held in one window light every window's keycaps;
                // compare event.window to this view's window to stop that.
                if event.type == .flagsChanged, held, event.window?.isKeyWindow == true {
                    pending = Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        if !Task.isCancelled {
                            shown = true
                        }
                    }
                } else if !held {
                    shown = false
                }
            }
            return event
        }
    }

    extension Page {
        /// Close Other Tabs, or Close Tabs to the Right (`right`), of the tab: asks first when a program runs in them.
        func closeTabs(besides tabID: String, right: Bool) {
            guard let tabs = store.workspace(of: tabID)?.tabs.map(\.id), let index = tabs.firstIndex(of: tabID)
            else { return }
            let others = right ? Array(tabs[(index + 1)...]) : tabs.filter { $0 != tabID }
            if !others.isEmpty {
                close(.otherTabs(others, right: right))
            }
        }

        /// The title with its folder dimmed, for the capsule and the hover card.
        func titleLabel(_ tab: HostStore.Tab) -> Text {
            let title = title(tab)
            return Text("\(title.name)\(Text(title.folder.map { " \($0)" } ?? "").foregroundStyle(.secondary))")
        }
    }

    extension Page {
        /// The tab's title, from herdr's label; herdr's default label (a bare number) gives the front card's program
        /// and folder instead (D65), "New Tab" until the program is known (a new pane's is asked a second late).
        func title(_ tab: HostStore.Tab) -> (name: String, folder: String?) {
            guard tab.label.allSatisfy(\.isNumber) else { return (tab.label, nil) }
            guard let pane = stack(tab).first, let name = pane.programName else {
                // A new tab (a stand-in, or a pane whose shell still starts): "New Tab", never a number. Else the
                // number, for a pane whose program herdr cannot say.
                return (stack(tab).first?.starting == false ? tab.label : "New Tab", nil)
            }
            // The folder's name ("pi oriel"), as in Rex: a tab is narrow.
            return (name, pane.folder.map { $0 == "~" ? $0 : ($0 as NSString).lastPathComponent })
        }

        /// The title in one string, for the window title and menus.
        func titleText(_ tab: HostStore.Tab) -> String {
            let title = title(tab)
            return [title.name, title.folder ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
#endif
