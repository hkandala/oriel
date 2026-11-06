import HerdrKit
import SwiftUI

/// The Agents view's Archived shelf (ui/window#archived): the sessions of Claude Code, Codex, Pi and OpenCode on the
/// page's machine that no pane runs, from the agents' own stores, newest first. Read each time it opens; 50 more of
/// an agent as the last row scrolls into view. A menu in its header shows one agent.
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
    @State private var failed = false
    @State private var slow = false
    /// Each read anew (an open, Retry); an older one's pages land nowhere.
    @State private var generation = 0

    /// UI tests' stores (`-archivedHome`), never the user's.
    private static let home = UserDefaults.standard.string(forKey: "archivedHome")

    var body: some View {
        let open = opened.split(separator: "\n").contains { $0 == page.shelfKey("Archived") }
        let shown = agent.isEmpty ? Chooser.agents.map(\.command) : [agent]
        let rows = open ? rows(shown) : []
        Shelf(label: "Archived", count: nil, page: page) {
            menu
        } content: {
            ForEach(rows) { session in
                row(session).onAppear {
                    if session == rows.last {
                        Task { await read(list.next(of: shown)) }
                    }
                }
            }
            if rows.isEmpty || failed || problem(shown) != nil {
                status(shown).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).padding(.horizontal, 8)
            }
        }
        .task(id: open) {
            (list, reading, failed, slow, generation) = (ClosedList(), [], false, false, generation + 1)
            guard open else { return }
            async let pages: Void = read(Chooser.agents.map(\.command))
            // No line while a page reads fast (This Mac).
            try? await Task.sleep(for: .seconds(0.3))
            slow = true
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
        .accessibilityValue(Chooser.agents.first { $0.command == agent }?.name ?? "All Agents")
        .accessibilityIdentifier("agents.archived.filter")
    }

    /// The sessions shown: none a live pane runs (on any page of the machine), none pinned (they show in Pinned).
    private func rows(_ shown: [String]) -> [ClosedSession] {
        let machine = page.store.machine.id
        let live = Set(HostStore.all.filter { $0.machine.id == machine }.flatMap(\.agentPanes).compactMap(\.session))
        let pinned = Set([AgentPin](json: pins).filter { $0.machine == machine && $0.session == page.store.session }
            .map(\.key))
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
    @ViewBuilder private func status(_ shown: [String]) -> some View {
        if failed {
            HStack(spacing: 6) {
                line("Could not read \(page.store.machine.name)'s sessions.")
                Button("Retry") {
                    generation += 1
                    (list, failed, reading) = (ClosedList(), false, [])
                    Task { await read(Chooser.agents.map(\.command)) }
                }
                .buttonStyle(.link).font(.system(size: 11))
                .accessibilityIdentifier("agents.archived.retry")
            }
        } else if let problem = problem(shown) {
            line(problem)
        } else if !reading.isEmpty {
            line(slow ? "Reading sessions…" : "")
        } else if !filter.trimmingCharacters(in: .whitespaces).isEmpty {
            line("No matching sessions.")
        } else {
            line(agent
                .isEmpty ? "No closed sessions on \(page.store.machine.name)." : "No \(Chooser.name(agent)) sessions.")
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
        let exec = await page.store.machine.exec(), generation = generation
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
                    failed = true
                }
            }
        }
    }
}

/// A pinned session no pane runs (Pinned, on top of the Agents view): Resume brings it back; Unpin lets it go to
/// Archived.
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

    /// The page's pins of sessions no pane holds, in pin order, that match the footer's filter.
    static func pins(_ page: Page, filter: String) -> [AgentPin] {
        let panes = page.store.agentPanes
        return [AgentPin](json: AppSettings().pins).filter { pin in
            pin.machine == page.store.machine.id && pin.session == page.store.session && pin.agent != nil
                && !panes.contains { $0.holds(pin) } && (pin.title.matches(filter) || (pin.cwd ?? "").matches(filter))
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
}

extension Chooser {
    static func name(_ command: String) -> String {
        agents.first { $0.command == command }?.name ?? command
    }
}
