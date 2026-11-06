import HerdrKit
import SwiftUI

/// The Agents view's Archived shelf (ui/window#archived): the sessions of Claude Code, Codex, Pi and OpenCode on the
/// page's machine that no pane runs, from the agents' own stores, newest first. Read each time it opens; the next page
/// of an agent as the list's end scrolls into view. A menu in its header shows one agent.
struct ArchivedShelf: View {
    let page: Page
    /// The footer's filter: by title and folder.
    let filter: String
    /// The agent the menu shows ("" for all), kept across relaunches.
    @AppStorage("archivedAgent", store: .agents) private var agent = ""
    @AppStorage(Page.openShelves, store: .agents) private var opened = ""
    @AppStorage(AgentPin.key, store: .agents) private var pins = ""
    @State private var list = ClosedList()
    @State private var reading: Set<String> = []
    @State private var failed: Set<String> = []
    @State private var slow = false
    /// Each read anew (an open, Retry); an older one's pages land nowhere.
    @State private var generation = 0
    @State private var attempt = 0

    /// UI tests' stores (`-archivedHome`), never the user's.
    private static let home = UserDefaults.standard.string(forKey: "archivedHome")

    var body: some View {
        let open = opened.split(separator: "\n").contains { $0 == page.shelfKey("Archived") }
        let shown = agent.isEmpty ? Chooser.agents.map(\.command) : [agent]
        let rows = open ? rows(shown) : []
        let next = list.next(of: shown).filter { !failed.contains($0) }
        Shelf(label: "Archived", count: nil, page: page) {
            menu
        } content: {
            ForEach(rows) { row($0) }
            if !next.isEmpty {
                // The list's end: anew after each page, so it reads on while it stays in view (a short filtered list,
                // a page with nothing to show).
                Color.clear.frame(height: 1).id(list.agents.values.map(\.looked).reduce(0, +))
                    .onAppear { Task { await read(next) } }
            }
            if rows.isEmpty || !failed.isDisjoint(with: shown) || problem(shown) != nil {
                status(shown, more: !next.isEmpty)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).padding(.horizontal, 8)
            }
        }
        .task(id: [open ? 1 : 0, attempt]) {
            (list, reading, failed, slow, generation) = (ClosedList(), [], [], false, generation + 1)
            guard open else { return }
            async let pages: Void = read(Chooser.agents.map(\.command))
            // No line while a page reads fast (This Mac).
            if await (try? Task.sleep(for: .seconds(0.3))) != nil {
                slow = true
            }
            await pages
        }
    }

    private var menu: some View {
        Menu {
            Picker("Agents", selection: $agent) {
                Text("All Agents").tag("")
                Divider()
                ForEach(Chooser.agents, id: \.command) { Text($0.name).tag($0.command) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // Filled while it shows one agent.
            Image(systemName: agent.isEmpty ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show Agent")
        .accessibilityLabel("Show Agent")
        .accessibilityValue(agent.isEmpty ? "All Agents" : Chooser.name(agent))
        .accessibilityIdentifier("agents.archived.filter")
    }

    /// The sessions shown: none a live pane runs (on any page of the machine), none pinned (they show in Pinned), none
    /// resuming.
    private func rows(_ shown: [String]) -> [ClosedSession] {
        let live = page.liveSessions.union(page.store.resuming)
        let pinned = Set([AgentPin](json: pins).filter { $0.machine == page.store.machine.id
                && $0.session == page.store.session
        }.map(\.key))
        return list.sessions(of: shown).filter { session in
            !live.contains(session.value) && !pinned.contains(session.value)
                && (session.title.matches(filter) || session.folder.matches(filter))
        }
    }

    private func problem(_ shown: [String]) -> String? {
        shown.lazy.compactMap { agent in
            list.agents[agent]?.problem.map { "\(Chooser.name(agent)) \($0) on \(page.store.machine.name)." }
        }.first
    }

    /// Why there is no row, or what is missing.
    @ViewBuilder private func status(_ shown: [String], more: Bool) -> some View {
        if !failed.isDisjoint(with: shown) {
            HStack(spacing: 6) {
                line("Could not read \(page.store.machine.name)'s sessions.")
                Button("Retry") { attempt += 1 }
                    .buttonStyle(.link).font(.system(size: 11))
                    .accessibilityIdentifier("agents.archived.retry")
            }
        } else if let problem = problem(shown) {
            line(problem)
        } else if more || !reading.isDisjoint(with: shown) {
            line(slow ? "Reading sessions…" : "")
        } else if !filter.trimmingCharacters(in: .whitespaces).isEmpty {
            line("No matching sessions.")
        } else if agent.isEmpty {
            line("No closed sessions on \(page.store.machine.name).")
        } else {
            line("No \(Chooser.name(agent)) sessions.")
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            .accessibilityIdentifier("agents.archived.status")
    }

    /// A click resumes it in a new tab of the workspace for its folder; ⌥-click beside the keyboard card.
    private func row(_ session: ClosedSession) -> some View {
        let id = ClosedPin.id("agents.archived", agent: session.agent, value: session.value)
        return AgentRow(icon: session.agent, title: session.title, line2: page.short(session.folder), id: id,
                        action: { page.resume(session) },
                        hover: { ClosedPin.buttons(session, page, id: id, pinned: false) },
                        trailing: { AgeText(date: session.date) })
            .contextMenu {
                Button("Resume") { page.resume(session, beside: false) }
                Button("Resume to the Side") { page.resume(session, beside: true) }
                Divider()
                Button("Pin") { ClosedPin.pin(session, page) }
            }
    }

    /// The first page of each agent, else the next; each agent's rows show as they come.
    private func read(_ agents: [String]) async {
        let generation = generation, exec = await page.store.machine.exec()
        let pages = agents.filter { !reading.contains($0) }.map { ($0, list.agents[$0]?.looked ?? 0) }
        reading.formUnion(pages.map(\.0))
        await withTaskGroup(of: (String, ClosedPage?).self) { group in
            for (agent, offset) in pages {
                group.addTask {
                    await (agent, try? exec.closedSessions(agent: agent, offset: offset, home: Self.home))
                }
            }
            for await (agent, page) in group where generation == self.generation {
                reading.remove(agent)
                if let page {
                    list.add(page, for: agent)
                } else {
                    failed.insert(agent)
                }
            }
        }
    }
}
