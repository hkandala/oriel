import Foundation

/// A short message at the bottom of the strip (design: Notice).
struct Notice {
    enum Tone {
        case error, warning, info
    }

    let text: String
    var tone = Tone.error
    let id = UUID()
}

#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// A notice's glass capsule (design: Notice).
    struct NoticeCapsule<Action: View>: View {
        let tone: Notice.Tone
        let text: String
        /// Instead of the tone's symbol.
        var symbol: String?
        /// A button, or the ✕.
        @ViewBuilder var action: Action
        @Environment(\.look) private var look

        var body: some View {
            let (toneSymbol, label, color) = switch tone {
            case .error: ("xmark.octagon.fill", "Error", look.error)
            case .warning: ("exclamationmark.triangle.fill", "Warning", look.needsYou)
            case .info: ("info.circle.fill", "Information", look.working)
            }
            HStack(spacing: 8) {
                Image(systemName: symbol ?? toneSymbol)
                    .foregroundStyle(color)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("notice.symbol")
                Text(text).lineLimit(2)
                action
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .floatingGlass(in: .capsule)
            .accessibilityElement(children: .contain)
        }
    }

    /// The page's selected workspace's tabs, or why there is nothing to show.
    struct Detail: View {
        let pages: WindowPages
        let page: Page

        var body: some View {
            let store = page.store
            let machine = store.name
            switch store.state {
            case .connecting:
                // After 0.3 s, so a fast connect shows nothing; ssh's question replaces it while it is up.
                if pages.question == nil {
                    Waiting(text: "Connecting to \(machine)", delay: .milliseconds(300))
                        .accessibilityIdentifier("detail.connecting")
                }
            case .failed(.notFound):
                message(store.machine.isRemote ? "herdr is not installed on \(store.machine.name)"
                    : "herdr is not installed", "Install it in a terminal:",
                    "curl -fsSL https://herdr.dev/install.sh | sh")
            case let .failed(.disconnected(text)):
                // Retries stopped: only Connect may ask (machines#health-check).
                message("Disconnected from \(store.machine.name)", text,
                        button: ("Connect", "connect", { await store.connect(in: pages) }))
            case let .failed(.unsupported(text)):
                // The client asks again every 2 s, so an updated herdr clears it.
                message("herdr is too old", text + ".")
            case .failed where !store.isRunning:
                message("\(store.session) is not running",
                        button: ("Start \(store.session)", "start", { await store.start() }))
            case .live, .failed:
                // Reconnecting (the server runs, the bridge fails) in one branch, so the strip keeps its state through
                // it; the notices stay clickable.
                let reconnecting = store.reconnecting
                tabs()
                    .opacity(reconnecting ? 0.5 : 1)
                    .allowsHitTesting(!reconnecting)
                    .overlay {
                        if reconnecting {
                            Waiting(text: "Reconnecting to \(machine)").accessibilityIdentifier("detail.reconnecting")
                        }
                    }
                    .overlay(alignment: .bottom) { notices(store) }
            }
        }

        /// The selected workspace's strip, the button that makes a missing tab, or that the session is empty: its page
        /// header's `+` makes a workspace (user, phase 28).
        @ViewBuilder private func tabs() -> some View {
            if let workspace = page.selectedWorkspace {
                if workspace.tabs.isEmpty {
                    Button { Task { await page.newTab() } } label: {
                        Label("New Tab", systemImage: "plus")
                        Text(KeyboardShortcut.newTab.glyphs).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("new-tab")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // A strip of its own per workspace: a shared one could lay out no page after a switch and stay
                    // empty (phase 25, `make strip-check`).
                    Strip(workspace: workspace, page: page).id("\(page.id) \(workspace.id)")
                }
            } else if page.store.state == .live {
                // Not while it reconnects before its first snapshot.
                ContentUnavailableView("This session is empty", systemImage: "square.dashed")
                    .accessibilityIdentifier("detail.empty")
            }
        }

        private func notices(_ store: HostStore) -> some View {
            VStack(spacing: gap) {
                if let notice = store.notice {
                    NoticeCapsule(tone: notice.tone, text: notice.text) {
                        Button("Close", systemImage: "xmark") { store.notice = nil }
                            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityIdentifier("notice.close")
                    }
                    .accessibilityIdentifier("detail.notice")
                }
                // Another window controls the session (D66). Under a notice; no ✕: only Take Back ends it.
                if page.watched {
                    let text = "Controlled in another window"
                    NoticeCapsule(tone: .info, text: text, symbol: "macwindow.on.rectangle") {
                        Button("Take Back") { pages.control(store) }
                            .accessibilityIdentifier("notice.controlled.take-back")
                    }
                    .accessibilityIdentifier("notice.controlled")
                    .onAppear {
                        AccessibilityNotification.Announcement(text).post()
                    }
                }
            }
            .padding(.horizontal, gap * 2)
            .padding(.bottom, 30)
        }

        // swiftlint:disable large_tuple
        /// What is wrong and the command that fixes it, or the button that does: Start for a stopped session (design
        /// D47), Connect for a machine that needs an answer.
        private func message(_ title: String, _ text: String? = nil, _ command: String? = nil,
                             button: (title: String, id: String, act: () async -> Void)? = nil) -> some View
        { // swiftlint:enable large_tuple
            ContentUnavailableView {
                Label(title, systemImage: "terminal")
            } description: {
                if let text {
                    Text(text).accessibilityIdentifier("detail.text")
                }
                // Why a start failed.
                if let notice = page.store.notice {
                    Text(notice.text).accessibilityIdentifier("detail.notice")
                }
                if let command {
                    Text(command).monospaced().textSelection(.enabled)
                }
            } actions: {
                if let button {
                    Button(button.title) { Task { await button.act() } }
                        .accessibilityIdentifier("detail.\(button.id)")
                }
            }
        }
    }

    /// A spinner and one line, after `delay`.
    struct Waiting: View {
        var text = ""
        var delay = Duration.zero
        @State private var shown = false

        var body: some View {
            ProgressView(text).controlSize(text.isEmpty ? .small : .regular).opacity(shown ? 1 : 0)
                .task {
                    try? await Task.sleep(for: delay)
                    shown = true
                }
        }
    }
#endif
