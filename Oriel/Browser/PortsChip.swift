import HerdrKit
import SwiftUI

/// The ports chip (future-work/web-page#finding-ports): the machine's listening TCP ports, from one run each time the
/// menu opens, grouped by the herdr workspace whose pane started them; a pick loads `localhost:<port>` in the card.
struct PortsChip: View {
    let browser: Browser
    let page: Page
    @State private var listed: [Listener]?
    @State private var error: String?
    @State private var asked: ContinuousClock.Instant?

    var body: some View {
        let id = "browser.\(browser.paneID).ports"
        Menu {
            Group {
                if let error {
                    Text(error)
                } else if let listed, listed.isEmpty {
                    Text("No Listening Ports")
                } else if let listed {
                    let groups = groups(listed)
                    if groups.count == 1, groups[0].name == nil {
                        items(groups[0].ports)
                    } else {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            Section(group.name ?? "Other") { items(group.ports) }
                        }
                    }
                } else {
                    Text("Looking for Ports…")
                }
            }
            // Each item appears as the menu opens, and the new ones as the answer comes: one run per opening.
            .onAppear {
                guard asked.map({ ContinuousClock.now - $0 > .seconds(1) }) ?? true else { return }
                asked = .now
                look()
            }
        } label: {
            Image(systemName: "network").font(.system(size: 11)).frame(width: 22, height: 22)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeStyle(radius: 22 / 4))
        .fixedSize()
        .help("Ports")
        .accessibilityLabel("Ports")
        .accessibilityIdentifier(id)
    }

    private func items(_ ports: [Listener]) -> some View {
        ForEach(ports, id: \.port) { listener in
            Button(":\(listener.port)" + (listener.command.isEmpty ? "" : " \(listener.command)")) {
                browser.go("localhost:\(listener.port)")
            }
        }
    }

    /// The last answer shows until the new one comes.
    private func look() {
        let store = page.store
        Task {
            do {
                listed = try await store.machine.exec().listeners().sorted { $0.port < $1.port }
                error = nil
            } catch {
                self.error = "\(store.machine.name) did not answer"
            }
        }
    }

    /// The session's workspaces in their order, then the rest as "Other"; one unnamed group when none is known.
    private func groups(_ listed: [Listener]) -> [(name: String?, ports: [Listener])] {
        let session = page.store.session
        let named = page.store.workspaces.compactMap { workspace in
            let ports = listed.filter { $0.session == session && $0.workspace == workspace.id }
            return ports.isEmpty ? nil : (name: Optional(workspace.label), ports: ports)
        }
        let rest = listed.filter { listener in !named.contains { $0.ports.contains(listener) } }
        return named + (rest.isEmpty ? [] : [(name: nil, ports: rest)])
    }
}
