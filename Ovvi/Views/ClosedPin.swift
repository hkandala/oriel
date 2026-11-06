import HerdrKit
import SwiftUI

/// A pinned session no pane runs (Pinned, on top of the Agents view, before the live pinned agents): Resume brings it
/// back; Unpin lets it go to Archived.
struct ClosedPin: View {
    let pin: AgentPin
    let page: Page

    var body: some View {
        let session = ClosedSession(agent: pin.agent ?? "", value: pin.key, title: pin.title, folder: pin.cwd ?? "",
                                    date: .now)
        let id = Self.id("agents.pinned", agent: session.agent, value: session.value)
        AgentRow(icon: session.agent, title: pin.title, line2: page.short(session.folder), id: id,
                 action: { page.resume(session) }, hover: { Self.buttons(session, page, id: id, pinned: true) },
                 trailing: { EmptyView() })
            .contextMenu {
                Button("Resume") { page.resume(session, beside: false) }
                Button("Resume to the Side") { page.resume(session, beside: true) }
                Divider()
                Button("Unpin") { Self.unpin(session, page) }
            }
    }

    /// Pin or Unpin, then Resume, under the pointer.
    @ViewBuilder
    static func buttons(_ session: ClosedSession, _ page: Page, id: String, pinned: Bool) -> some View {
        IconButton(symbol: pinned ? "pin.slash" : "pin", help: pinned ? "Unpin" : "Pin", size: 18) {
            pinned ? unpin(session, page) : pin(session, page)
        }
        .accessibilityIdentifier(id + ".pin")
        IconButton(symbol: "arrow.uturn.backward", help: "Resume", size: 18) { page.resume(session) }
            .accessibilityIdentifier(id + ".resume")
    }

    static func unpin(_ session: ClosedSession, _ page: Page) {
        let settings = AppSettings()
        settings.pins = [AgentPin](json: settings.pins).filter { pin in
            !(pin.machine == page.store.machine.id && pin.session == page.store.session && pin.key == session.value)
        }.json
    }

    /// The page's pins of sessions no pane of the machine runs, in pin order, that match the footer's filter.
    static func pins(_ page: Page, filter: String) -> [AgentPin] {
        let panes = page.store.agentPanes, live = page.liveSessions
        return [AgentPin](json: AppSettings().pins).filter { pin in
            pin.machine == page.store.machine.id && pin.session == page.store.session && pin.agent != nil
                && !live.contains(pin.key) && !panes.contains { $0.holds(pin) }
                && (pin.title.matches(filter) || (pin.cwd ?? "").matches(filter))
        }
    }

    static func pin(_ session: ClosedSession, _ page: Page) {
        let settings = AppSettings()
        settings.pins = ([AgentPin](json: settings.pins) + [AgentPin(
            machine: page.store.machine.id, session: page.store.session, key: session.value, agent: session.agent,
            title: session.title, cwd: session.folder,
        )]).json
    }

    /// A row's identifier: pi's file by its name.
    static func id(_ prefix: String, agent: String, value: String) -> String {
        "\(prefix).\(agent).\((value as NSString).lastPathComponent)"
    }
}

extension Page {
    /// ⌥: beside the keyboard card.
    func resume(_ session: ClosedSession) {
        resume(session, beside: NSEvent.modifierFlags.contains(.option))
    }

    /// A folder as line 2 shows it: the home folder as `~`.
    func short(_ folder: String) -> String {
        PathField.short(folder, remote: store.machine.isRemote)
    }

    /// The agents' sessions the panes of every open session of the machine run.
    var liveSessions: Set<String> {
        Set(HostStore.all.filter { $0.machine.id == store.machine.id }.flatMap(\.agentPanes).compactMap(\.session))
    }
}

extension Chooser {
    static func name(_ command: String) -> String {
        agents.first { $0.command == command }?.name ?? command
    }
}
