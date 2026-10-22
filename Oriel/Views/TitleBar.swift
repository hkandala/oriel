#if os(macOS)
    import HerdrKit
    import IOKit.ps
    import SwiftUI

    /// The title row (D45): sidebar toggle, machine button, workspace button while the sidebar is collapsed, the tab
    /// bar, then Agents, ⌘ and +.
    struct TitleBar: View {
        /// The compact toolbar's height, so the row centers on the traffic lights.
        static let height: CGFloat = 40

        /// Where the row starts: after the traffic lights, which AppKit owns; full screen has none.
        static func inset(fullScreen: Bool) -> CGFloat {
            fullScreen ? gap : 78
        }

        let page: Page
        let fullScreen: Bool
        @Binding var sidebar: Bool
        /// The sidebar shows the Agents view.
        @Binding var agents: Bool
        @Binding var palette: Bool
        @Binding var workspaceMenu: Bool
        /// Where the workspace button starts in the window, for its menu.
        @Binding var workspaceButtonX: CGFloat

        var body: some View {
            HStack(spacing: 8) {
                // ⌃⌘S is the menu's.
                SidebarToggle(open: $sidebar)
                    .accessibilityIdentifier("titlebar.sidebar")
                    .accessibilityValue(sidebar ? "open" : "closed")
                MachineButton()
                if !sidebar, let workspace = page.selectedWorkspace {
                    Capped(width: 260) {
                        WorkspaceButton(session: page.id, workspace: workspace.label, open: $workspaceMenu)
                    }
                    .layoutPriority(1)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                        workspaceButtonX = $0
                    }
                }
                if page.store.state == .live, let workspace = page.selectedWorkspace {
                    TabBar(workspace: workspace, page: page)
                } else {
                    Spacer(minLength: 0)
                }
                // ⌘. is the menu's.
                AgentsButton(page: page, showing: sidebar && agents) { toggleAgents($agents, $sidebar) }
                // ⌘K is the menu's.
                IconButton(symbol: "command", help: "Commands") { palette.toggle() }
                    .accessibilityIdentifier("titlebar.palette")
                // ⌘T is the menu's.
                IconButton(symbol: "plus", help: "New Tab") { Task { await page.newTab() } }
                    .disabled(page.selectedWorkspace == nil || page.store.writing)
                    .accessibilityIdentifier("titlebar.new-tab")
            }
            .padding(.leading, Self.inset(fullScreen: fullScreen))
            .padding(.trailing, gap)
            .frame(height: Self.height)
            // The title bar is hidden, so the row's empty space moves the window. Behind the row, not a content shape
            // on it: that would cut off the Agents button's panel hanging below.
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

    /// Outline chat bubbles, the front one filled while the Agents view is on; an amber dot while an agent of the
    /// page in view needs you. Its hover lists them (no tooltip).
    private struct AgentsButton: View {
        let page: Page
        /// The Agents view is on.
        let showing: Bool
        let toggle: () -> Void
        @Environment(\.look) private var look

        var body: some View {
            let waiting = page.store.panes.count { $0.state == .needsYou }
            Button(action: toggle) {
                // Only the front bubble filled: `.fill` fills both, so its front layer alone (palette, back layer
                // clear) goes over the outline; the two symbols line up at their bottoms, not their centers.
                ZStack(alignment: .bottom) {
                    Image(systemName: "bubble.left.and.bubble.right")
                    if showing {
                        Image(systemName: "bubble.left.and.bubble.right.fill").symbolRenderingMode(.palette)
                            .foregroundStyle(HierarchicalShapeStyle.secondary, Color.clear)
                    }
                }
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
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
            .hoverPanel { close in NeedsYouPanel(page: page, close: close) }
        }
    }

    /// `sidebar.left`, with its sidebar part filled while open. No highlight: the icon says open or closed.
    /// `rectangle.leftthird.inset.filled` alone drew too thin a bar at 13 pt to tell the two apart.
    private struct SidebarToggle: View {
        @Binding var open: Bool

        var body: some View {
            Button { open.toggle() } label: {
                Image(systemName: "sidebar.left")
                    // Its bar sits on sidebar.left's sidebar part: both are the same window outline.
                    .overlay {
                        if open {
                            Image(systemName: "rectangle.leftthird.inset.filled")
                        }
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(ChromeStyle(radius: 7))
            .help("Toggle Sidebar")
            .accessibilityLabel("Toggle Sidebar")
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

    /// The machine's icon and a chevron; its menu lists the machines (This Mac only for now) and Add Remote Host.
    private struct MachineButton: View {
        var body: some View {
            Menu {
                // The current machine: picking it does nothing. macOS 27 draws no images in these menus (an AppKit
                // NSMenuItem.image does not show either); the icons are here for systems that do.
                Toggle(isOn: .constant(true)) { Label("This Mac", systemImage: thisMacIcon) }
                Divider()
                // ponytail: no-op until remote hosts
                Button("Add Remote Host…", systemImage: "plus") {}
            } label: {
                // One text, so the menu button is one element.
                let chevron = Text(Image(systemName: "chevron.down")).font(.system(size: 8, weight: .bold))
                Text("\(Image(systemName: thisMacIcon)) \(chevron)").fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 28)
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

        var body: some View {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder").fontWeight(.medium).foregroundStyle(.secondary)
                    // A long session name stops at 110 pt, so a long workspace name fades instead of hiding it.
                    Capped(width: 110) { Text(session).foregroundStyle(.secondary).lineLimit(1) }.layoutPriority(1)
                    Rectangle().fill(.separator).frame(width: 1, height: 12)
                    FadeText(text: Text(workspace))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .frame(height: 28)
            }
            .buttonStyle(ChromeStyle(selected: open, radius: 7))
            .accessibilityIdentifier("titlebar.workspace")
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
                                detail: "⇧⌘N", section: "", act: openSession),
            ]
        }
    }
#endif
