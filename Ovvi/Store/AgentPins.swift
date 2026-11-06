import Foundation
import HerdrKit

/// A pinned agent (Agents view), on top of its session's page in pin order. Kept by its agent's session when it has
/// one, so it stays pinned after its pane closes (Archived resumes it), else by its terminal.
struct AgentPin: Codable, Hashable {
    let machine: String
    /// The herdr session it runs in.
    let session: String
    /// `Pane.pinKey`.
    var key: String
    /// herdr's agent kind, with a session only: what a resume runs.
    var agent: String?
    var title: String
    /// Its folder, as herdr has it: where a resume runs.
    var cwd: String?

    /// The defaults key of the pins, a JSON list (`AppSettings.pins`).
    static let key = "agentPins"
}

/// An agent settled, or kept out of Settled, by hand until its next change of state: while its `since` is the same.
struct AgentSettle: Equatable {
    let since: Date?
    let settled: Bool
}

extension HostStore.Pane {
    /// What settles it (`HostStore.settles`): as `Seen` keys it.
    var settleKey: String {
        Seen.key(terminalID: terminalID, paneID: id)
    }

    /// What pins it: its agent's session, else its terminal.
    var pinKey: String? {
        session ?? terminalID.map { "terminal \($0)" }
    }

    /// Pinned by `pin`: the pin may predate its session (`pinKey` moved from the terminal to the session).
    func holds(_ pin: AgentPin) -> Bool {
        pin.key == pinKey || terminalID.map { "terminal \($0)" } == pin.key
    }

    /// Its pin as it is now, in `store`.
    func pin(in store: HostStore) -> AgentPin? {
        pinKey.map {
            AgentPin(machine: store.machine.id, session: store.session, key: $0, agent: session == nil ? nil : agent,
                     title: agentTitle ?? "Untitled", cwd: cwd)
        }
    }
}

extension HostStore {
    /// Keeps this session's pins as their panes are now, after each snapshot of every open session: the key moves to
    /// the session once the agent reports one, and the title and folder follow. Drops pins nothing can bring back:
    /// closed, with no session. Another session's pins and pins of closed sessions stay (Archived resumes them).
    func keepPins() {
        guard last != nil else { return }
        let text = UserDefaults.agents.string(forKey: AgentPin.key) ?? ""
        let agents = agentPanes
        let pins = [AgentPin](json: text).compactMap { pin -> AgentPin? in
            guard pin.machine == machine.id, pin.session == session else { return pin }
            // A pane whose agent herdr lost for a moment keeps its pin.
            let gone = pin.agent == nil && !panes.contains { $0.holds(pin) }
            return agents.first { $0.holds(pin) }?.pin(in: self) ?? (gone ? nil : pin)
        }
        if !text.isEmpty, pins.json != text {
            UserDefaults.agents.set(pins.json, forKey: AgentPin.key)
        }
    }
}

@MainActor
extension UserDefaults {
    /// The Agents view's own state: pins, open shelves and the agents' times, in `agents.plist` in the config folder,
    /// so a test's `-configFolder` keeps its writes out of the user's.
    static let agents = UserDefaults(suiteName: Registry.config.appending(path: "agents").path) ?? .standard
}

extension Array where Element: Codable {
    /// From the JSON text a setting keeps; empty when there is none or it does not decode.
    init(json: String) {
        self = (try? JSONDecoder().decode(Self.self, from: Data(json.utf8))) ?? []
    }

    var json: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
