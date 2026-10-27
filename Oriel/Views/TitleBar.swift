import HerdrKit
import IOKit.ps
import SwiftUI

/// The title row (D45): sidebar toggle, machine button, workspace button while the sidebar is collapsed, the tab
/// bar, then Agents, the overview, ⌘ and +; in the overview only its ×.
struct TitleBar: View {
    /// Rex's bar; `WindowReader` centers the traffic lights on it.
    static let height: CGFloat = 46

    /// Where the row starts: after the traffic lights (Rex's sidebar toggle is centered 82 pt right of the red
    /// light's center); full screen has none.
    static func inset(fullScreen: Bool) -> CGFloat {
        fullScreen ? gap : 91
    }

    let pages: WindowPages
    let page: Page
    let fullScreen: Bool
    @Binding var sidebar: Bool
    /// While the sidebar is open, the tabs start where the cards do, at its width.
    let sidebarWidth: CGFloat
    /// The sidebar shows the Agents view.
    @Binding var agents: Bool
    @Binding var palette: Bool
    @Binding var workspaceMenu: Bool
    @Binding var openSession: Bool
    /// Where the workspace button starts in the window, for its menu.
    @Binding var workspaceButtonX: CGFloat
    /// A pane dragged over the `+`.
    @State private var plus = false
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: gap) {
            row
        }
        .underOverview(pages)
        .overlay(alignment: .trailing) {
            // The overview (D70): the traffic lights and one × that leaves it.
            if pages.overview {
                // ⌃⌘O is the menu's.
                IconButton(symbol: "xmark", help: "Close Overview", key: .overview) { pages.toggleOverview() }
                    .accessibilityIdentifier("overview.close")
                    .underOverview(pages, own: true)
            }
        }
        .padding(.leading, Self.inset(fullScreen: fullScreen))
        .padding(.trailing, gap)
        .frame(height: Self.height)
        .foregroundStyle(look.chrome)
        // The title bar is hidden, so the row's empty space moves the window.
        .background { Color.clear.contentShape(.rect).gesture(WindowDragGesture()) }
    }

    @ViewBuilder private var row: some View {
        HStack(spacing: gap) {
            // ⌃⌘S is the menu's.
            // Its sidebar part filled while open; no highlight: the icon says open or closed.
            // `rectangle.leftthird.inset.filled` alone drew too thin a bar at 13 pt to tell the two apart.
            IconButton(symbol: "sidebar.left", help: "Toggle Sidebar", key: .toggleSidebar) { sidebar.toggle() }
                .overlay {
                    if sidebar {
                        Image(systemName: "rectangle.leftthird.inset.filled").font(.body.weight(.medium))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("titlebar.sidebar")
                .accessibilityValue(sidebar ? "open" : "closed")
            MachineButton(pages: pages, openSession: $openSession)
        }
        .frame(width: sidebar ? sidebarWidth - Self.inset(fullScreen: fullScreen) - gap : nil,
               alignment: .leading)
        if !sidebar, let workspace = page.selectedWorkspace {
            Capped(width: 260) {
                WorkspaceButton(page: page, workspace: workspace.label, open: $workspaceMenu)
            }
            .layoutPriority(1)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                workspaceButtonX = $0
            }
        }
        if page.store.state == .live || page.store.reconnecting,
           let workspace = page.selectedWorkspace
        {
            TabBar(workspace: workspace, page: page, plus: plus, overview: pages.overview)
                // Made anew per session: herdr's ids repeat across sessions ("w1:t1"), so a tab's announcement or
                // rename, and the row's scroll, carried over to the other session's tab.
                .id(page.id)
        } else {
            Spacer(minLength: 0)
        }
        // ⌘. is the menu's.
        AgentsButton(page: page, showing: sidebar && agents) {
            toggleAgents($agents, $sidebar)
            // A click takes the keyboard from the card.
            page.focusKeyboardCard()
        }
        // ⌃⌘O is the menu's.
        IconButton(symbol: "square.grid.2x2", help: "Show Overview", key: .overview) { pages.toggleOverview() }
            .accessibilityIdentifier("titlebar.overview")
        // ⌘K is the menu's.
        IconButton(symbol: "command", help: "Command Palette", key: .palette) { palette.toggle() }
            .accessibilityIdentifier("titlebar.palette")
        // ⌘T is the menu's.
        IconButton(symbol: "plus", help: "New Tab", key: .newTab) { Task { await page.newTab() } }
            .disabled(page.selectedWorkspace == nil)
            .accessibilityIdentifier("titlebar.new-tab")
            // Highlighted too: a full track has no room for the ghost capsule.
            .overlay {
                if plus, page.dragging != nil {
                    DropIndicator(radius: 7)
                }
            }
            .onDrop(of: page.selectedWorkspaceID == nil ? [] : [.orielDrag], delegate: PaneDrop(
                page: page, target: .move(.newTab(workspaceID: page.selectedWorkspaceID ?? "")), over: $plus,
            ))
            .clearsDrop(page) { plus = false }
    }
}

/// The Agents button and ⌘.: the Agents view on (opening a collapsed sidebar), or back to the Workspaces view.
func toggleAgents(_ agents: Binding<Bool>, _ sidebar: Binding<Bool>) {
    if agents.wrappedValue, sidebar.wrappedValue {
        agents.wrappedValue = false
    } else {
        agents.wrappedValue = true
        sidebar.wrappedValue = true
    }
}

/// A list of statuses, filled while the Agents view is on; an amber dot while an agent of the page in view needs
/// you. Its hover lists them and the unseen finishes (no tooltip).
private struct AgentsButton: View {
    let page: Page
    /// The Agents view is on.
    let showing: Bool
    let toggle: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        let waiting = page.store.waiting
        Button(action: toggle) {
            Image(systemName: showing ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                .fontWeight(.medium)
                .overlay(alignment: .topTrailing) {
                    if waiting > 0 {
                        Circle().fill(look.needsYou).frame(width: 7, height: 7).offset(x: 3, y: -2)
                    }
                }
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ChromeStyle(radius: 7))
        .accessibilityLabel("Agents")
        .accessibilityIdentifier("titlebar.agents")
        .accessibilityValue("\(waiting) need you")
        .hoverPanel(place: .underTrailing, enabled: waiting > 0 || page.store.done > 0) { close in
            AgentsPanel(page: page, close: close)
        }
    }
}

/// The Agents button's panel: the page's agents that need you, then those whose finish is not seen yet, under the
/// Agents view's group labels. A click on a done row shows its tab, which clears it.
private struct AgentsPanel: View {
    let page: Page
    let close: () -> Void

    var body: some View {
        let agents = page.store.agentPanes
        VStack(alignment: .leading, spacing: 2) {
            Text("Agents · \(page.store.title)").font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .accessibilityIdentifier("agents.popover.header")
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([AgentState.needsYou, .finishedUnseen], id: \.self) { state in
                        let group = agents.filter { $0.state == state }
                        if !group.isEmpty {
                            // The Agents view's group label, without its fold.
                            Text("\(state.capsule) \(group.count)")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                .accessibilityIdentifier("agents.popover.group.\(state.capsule)")
                                .padding(.horizontal, 8).padding(.top, 8)
                            ForEach(group) { AgentButton(pane: $0, page: page, picked: close) }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 440)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(width: 320, alignment: .leading)
        .floatingGlass(in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agents.popover")
    }
}

/// This Mac's icon: a laptop when it has an internal battery (`hw.model` no longer says MacBook on M2 and later
/// laptops).
let thisMacIcon: String = {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return "desktopcomputer" }
    let battery = sources.contains { source in
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
    }
    return battery ? "laptopcomputer" : "desktopcomputer"
}()

/// The machine's icon and its menu.
private struct MachineButton: View {
    let pages: WindowPages
    @Binding var openSession: Bool

    var body: some View {
        let current = pages.machine
        Menu {
            // Another machine shows in its own window: the one used last comes forward, else a new one opens; this
            // one and its sessions stay. Picking the current machine does nothing.
            // macOS 27 draws no images in these menus (an AppKit NSMenuItem.image does not show either); the icons
            // are here for systems that do.
            ForEach([Machine.thisMac] + MachineList.shared.list) { machine in
                Toggle(isOn: Binding { machine == current } set: { _ in
                    guard machine != current else { return }
                    if let window = WindowPages.windows.first(where: { $0.machine == machine }) {
                        window.window?.makeKeyAndOrderFront(nil)
                    } else {
                        WindowPages.open(machine: machine)
                    }
                }) { Label(machine.name, systemImage: machine.icon) }
            }
            Divider()
            // The machine's other sessions, also from here (not found in a remote window).
            Button("Open Session…", systemImage: "plus.square.on.square") { openSession = true }
            Divider()
            Button("Add Remote Host…", systemImage: "plus") {
                pages.hostDialog = Machine(id: UUID().uuidString, name: "", target: "", icon: "server.rack")
            }
            if !MachineList.shared.list.isEmpty {
                Menu("Edit Remote Host", systemImage: "pencil") {
                    ForEach(MachineList.shared.list) { machine in
                        Button(machine.name) { pages.hostDialog = machine }
                    }
                }
            }
        } label: {
            // The icon alone: no chevron.
            Image(systemName: current.icon).fontWeight(.medium)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeStyle(radius: 7))
        .fixedSize()
        .help("Machine")
        .accessibilityLabel("Machine: \(current.name)")
        .accessibilityValue(current.icon)
        .accessibilityIdentifier("titlebar.machine")
    }
}

/// While the sidebar is collapsed: "‹session› | ‹workspace›"; a click opens the workspace menu, and so does a pane
/// or a tab held over it, whose rows then take the drop.
private struct WorkspaceButton: View {
    let page: Page
    let workspace: String
    @Binding var open: Bool
    @State private var over = false
    @State private var spring: Task<Void, Never>?
    @Environment(\.look) private var look

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").fontWeight(.medium)
                // A long session name stops at 110 pt, so a long workspace name fades instead of hiding it.
                Capped(width: 110) { Text(page.store.title).lineLimit(1) }.layoutPriority(1)
                Rectangle().fill(look.divider).frame(width: 1, height: 12)
                FadeText(text: Text(workspace)).foregroundStyle(look.selected)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            // Rex's session picker label.
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
        .buttonStyle(ChromeStyle(selected: open, radius: 7))
        .overlay {
            if over, page.dragging != nil {
                DropIndicator(radius: 7)
            }
        }
        .onDrop(of: [.orielDrag], delegate: SpringDrop(page: page, over: $over, spring: $spring) { open = true })
        .clearsDrop(page) {
            spring?.cancel()
            over = false
        }
        .onDisappear { spring?.cancel() }
        .accessibilityIdentifier("titlebar.workspace")
        .help("Workspace")
        .accessibilityLabel("Workspace")
        .accessibilityValue("\(page.store.title) | \(workspace)")
    }
}

/// Offers its view at most `width` and takes the view's own size, so short content hugs (a `frame(maxWidth:)` takes
/// the whole offer).
private struct Capped: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let offer = ProposedViewSize(width: min(proposal.width ?? width, width), height: proposal.height)
        return subviews.first?.sizeThatFits(offer) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// The workspace button's menu: every workspace of every page of the window under its session's header, with
/// its branch; a typed name that matches none to make in the page in view; New Workspace and Open Session under the
/// scrolled rows. With the sidebar collapsed it is there, hidden, through every drag of the page in view, until a
/// hold over the button opens it: macOS 27 finds no drop target added after the drag entered the window (the rows
/// in view take drops).
struct WorkspaceMenu: View {
    let pages: WindowPages
    let page: Page
    @Binding var open: Bool
    let openSession: () -> Void

    var body: some View {
        let rows = pages.list.flatMap { page in page.store.workspaces.map { (page, $0) } }
        FilterList(prompt: "Filter or create…", name: "workspaces", items: items,
                   start: rows.firstIndex { $0.0 === page && $0.1.id == page.selectedWorkspaceID } ?? 0,
                   maxHeight: 340, pinned: 2, autofocus: page.dragging == nil) { open = false }
            .padding(8)
            .frame(width: 300)
            .floatingGlass(in: .rect(cornerRadius: 12))
            // It closes with the drag.
            .clearsDrop(page) { open = false }
    }

    private func items(_ filter: String) -> [FilterList.Item] {
        let workspaces = pages.list.flatMap { page in
            page.store.workspaces.filter { $0.label.matches(filter) }.map { workspace in
                // Another page's workspace shows that page.
                FilterList.Item(id: "\(page.id).\(workspace.id)",
                                state: workspace.state,
                                title: workspace.label,
                                detail: workspace.git?.branch ?? "", section: page.id,
                                // The page in view's drag: a pane or a tab goes there.
                                drop: page === self.page ? MenuRowDrop.Target(
                                    page: page, destination: .newTab(workspaceID: workspace.id), shown: open,
                                ) : nil, act: {
                                    pages.show(page)
                                    page.select(workspace)
                                })
            }
        }
        let typed = filter.trimmingCharacters(in: .whitespaces)
        let create = typed.isEmpty || !workspaces.isEmpty ? [] : [
            FilterList.Item(id: "create", symbol: "plus", title: "New Workspace “\(typed)”") {
                Task { await page.newWorkspace(label: typed) }
            },
        ]
        return create + workspaces + [
            FilterList.Item(id: "new", symbol: "plus", title: "New Workspace", section: "",
                            drop: MenuRowDrop.Target(page: page, destination: .newWorkspace(), shown: open),
                            act: { Task { await page.newWorkspace() } }),
            FilterList.Item(id: "open-session", symbol: "plus.square.on.square", title: "Open Session…",
                            detail: KeyboardShortcut.openSession.glyphs, section: "", act: openSession),
        ]
    }
}
