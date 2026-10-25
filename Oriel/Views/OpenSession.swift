#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// The one place to create or open a session (D68): a new name, the running and stopped sessions, and the ones
    /// already open in this window. Create, open and start take one path: start the server when it is not running,
    /// then open its page last. The lit running session has Stop, the lit stopped one Delete; both ask first. A glass
    /// panel like the palette: Enter acts, Esc or a click outside closes it.
    struct OpenSession: View {
        let pages: WindowPages
        @Binding var open: Bool
        /// herdr's session list, read once as the sheet opens.
        @State private var sessions: [Session] = []
        /// A name no session has, picked once.
        @State private var suggested = ""
        /// The session a start, stop or delete runs on.
        @State private var busy: String?
        /// The last start, stop or delete that failed: the notice, and the same again.
        @State private var failure: (text: String, retry: () -> Void)?
        /// The Stop or Delete waiting for the user's yes: `stop`, else `delete`, and its session.
        @State private var asking: (verb: String, session: String)?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                FilterList(prompt: "Name a new session, or find one", name: "open-session", items: items,
                           maxHeight: 320) {}
                if let failure {
                    NoticeCapsule(tone: .error, text: failure.text) {
                        Button("Retry", action: failure.retry).accessibilityIdentifier("notice.retry")
                    }
                    .accessibilityIdentifier("open-session.notice")
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(8)
            .frame(width: 420)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Open Session")
            .task {
                await list()
                suggested = sessions.newName
            }
            // Both end what runs for good, on every device (D41's reason to ask).
            .confirmationDialog(
                "\(asking?.verb.capitalized ?? "") the session “\(asking?.session ?? "")”?",
                isPresented: Binding { asking != nil } set: {
                    if !$0 {
                        asking = nil
                    }
                },
                presenting: asking,
            ) { asked in
                Button("\(asked.verb.capitalized) Session", role: .destructive) {
                    run(asked.session, asked.verb) {
                        let client = await HerdrClient(session: asked.session, exec: exec.value)
                        if asked.verb == "stop" {
                            try await client.stopSession()
                        } else {
                            try await client.deleteSession()
                        }
                        await list()
                    }
                }
            } message: { asked in
                Text(asked.verb == "stop"
                    ? "Every program in it will end, here and in every herdr client. Its workspaces and tabs stay "
                    + "for its next start."
                    : "Its workspaces, tabs and panes go for good. This cannot be undone.")
            }
        }

        private func list() async {
            let client: any Multiplexer = await HerdrClient(session: pages.current?.id ?? "default", exec: exec.value)
            sessions = await (try? client.sessions()) ?? sessions
        }

        /// New, then Running and Stopped sessions not open in this window, then the ones open in it.
        private func items(_ filter: String) -> [FilterList.Item] {
            let shown = pages.list.map(\.id)
            let typed = filter.trimmingCharacters(in: .whitespaces)
            let new = typed.isEmpty ? suggested : typed
            let create = Session.isValidName(new) && !sessions.contains { $0.name == new } && !shown.contains(new)
                ? [item("new", "Create session “\(new)”", "New", new) { start(new) }] : []
            let others = sessions.filter { !shown.contains($0.name) && $0.name.matches(filter) }
            let session = { (one: Session) in
                var row = item("session", one.name, one.running ? "Running" : "Stopped", one.name) { start(one.name) }
                let verb = one.running ? "stop" : "delete"
                row.button = (verb.capitalized, {
                    if busy == nil {
                        asking = (verb, one.name)
                    }
                })
                return row
            }
            return create + others.filter(\.running).map(session) + others.filter { !$0.running }.map(session)
                + shown.filter { $0.matches(filter) }.map { name in
                    item("open", name, "Open in this window", name) {
                        if let page = pages.list.first(where: { $0.id == name }) {
                            pages.show(page)
                        }
                        open = false
                    }
                }
        }

        /// A row of a kind (`new`, `session` or `open`: its id's prefix and its symbol). The group headers say what a
        /// row does; no hint text on the rows.
        private func item(_ kind: String, _ title: String, _ section: String, _ session: String,
                          act: @escaping () -> Void) -> FilterList.Item
        {
            FilterList.Item(
                id: "\(kind).\(session)",
                symbol: ["new": "plus", "open": "checkmark"][kind] ?? "rectangle.stack",
                title: title,
                section: section,
                busy: busy == session,
            ) {
                if busy == nil {
                    act()
                }
            }
        }

        /// Starts the session when it is not running, then opens its page.
        private func start(_ session: String) {
            run(session, "start") {
                try await HostStore.start(session)
                pages.open(session)
                open = false
            }
        }

        /// A start, stop or delete of the session (`verb` for the notice). On a failure the panel stays open, with
        /// herdr's reason and Retry.
        private func run(_ session: String, _ verb: String, _ work: @escaping () async throws -> Void) {
            guard busy == nil else { return }
            busy = session
            failure = nil
            Task {
                do {
                    try await work()
                } catch {
                    failure = ("Could not \(verb) \(session). \(error.localizedDescription)", {
                        run(session, verb, work)
                    })
                }
                busy = nil
            }
        }
    }

    extension [Session] {
        /// A readable name no session has yet, like the references' `lunar-ridge`.
        var newName: String {
            let first = ["amber", "brisk", "calm", "early", "lunar", "misty", "quiet", "sunny"]
            let second = ["cedar", "dune", "grove", "harbor", "meadow", "peak", "ridge", "river"]
            let names = first.flatMap { word in second.map { "\(word)-\($0)" } }
            return names.shuffled().first { name in !contains { $0.name == name } } ?? "session-\(count + 1)"
        }
    }
#endif
