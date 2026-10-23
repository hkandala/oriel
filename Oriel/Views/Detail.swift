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
            .glassEffect()
            .accessibilityElement(children: .contain)
        }
    }

    /// The page's selected workspace's tabs, or why there is nothing to show.
    struct Detail: View {
        let pages: WindowPages
        let page: Page

        var body: some View {
            let store = page.store
            let machine = HostStore.name(store.session)
            switch store.state {
            case .connecting:
                // After 0.3 s, so a fast connect shows nothing.
                Waiting(text: "Connecting to \(machine)", delay: .milliseconds(300))
                    .accessibilityIdentifier("detail.connecting")
            case .failed(.notFound):
                message("herdr is not installed", "Install it in a terminal:",
                        "curl -fsSL https://herdr.dev/install.sh | sh")
            case let .failed(.unsupported(text)):
                // The client asks again every 2 s, so an updated herdr clears it.
                message("herdr is too old", text + ".")
            case .failed where !store.isRunning:
                message("\(store.session) is not running", start: true)
            case .live, .failed:
                // Reconnecting (the server runs, the bridge fails) in one branch, so the strip keeps its state through
                // it; the notices stay clickable.
                let reconnecting = store.reconnecting
                tabs(store)
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

        /// The selected workspace's strip, or the button that makes what is missing.
        @ViewBuilder private func tabs(_ store: HostStore) -> some View {
            if let workspace = page.selectedWorkspace {
                if workspace.tabs.isEmpty {
                    Button { Task { await page.newTab() } } label: {
                        Label("New Tab", systemImage: "plus")
                        Text(KeyboardShortcut.newTab.glyphs).foregroundStyle(.secondary)
                    }
                    .disabled(store.writing)
                    .accessibilityIdentifier("new-tab")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Strip(workspace: workspace, page: page)
                }
            } else {
                NewWorkspaceButton(page: page).frame(maxWidth: .infinity, maxHeight: .infinity)
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

        /// What is wrong and the command that fixes it; a stopped session gets a Start button instead (design D47).
        private func message(_ title: String, _ text: String? = nil, _ command: String? = nil,
                             start: Bool = false) -> some View
        {
            ContentUnavailableView {
                Label(title, systemImage: "terminal")
            } description: {
                if let text {
                    Text(text)
                }
                // Why a start failed.
                if let notice = page.store.notice {
                    Text(notice.text).accessibilityIdentifier("detail.notice")
                }
                if let command {
                    Text(command).monospaced().textSelection(.enabled)
                }
            } actions: {
                if start {
                    Button("Start \(page.store.session)") { Task { await page.store.start() } }
                        .accessibilityIdentifier("detail.start")
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
