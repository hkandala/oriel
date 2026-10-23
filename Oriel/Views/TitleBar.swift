#if os(macOS)
    import HerdrKit
    import IOKit.ps
    import SwiftUI

    /// The title row (D45): sidebar toggle, machine button, workspace button while the sidebar is collapsed, the tab
    /// bar, then Agents, ⌘ and +.
    struct TitleBar: View {
        /// Rex's bar; `WindowReader` centers the traffic lights on it.
        static let height: CGFloat = 46

        /// Where the row starts: after the traffic lights (Rex's sidebar toggle is centered 82 pt right of the red
        /// light's center); full screen has none.
        static func inset(fullScreen: Bool) -> CGFloat {
            fullScreen ? gap : 91
        }

        let page: Page
        let fullScreen: Bool
        @Binding var sidebar: Bool
        /// While the sidebar is open, the tabs start where the cards do, at its width.
        let sidebarWidth: CGFloat
        /// The sidebar shows the Agents view.
        @Binding var agents: Bool
        @Binding var palette: Bool
        @Binding var workspaceMenu: Bool
        /// Where the workspace button starts in the window, for its menu.
        @Binding var workspaceButtonX: CGFloat
        /// A pane dragged over the `+`.
        @State private var plus = false
        @Environment(\.look) private var look

        var body: some View {
            HStack(spacing: gap) {
                HStack(spacing: gap) {
                    // ⌃⌘S is the menu's.
                    // Its sidebar part filled while open; no highlight: the icon says open or closed.
                    // `rectangle.leftthird.inset.filled` alone drew too thin a bar at 13 pt to tell the two apart.
                    IconButton(symbol: "sidebar.left", help: "Toggle Sidebar", key: .toggleSidebar) { sidebar.toggle() }
                        .overlay {
                            if sidebar {
                                Image(systemName: "rectangle.leftthird.inset.filled").font(.body.weight(.medium))
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityIdentifier("titlebar.sidebar")
                        .accessibilityValue(sidebar ? "open" : "closed")
                    MachineButton()
                }
                .frame(width: sidebar ? sidebarWidth - Self.inset(fullScreen: fullScreen) - gap : nil,
                       alignment: .leading)
                if !sidebar, let workspace = page.selectedWorkspace {
                    Capped(width: 260) {
                        WorkspaceButton(session: page.id, workspace: workspace.label, open: $workspaceMenu)
                    }
                    .layoutPriority(1)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                        workspaceButtonX = $0
                    }
                }
                if page.store.state == .live || page.store.reconnecting, let workspace = page.selectedWorkspace {
                    TabBar(workspace: workspace, page: page, plus: plus)
                } else {
                    Spacer(minLength: 0)
                }
                // ⌘. is the menu's.
                AgentsButton(page: page, showing: sidebar && agents) {
                    toggleAgents($agents, $sidebar)
                    // A click takes the keyboard from the card.
                    page.focusKeyboardCard()
                }
                // ⌘K is the menu's.
                IconButton(symbol: "command", help: "Command Palette", key: .palette) { palette.toggle() }
                    .accessibilityIdentifier("titlebar.palette")
                // ⌘T is the menu's.
                IconButton(symbol: "plus", help: "New Tab", key: .newTab) { Task { await page.newTab() } }
                    .disabled(page.selectedWorkspace == nil || page.store.writing)
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
            .padding(.leading, Self.inset(fullScreen: fullScreen))
            .padding(.trailing, gap)
            .frame(height: Self.height)
            .foregroundStyle(look.chrome)
            // The title bar is hidden, so the row's empty space moves the window.
            .background { Color.clear.contentShape(.rect).gesture(WindowDragGesture()) }
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
    /// you. Its hover lists them (no tooltip).
    private struct AgentsButton: View {
        let page: Page
        /// The Agents view is on.
        let showing: Bool
        let toggle: () -> Void
        @Environment(\.look) private var look

        var body: some View {
            let waiting = page.store.panes.count { $0.state == .needsYou }
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
            .hoverPanel(place: .underTrailing) { close in NeedsYouPanel(page: page, close: close) }
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

    /// The machine's icon; its menu lists the machines (This Mac only for now) and Add Remote Host.
    private struct MachineButton: View {
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Menu {
                // The current machine: picking it does nothing; ⌥-click opens it in a new window, as ⌘N.
                // ponytail: no machine id is stored until remote machines exist; then `WindowGroup(id:for:)` and
                // `openWindow(id:value:)` carry it. macOS 27 draws no images in these menus (an AppKit
                // NSMenuItem.image does not show either); the icons are here for systems that do.
                Toggle(isOn: Binding { true } set: { _ in
                    if NSEvent.modifierFlags.contains(.option) {
                        openWindow(id: "main")
                    }
                }) { Label("This Mac", systemImage: thisMacIcon) }
                Divider()
                // ponytail: no-op until remote hosts
                Button("Add Remote Host…", systemImage: "plus") {}
            } label: {
                // The icon alone (user, phase 22): no chevron.
                Image(systemName: thisMacIcon).fontWeight(.medium)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(ChromeStyle(radius: 7))
            .fixedSize()
            .help("Machine")
            .accessibilityLabel("Machine: This Mac")
            .accessibilityIdentifier("titlebar.machine")
        }
    }

    /// While the sidebar is collapsed: "‹session› | ‹workspace›"; a click opens the workspace menu.
    private struct WorkspaceButton: View {
        let session: String
        let workspace: String
        @Binding var open: Bool
        @Environment(\.look) private var look

        var body: some View {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder").fontWeight(.medium)
                    // A long session name stops at 110 pt, so a long workspace name fades instead of hiding it.
                    Capped(width: 110) { Text(session).lineLimit(1) }.layoutPriority(1)
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
            .accessibilityIdentifier("titlebar.workspace")
            .help("Workspace")
            .accessibilityLabel("Workspace")
            .accessibilityValue("\(session) | \(workspace)")
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
    /// its branch; a typed name that matches none to make in the page in view, New Workspace and Open Session.
    struct WorkspaceMenu: View {
        let pages: WindowPages
        let page: Page
        @Binding var open: Bool
        let openSession: () -> Void

        var body: some View {
            let rows = pages.list.flatMap { page in page.store.workspaces.map { (page, $0) } }
            FilterList(prompt: "Filter or create…", name: "workspaces", items: items,
                       start: rows.firstIndex { $0.0 === page && $0.1.id == page.selectedWorkspaceID } ?? 0,
                       maxHeight: 340) { open = false }
                .padding(8)
                .frame(width: 300)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }

        private func items(_ filter: String) -> [FilterList.Item] {
            let workspaces = pages.list.flatMap { page in
                page.store.workspaces.filter { $0.label.matches(filter) }.map { workspace in
                    // Another page's workspace shows that page.
                    FilterList.Item(id: "\(page.id).\(workspace.id)",
                                    state: page.store.strongest(workspace.tabs.map(\.id))?.state,
                                    title: workspace.label,
                                    detail: workspace.git?.branch ?? "", section: page.id, act: {
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
                FilterList.Item(id: "new", symbol: "plus", title: "New Workspace", section: "") {
                    Task { await page.newWorkspace() }
                },
                FilterList.Item(id: "open-session", symbol: "plus.square.on.square", title: "Open Session…",
                                detail: KeyboardShortcut.openSession.glyphs, section: "", act: openSession),
            ]
        }
    }
#endif
