import AppKit
import HerdrKit
import SwiftUI

/// Every tab of the session in view as miniatures of their pages (D70), its workspaces scrolled vertically. A click
/// on a tile, Esc or the toggle shows the selected tab's page at once.
struct Overview: View {
    let pages: WindowPages
    /// Where the tab's page starts when the overview closes: the sidebar's width, or 0.
    let leading: CGFloat
    @State private var monitor: Any?

    var body: some View {
        GeometryReader { proxy in
            // Wide margins round the grid, as in the user's reference.
            let side = max(48, proxy.size.width * 0.08)
            if let page = pages.current {
                OverviewPage(
                    pages: pages,
                    page: page,
                    // The tab's page, as `TabPage` lays it out beside the sidebar.
                    size: CGSize(width: max(proxy.size.width - leading - 2 * gap, 1),
                                 height: max(proxy.size.height - 4 - gap, 1)),
                    side: side,
                    columns: min(4, max(2, Int((proxy.size.width - 2 * side + 16) / 356))),
                ) { workspace, tab in
                    page.select(workspace, tab: tab.id)
                    pages.closeOverview()
                }
                .equatable()
                // A view of its own per session: tab ids repeat across sessions, and its tiles report what is in view.
                .id(page.id)
            }
        }
        // e2e: the live cards and the snapshots kept (`-recordMotion YES`).
        .testValue("overview.snapshots", "Overview Snapshots",
                   "\(pages.overviewLive.count) \(PaneTerminal.snapshots.count)", shown: SettlingHost.record)
        // The keyboard leaves the terminals, which take none while in a miniature (`PaneSurfaceView`). Esc by a
        // monitor: a SwiftUI focus did not take the keyboard from a terminal moving into a miniature (CI).
        .onAppear {
            pages.window?.makeFirstResponder(nil)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                let leave = MainActor.assumeIsolated {
                    // Not a panel's (the palette's, the shortcuts').
                    guard let window = pages.window, NSApp.keyWindow === window, !pages.panelOpen,
                          !(window.firstResponder is NSText) else { return false }
                    pages.closeOverview()
                    return true
                }
                return leave ? nil : event
            }
        }
        .onDisappear {
            monitor.map(NSEvent.removeMonitor)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview")
    }
}

extension View {
    /// The window's chrome (the sidebar, the title row) under the overview: laid out while it is open, hidden, so it
    /// shows at once when it closes (made then, it came a moment late in a big session). `own`: the overview's ×,
    /// the other way round.
    func underOverview(_ pages: WindowPages, own: Bool = false) -> some View {
        let shown = pages.overview == own
        return opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            // Not `accessibilityHidden(false)`, which overrides the hidden ones inside (a button's overlay image
            // took its identifier too).
            .accessibilityElement(children: shown ? .contain : .ignore)
            // Out of the key view loop too: Tab would reach a hidden field.
            .disabled(!shown)
    }
}

extension WindowPages {
    /// Opens the overview, or closes it.
    func toggleOverview() {
        if overview {
            closeOverview()
        } else {
            overview = true
            // The cards in view: their pictures now, for their tiles (D70).
            terminals.takePictures(of: current?.shownTerminals.keys.map(\.self) ?? [])
            showTerminals()
        }
    }

    /// The tab's page shows again, and the keyboard goes back to the tab's card.
    func closeOverview() {
        guard overview else { return }
        overview = false
        overviewTabs = [:]
        overviewScrolling = false
        overviewSettling?.cancel()
        showTerminals()
        current?.focusKeyboardCard()
    }
}

extension WindowPages {
    /// The cards of the overview's tiles in view, whole tabs, the latest in first, up to a cap: each live card
    /// keeps a swap chain at its card's size, so a live tab costs about its page's pixels three times over (69 MB
    /// for a full window on Retina): at most 400 MB of tabs (16 tabs took 1.5 GB), and 16 cards
    /// (streams). A remote machine's cards share the relay's one SSH session: 6. The other tiles show their
    /// snapshot.
    func overviewCards(_ page: Page) -> [String: String] {
        let tabs = (overviewTabs[page.id] ?? []).reversed().map { tileCards(page, $0) }
        // Only those with a card that has no picture yet (a loader shows there), so each tile in view gets one in turn;
        // one that drew lets go and keeps its snapshot (D70: the tiles show pictures).
        let drawn = { (tab: [(String, String)]) in self.pictured(page, tab) }
        let size = window.map { $0.contentLayoutRect.size.applying(.init(scaleX: $0.backingScaleFactor,
                                                                         y: $0.backingScaleFactor)) }
        let most = size.map { Int(400e6 / max($0.width * $0.height * 12, 1)) } ?? 16
        var cards: [String: String] = [:], taken = 0
        for tabCards in tabs.filter({ !drawn($0) }) {
            // A tab over the caps alone still loads.
            guard cards.isEmpty || cards.count + tabCards.count <= (machine.isRemote ? 6 : 16) && taken < most
            else { continue }
            cards.merge(tabCards) { first, _ in first }
            taken += 1
        }
        return cards
    }

    /// The cards that stream for the overview: chosen again when it settles (`overviewCards`), kept on a herdr
    /// snapshot (4 a second while agents work) but for closed panes: choosing there made and freed surfaces in the
    /// middle of a scroll.
    func overviewStreams(_ page: Page, snapshot: Bool) -> [String: String] {
        guard snapshot else { return overviewCards(page) }
        let kept = page.store.panes.compactMap { pane in
            pane.terminalID.flatMap { overviewLive.contains($0) ? ($0, pane.id) : nil }
        }
        return Dictionary(kept) { first, _ in first }
    }

    /// A tab's terminals in its tile (terminal id, pane id), as its miniature draws them: its zoomed card alone, no
    /// floated one, no browser, plugin or chat (their own view).
    func tileCards(_ page: Page, _ tab: String) -> [(String, String)] {
        let panes = (page.store.tabPanes[tab] ?? []).filter { !page.floats($0) }
        let zoomed = panes.filter { $0.id == page.zoomedPaneID }
        return (zoomed.isEmpty ? panes : zoomed).compactMap { pane in
            (pane.plugin == nil || pane.placeholder) && page.shownChat(pane) == nil ? pane.terminalID
                .map { ($0, pane.id) } : nil
        }
    }

    /// Each of these cards has a picture for its tile.
    func pictured(_ page: Page, _ cards: [(String, String)]) -> Bool {
        cards.allSatisfy { id, _ in page.terminals.terminals([id]).first?.pictured == true }
    }

    /// The tiles in view turn live 150 ms after the last change: while tiles keep coming (a scroll), none does (a
    /// new surface and stream each, on the main thread); they show their snapshots meanwhile. A tile scrolled away
    /// lets go then too, and one that drew while another waits (`overviewCards`).
    func settleOverview() {
        guard overview else { return }
        overviewSettling?.cancel()
        // Not while the grid scrolls: its end settles (a surface made or freed mid-scroll dropped frames).
        guard !overviewScrolling else { return }
        overviewSettling = Task {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled, !overviewScrolling {
                showTerminals()
            }
        }
    }
}
