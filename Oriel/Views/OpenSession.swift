#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// The one place to create or open a session (D68): a new name, the running and stopped sessions, and the ones
    /// already open in this window. Create, open and start take one path: start the server when it is not running,
    /// then open its page last. The lit running session has Stop, the lit stopped one Delete (both red, and ask first),
    /// the lit open one Detach. A glass panel like the palette: Enter acts, Esc or a click outside closes it.
    struct OpenSession: View {
        let pages: WindowPages
        @Binding var open: Bool
        /// A name no session has, picked once.
        @State private var suggested: String
        /// The session a start, stop or delete runs on.
        @State private var busy: String?
        /// The last start, stop or delete that failed: the notice, and the same again.
        @State private var failure: (text: String, retry: () -> Void)?
        /// The Stop or Delete waiting for the user's yes: `stop`, else `delete`, and its session.
        @State private var asking: (verb: String, session: String)?

        init(pages: WindowPages, open: Binding<Bool>) {
            self.pages = pages
            _open = open
            _suggested = State(initialValue: (pages.current?.store.sessions ?? []).newName)
        }

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
            .floatingGlass(in: .rect(cornerRadius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Open Session")
            // e2e: what the first draw lists.
            .onAppear { Latency.shared.note("open-session \(sessions.map(\.name).joined(separator: ","))") }
            .task {
                await list()
                if sessions.contains(where: { $0.name == suggested }) {
                    suggested = sessions.newName
                }
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
                        let client = await HerdrClient(session: asked.session, exec: pages.machine.exec())
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

        /// herdr's session list as the page last read it (as it connected): shown at once, then read again as the
        /// panel opens, its rows changing in place. An empty list first drew only the open pages, then the sessions
        /// pushed in above them (user, phase 29).
        private var sessions: [Session] {
            pages.current?.store.sessions ?? []
        }

        private func list() async {
            await pages.current?.store.loadSessions()
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
                row.buttonRole = .destructive
                row.button = (verb.capitalized, {
                    if busy == nil {
                        asking = (verb, one.name)
                    }
                })
                return row
            }
            return create + others.filter(\.running).map(session) + others.filter { !$0.running }.map(session)
                + pages.list.filter { $0.id.matches(filter) }.map { page in
                    var row = item("open", page.id, "Open in this window", page.id) {
                        pages.show(page)
                        open = false
                    }
                    // The session keeps running; never the window's last page.
                    if pages.list.count > 1 {
                        row.button = ("Detach", { pages.close(page) })
                    }
                    return row
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
            let machine = pages.machine
            run(session, "start") {
                try await HostStore.start(session, on: machine)
                // Not on a machine the window switched to meanwhile.
                if pages.machine == machine {
                    pages.open(session)
                }
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
