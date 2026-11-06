import HerdrKit
import SwiftUI

extension AgentState {
    /// For notifications, the Dock menu, a tab's announcement and VoiceOver.
    var word: String {
        switch self {
        case .needsYou: "needs you"
        case .working: "working"
        case .finishedUnseen: "finished"
        case .idle: "idle"
        }
    }

    /// Its word in a `StateLabel` and the Agents panel's group labels.
    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .finishedUnseen: "Done"
        case .idle: "Idle"
        }
    }

    /// Its `StateLabel`, none while idle.
    func label(_ look: Look) -> StateLabel? {
        self == .idle ? nil : StateLabel(text: title, icon: self, color: color(look))
    }

    /// Needs you or done and not seen: its row's name is medium; the others recede.
    var calls: Bool {
        self >= .finishedUnseen
    }

    func color(_ look: Look) -> Color {
        switch self {
        case .needsYou: look.needsYou
        case .working: look.working
        case .finishedUnseen: look.finished
        case .idle: .secondary
        }
    }
}

/// An agent pane in the Agents view and the Agents button's panel. A click selects its workspace and tab and gives
/// it the keyboard. Lit like the selected workspace row while it is the shown tab's keyboard card.
struct AgentButton: View {
    let pane: HostStore.Pane
    let page: Page
    /// In Settled: its age where the box goes.
    var age: Date?
    /// Pin or Unpin under the pointer (the Agents view's rows).
    var pinned = false
    var pin: (() -> Void)?
    var picked: () -> Void = {}

    var body: some View {
        let state = pane.state ?? .idle
        AgentRow(icon: pane.iconID, letter: pane.letter, title: title, line2: page.place(pane), medium: state.calls,
                 lit: lit, id: "agent.\(pane.id)", value: pane.state?.title ?? "", action: go, hover: { pinButton },
                 trailing: { trailing(state) })
    }

    private func go() {
        page.go(to: pane)
        picked()
    }

    private var title: String {
        pane.agentTitle ?? "agent"
    }

    @ViewBuilder private var pinButton: some View {
        if let pin {
            IconButton(symbol: pinned ? "pin.slash" : "pin", help: pinned ? "Unpin" : "Pin", size: 18, action: pin)
                .accessibilityIdentifier("agent.\(pane.id).pin")
        }
    }

    /// The state's box, none while idle; in Settled the age instead.
    @ViewBuilder private func trailing(_ state: AgentState) -> some View {
        if state != .idle {
            StateBox(state: state, since: state == .working ? pane.since : nil)
        } else if let age {
            AgeText(date: age)
        }
    }

    private var lit: Bool {
        page.keyboardCard(page.selectedTab?.id) === pane
    }
}

extension HostStore {
    /// The agent panes in herdr's order of workspaces, tabs and panes.
    var agentPanes: [Pane] {
        workspaces.flatMap(\.tabs).flatMap { panes(in: $0.id).filter { $0.state != nil } }
    }
}

/// The Dock badge over every open page (also `app.badge`, for tests), and the tab and pane the user looks at (D14).
struct AgentsWatch: ViewModifier {
    let pages: WindowPages
    let page: Page
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        // Each session once over every window. This window's list is read too, so a page it opens or closes counts.
        // ponytail: `HostStore.all` is not observed, so this window's `app.badge` may lag a store only another
        // window shows until one of this window's own changes; the Dock tile is right (the last writer counts all).
        let needsYou = pages.list.isEmpty ? 0 : HostStore.needsYou
        let card = page.keyboardCard(page.selectedTab?.id)
        let looked = [page.id, page.selectedTab?.id ?? "", card?.id ?? ""]
        content
            .testValue("app.badge", "Dock Badge", "\(needsYou)")
            .onChange(of: needsYou, initial: true) { HostStore.showBadge() }
            .onChange(of: looked + [appearsActive ? "key" : ""], initial: true) {
                pages.look(key: appearsActive)
                // The app in the background keeps the pane looked at.
                if appearsActive {
                    HostStore.look(card, in: page.store)
                }
            }
    }
}
