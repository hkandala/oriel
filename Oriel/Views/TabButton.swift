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
        let selected = workspace.id == page.selectedWorkspaceID && tab.id == page.selectedTabIDs[workspace.id]
        let stack = page.stack(tab)
        let agent = tab.agent, working = tab.working
        Button {
            clicked()
            page.select(workspace, tab: tab.id)
            // Anywhere on the capsule. AppKit's double-click, counted from the events' times: SwiftUI's
            // TapGesture(count: 2) missed one while the app drew the first click (as on a workspace row).
            if let event = NSApp.currentEvent, event.type == .leftMouseUp, event.clickCount == 2 {
                renaming = true
            }
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
            // The title fades out before the × (its 22 pt circle ends 28 pt from the end) or the working dots (24 pt),
            // else at 12 pt.
            .padding(.trailing, keycap != nil ? keycapInset : hovering && !renaming || working ? 28 : 12)
            .frame(width: TabBar.width, height: TabBar.height, alignment: .leading)
        }
        // The selection is the tab bar's marker.
        .buttonStyle(ChromeStyle(radius: TabBar.radius, inset: TabBar.inset))
        .dragSource(.tab(tab.id), page: page)
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
        // The status slot: × while hovered, else the working dots (the selected tab too) unless a
        // keycap is in it.
        .overlay(alignment: .trailing) {
            if working, keycap == nil, !hovering || renaming {
                WorkingDots().padding(.trailing, 10)
                    .accessibilityElement().accessibilityLabel("working")
                    .accessibilityIdentifier("tab.\(tab.id).working")
            }
        }
        // At the end, beside the ×: never over the icon or the title. Over the button, so a test
        // sees its frame.
        .overlay(alignment: .trailing) {
            if let keycap, !renaming {
                Keycap(text: "⌘\(keycap)").padding(.trailing, keycapInset)
                    .transition(Keycap.transition)
                    .accessibilityIdentifier("tab.\(tab.id).keycap")
            }
        }
        .overlay(alignment: .trailing) {
            // Over the capsule, so it never changes the tab's width.
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
        // The stack's first, without the stack: the menus ask for every tab's title.
        let front = keyboardCard(tab.id) ?? store.panes(in: tab.id).first
        // "Browser" and its page dimmed, as a terminal's "zsh oriel".
        if let pane = front, let label = pane.browser {
            return ("Browser", browserTitle(pane, label))
        }
        // Its front card asks what it runs (ui/new-pane): "New Tab", as the card's header says "New Pane".
        let choosing = front.map { store.chooser($0.id) != nil } ?? false
        guard let pane = front, let name = pane.programName, !choosing else {
            // A new tab (a stand-in, or a pane whose shell still starts): "New Tab", never a number. Else the
            // number, for a pane whose program herdr cannot say.
            return (front?.starting == false && !choosing ? tab.label : "New Tab", nil)
        }
        // An agent's session title ("Claude Code Fix login"); else the folder's name ("zsh oriel"), as in Rex: a tab is
        // narrow.
        if let title = pane.agentTitle {
            return (pane.agentLabel ?? name, title)
        }
        return (name, pane.cwd.map { $0 == Self.home ? "~" : ($0 as NSString).lastPathComponent })
    }

    private static let home = NSHomeDirectory()

    /// The tab's panes for its icon stack, at most 5: the keyboard card's first (herdr's focused pane until one
    /// had the keyboard), then herdr's order.
    func stack(_ tab: HostStore.Tab) -> [HostStore.Pane] {
        let tabPanes = store.panes(in: tab.id)
        let front = keyboardCard(tab.id)
        return Array(([front].compactMap(\.self) + tabPanes.filter { $0 !== front }).prefix(5))
    }

    /// "‹workspace› · ‹tab›", for agent rows and notifications.
    func place(_ pane: HostStore.Pane) -> String {
        let workspace = store.workspace(of: pane.tabID)
        let tab = workspace?.tabs.first { $0.id == pane.tabID }
        return [workspace?.label, tab.map(titleText)].compactMap(\.self).joined(separator: " · ")
    }

    /// The title in one string, for the window title and menus.
    func titleText(_ tab: HostStore.Tab) -> String {
        let title = title(tab)
        return [title.name, title.folder].plainTitle
    }
}

extension [String?] {
    /// A title's parts where it shows as plain text (⌘K, menus, window titles): with no dimmed part, a bar
    /// separates them ("Browser | Hacker News").
    var plainTitle: String {
        compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " | ")
    }
}
