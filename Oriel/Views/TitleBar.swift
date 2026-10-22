#if os(macOS)
    import IOKit.ps
    import SwiftUI

    /// The title row (D45): sidebar toggle, session picker (until phase 14), machine button, workspace button while
    /// the sidebar is collapsed, the tab bar, then ⌘ and +.
    struct TitleBar: View {
        /// The compact toolbar's height, so the row centers on the traffic lights.
        static let height: CGFloat = 40
        /// The session picker button starts this far into the row: the 28 pt sidebar toggle and the row's 8 pt spacing.
        static let picker: CGFloat = 36

        /// Where the row starts: after the traffic lights, which AppKit owns; full screen has none.
        static func inset(fullScreen: Bool) -> CGFloat {
            fullScreen ? gap : 78
        }

        let store: HostStore
        let fullScreen: Bool
        @Binding var sidebar: Bool
        @Binding var picking: Bool
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
                SessionPicker(store: store, open: $picking)
                MachineButton()
                if !sidebar, let workspace = store.selectedWorkspace {
                    Capped(width: 260) {
                        WorkspaceButton(session: store.session, workspace: workspace.label, open: $workspaceMenu)
                    }
                    .layoutPriority(1)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                        workspaceButtonX = $0
                    }
                }
                if store.state == .live, let workspace = store.selectedWorkspace {
                    TabBar(workspace: workspace, store: store)
                } else {
                    Spacer(minLength: 0)
                }
                // ⌘K is the menu's.
                IconButton(symbol: "command", help: "Commands") { palette.toggle() }
                    .accessibilityIdentifier("titlebar.palette")
                // ⌘T is the menu's.
                IconButton(symbol: "plus", help: "New Tab") { Task { await store.newTab() } }
                    .disabled(store.selectedWorkspace == nil || store.writing)
                    .accessibilityIdentifier("titlebar.new-tab")
            }
            .padding(.leading, Self.inset(fullScreen: fullScreen))
            .padding(.trailing, gap)
            .frame(height: Self.height)
            .contentShape(.rect)
            // The title bar is hidden, so the row's empty space moves the window.
            .gesture(WindowDragGesture())
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
                // The current machine: picking it does nothing.
                Toggle(isOn: .constant(true)) {
                    Image(systemName: thisMacIcon)
                    Text("This Mac")
                }
                Divider()
                // ponytail: no-op until remote hosts
                Button {} label: {
                    Image(systemName: "plus")
                    Text("Add Remote Host…")
                }
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

    /// The workspace button's menu: every workspace of the window's session under its header, a typed name that
    /// matches none to make, and New Workspace.
    struct WorkspaceMenu: View {
        let store: HostStore
        @Binding var open: Bool

        var body: some View {
            FilterList(prompt: "Filter or create…", name: "workspaces", items: items,
                       start: store.workspaces.firstIndex { $0.id == store.selectedWorkspaceID } ?? 0,
                       maxHeight: 340) { open = false }
                .padding(8)
                .frame(width: 300)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }

        private func items(_ filter: String) -> [FilterList.Item] {
            let workspaces = store.workspaces.filter { $0.label.matches(filter) }.map { workspace in
                // The state icon (phase 15) and the branch (phase 14) come later.
                FilterList.Item(id: workspace.id, title: workspace.label, section: store.session) {
                    store.selectedWorkspaceID = workspace.id
                }
            }
            let typed = filter.trimmingCharacters(in: .whitespaces)
            let create = typed.isEmpty || !workspaces.isEmpty ? [] : [
                FilterList.Item(id: "create", symbol: "plus", title: "New Workspace “\(typed)”") {
                    Task { await store.newWorkspace(label: typed) }
                },
            ]
            let new = FilterList.Item(id: "new", symbol: "plus", title: "New Workspace", section: "") {
                Task { await store.newWorkspace() }
            }
            return create + workspaces + [new]
        }
    }
#endif
