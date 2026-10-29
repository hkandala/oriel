import AppKit
import SwiftUI

/// Shows a pane's terminal view. The registry owns the view; the newest host adopts it, so a page
/// SwiftUI rebuilds while the strip scrolls never destroys the surface (design: making the strip
/// work).
struct TerminalHost: NSViewRepresentable {
    let terminal: PaneTerminal
    /// The card's dim. On the host view: SwiftUI's `opacity` moved the terminal's accessibility frame half a card
    /// down, so clicks at its center missed it.
    let alpha: CGFloat

    func makeNSView(context _: Context) -> SettlingHost {
        let host = SettlingHost()
        host.clipsToBounds = true
        host.addSubview(terminal.view)
        if SettlingHost.record {
            host.setAccessibilityElement(true)
            host.setAccessibilityRole(.group)
        }
        return host
    }

    func updateNSView(_ host: SettlingHost, context _: Context) {
        // A new pane's chooser hid it (ui/new-pane): it fades in as the chooser fades out.
        if host.alphaValue == 0, alpha > 0,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || Animation.forceMotion
        {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                host.animator().alphaValue = alpha
            }
        } else {
            host.alphaValue = alpha
        }
        if SettlingHost.record {
            host.setAccessibilityIdentifier("host.\(terminal.paneID)")
        }
    }
}

/// A card's terminal, with what to do when it does not stream.
struct TerminalCard: View {
    let terminal: PaneTerminal
    /// Another window controls the session (D66): the window's capsule offers Take Back instead of the card.
    let watched: Bool
    /// The content's opacity: the watching dim (D66); 0 under a new pane's chooser, with no spinner.
    let alpha: CGFloat

    var body: some View {
        TerminalHost(terminal: terminal, alpha: alpha)
            // A new terminal in the same spot (panes swapped) needs a new host to adopt it.
            .id(ObjectIdentifier(terminal))
            .overlay(alignment: .bottom) {
                switch terminal.state {
                // Not under a new pane's chooser, where it could not be clicked.
                case _ where alpha == 0: EmptyView()
                case .watching where !watched:
                    Button("In use elsewhere · Take Back", action: terminal.takeBack)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("pane.\(terminal.paneID).take-back")
                        .padding(gap)
                case let .failed(text):
                    // herdr's reason; Retry opens the stream again.
                    VStack {
                        Text(text).font(.caption).foregroundStyle(.secondary)
                        Button("Retry", action: terminal.show).buttonStyle(.glass)
                            .accessibilityIdentifier("pane.\(terminal.paneID).retry")
                    }
                    .padding(gap)
                case .idle, .live, .watching:
                    EmptyView()
                }
            }
            // The card's fill (after a grid change, its old picture) until herdr drew it at its size; a spinner
            // only when that takes over 0.5 s.
            .overlay {
                if !terminal.ready, !terminal.state.isFailed, alpha > 0 {
                    Waiting(delay: .milliseconds(500))
                }
            }
    }
}
