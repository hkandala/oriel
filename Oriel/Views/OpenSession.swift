#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// The one place to create or open a session (D68): a new name, the running and stopped sessions, and the ones
    /// already open in this window. Create, open and start take one path: start the server when it is not running,
    /// then open its page after the page in view.
    struct OpenSession: View {
        let pages: WindowPages
        @Environment(\.dismiss) private var dismiss
        /// herdr's session list, read once as the sheet opens.
        @State private var sessions: [Session] = []
        /// A name no session has, picked once.
        @State private var suggested = ""
        @State private var lit: String?
        /// The session whose server is starting.
        @State private var starting: String?
        @State private var failure: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Open Session").font(.headline)
                FilterList(prompt: "Name a new session, or find one", name: "open-session", items: items,
                           maxHeight: 320, lit: $lit) {}
                if let failure {
                    Text(failure).foregroundStyle(.secondary).accessibilityIdentifier("open-session.notice")
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Open") { lit.map(act) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(lit == nil || starting != nil)
                        .accessibilityIdentifier("open-session.open")
                }
            }
            .padding(16)
            .frame(width: 420)
            .task {
                let client: any Multiplexer = await HerdrClient(session: pages.current?.id ?? "default",
                                                                exec: exec.value)
                sessions = await (try? client.sessions()) ?? []
                suggested = sessions.newName
            }
        }

        /// New, then Running and Stopped sessions not open in this window, then the ones open in it.
        private func items(_ filter: String) -> [FilterList.Item] {
            let open = pages.list.map(\.id)
            let typed = filter.trimmingCharacters(in: .whitespaces)
            let new = typed.isEmpty ? suggested : typed
            let create = Session.isValidName(new) && !sessions.contains { $0.name == new } && !open.contains(new)
                ? [item("new.\(new)", "Create session “\(new)”", "New", new)] : []
            let others = sessions.filter { !open.contains($0.name) && $0.name.matches(filter) }
            return create
                + others.filter(\.running).map { item("session.\($0.name)", $0.name, "Running", $0.name) }
                + others.filter { !$0.running }
                .map { item("session.\($0.name)", $0.name, "Stopped", $0.name) }
                + open.filter { $0.matches(filter) }.map { item("open.\($0)", $0, "Open in this window", $0) }
        }

        /// The group headers say what a row does; no hint text on the rows.
        private func item(_ id: String, _ title: String, _ section: String, _ session: String) -> FilterList.Item {
            FilterList.Item(id: id, title: title, section: section, busy: starting == session) {
                act(id)
            }
        }

        /// A row's action by its id (`new.`, `session.` or `open.` and the session's name), for Enter and Open.
        private func act(_ id: String) {
            guard starting == nil, let dot = id.firstIndex(of: ".") else { return }
            let session = String(id[id.index(after: dot)...])
            if id.hasPrefix("open."), let page = pages.list.first(where: { $0.id == session }) {
                pages.show(page)
                dismiss()
                return
            }
            starting = session
            failure = nil
            Task {
                do {
                    try await HostStore.start(session)
                    pages.open(session)
                    dismiss()
                } catch {
                    failure = error.localizedDescription
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
