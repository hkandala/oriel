#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// The selected workspace's tabs in the title row (D42): equal widths on a track, one marker that follows the
    /// strip's scroll, dividers, hover and close. It takes the row's free space and scrolls when tabs would be narrower
    /// than 64 pt.
    struct TabBar: View {
        /// The track's height; Rex's capsules sit 2 pt inside it, 30 pt tall and fully round.
        static let height: CGFloat = 34
        static let inset: CGFloat = 2
        static let radius: CGFloat = 17

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
        @Environment(\.look) private var look

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
                                    Rectangle().fill(look.divider).frame(width: 1, height: Self.height - 16)
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
                    .clearsDrop(page) {
                        spring?.cancel() // a late update after the drop may have started one
                        over = nil
                        end = false
                    }
                    .background {
                        ZStack(alignment: .leading) {
                            Capsule().fill(look.track).opacity(tabs.count > 1 ? 1 : 0)
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
                    if !inside, page.closing == nil {
                        settle()
                    }
                }
                .onChange(of: page.closing == nil) { _, closed in
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
                            if end || plus, page.dragging != nil, content + 1 + width <= space {
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
            return Pill(shape: RoundedRectangle(cornerRadius: Self.radius - Self.inset, style: .continuous))
                .frame(width: width, height: Self.height - 2 * Self.inset)
                .offset(x: offset * (width + 1))
                .allowsHitTesting(false)
        }

        /// ⌘ alone held 0.7 s with the window key shows the keycaps; releasing it hides them. A key pressed first
        /// (⌘T) cancels.
        private func watch(_ event: NSEvent) -> NSEvent? {
            MainActor.assumeIsolated {
                pendingHints?.cancel()
                let command = event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
                // ponytail: any key window of the app, so ⌘ held in one window lights every window's keycaps;
                // compare event.window to this bar's window to stop that.
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
#endif
