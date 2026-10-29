import HerdrKit
import SwiftUI

/// Relaunch with Chat (ui/chat-view#which-panes-have-it), where Chat | TUI sits on an agent card with no launch marker:
/// it starts the agent again with Oriel's flags in the same session. It asks first while the agent works or waits.
struct EnableChat: View {
    let pane: HostStore.Pane
    let page: Page
    @State private var asking = false
    @Environment(\.look) private var look

    /// An agent with a chat adapter whose session herdr knows, once its processes are known to carry no marker.
    static func offered(_ pane: HostStore.Pane, _ store: HostStore) -> Bool {
        guard pane.program != nil, ChatAdapters.recognize(pane.program) == nil, let session = pane.session,
              let adapter = ChatAdapters.adapter(pane.agent) else { return false }
        return adapter.resume(session) != nil && store.chooser(pane.id) == nil
    }

    var body: some View {
        let name = pane.agentLabel ?? "the agent"
        Button {
            if pane.state == .working || pane.state == .needsYou {
                asking = true
            } else {
                page.store.enableChat(pane)
            }
        } label: {
            Label("Relaunch with Chat", systemImage: "bubble.left.and.text.bubble.right")
                .font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).frame(height: 20)
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .padding(2)
        .background(look.track, in: .rect(cornerRadius: 8))
        .fixedSize()
        .help("Restart \(name) with chat, in the same session")
        .accessibilityIdentifier("pane.\(pane.id).enable-chat")
        .alert("Restart \(name)?", isPresented: $asking) {
            Button("Restart", role: .destructive) { page.store.enableChat(pane) }
            Button("Cancel", role: .cancel) {}
        } message: {
            let doing = pane.state == .needsYou ? "waiting for you" : "working"
            Text("\(name) is \(doing). It stops, then starts again in the same session, with chat.")
        }
    }
}
