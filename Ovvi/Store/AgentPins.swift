import Foundation

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
    var folder: String?
}

/// An agent settled, or kept out of Settled, by hand until its next change of state (its `state_change_seq`).
struct AgentSettle: Codable, Hashable {
    let machine: String
    let session: String
    let key: String
    let seq: Int?
    let settled: Bool
}

extension HostStore.Pane {
    /// What pins and settles it: its agent's session, else its terminal.
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
                     title: agentTitle ?? "Untitled", folder: folder)
        }
    }
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
