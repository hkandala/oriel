#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// The one place to create or open a session (D68): a new name, the running and stopped sessions, and the ones
    /// already open in this window. Create, open and start take one path: start the server when it is not running,
    /// then open its page after the page in view. A glass panel like the palette: Enter acts, Esc or a click outside
    /// closes it.
    struct OpenSession: View {
        let pages: WindowPages
        @Binding var open: Bool
        /// herdr's session list, read once as the sheet opens.
        @State private var sessions: [Session] = []
        /// A name no session has, picked once.
        @State private var suggested = ""
        @State private var lit: String?
        @State private var starting: String?
        /// The last start that failed: its session and the notice.
        @State private var failure: (session: String, text: String)?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                FilterList(prompt: "Name a new session, or find one", name: "open-session", items: items,
                           maxHeight: 320, lit: $lit) {}
                if let failure {
                    NoticeCapsule(tone: .error, text: failure.text) {
                        Button("Retry") { start(failure.session) }.accessibilityIdentifier("notice.retry")
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
                let client: any Multiplexer = await HerdrClient(session: pages.current?.id ?? "default",
                                                                exec: exec.value)
                sessions = await (try? client.sessions()) ?? []
                suggested = sessions.newName
            }
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
                item("session", one.name, one.running ? "Running" : "Stopped", one.name) { start(one.name) }
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
                busy: starting == session,
            ) {
                if starting == nil {
                    act()
                }
            }
        }

        /// Starts the session when it is not running, then opens its page.
        private func start(_ session: String) {
            starting = session
            failure = nil
            Task {
                do {
                    try await HostStore.start(session)
                    pages.open(session)
                    open = false
                } catch {
                    // The panel stays open, with herdr's reason.
                    failure = (session, "Could not start \(session). \(error.localizedDescription)")
                }
                starting = nil
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
