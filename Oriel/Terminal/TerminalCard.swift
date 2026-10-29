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

    func makeNSView(context _: Context) -> Host {
        let host = Host()
        host.clipsToBounds = true
        host.addSubview(terminal.view)
        if Host.record {
            host.setAccessibilityElement(true)
            host.setAccessibilityRole(.group)
        }
        return host
    }

    func updateNSView(_ host: Host, context _: Context) {
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
        if Host.record {
            host.setAccessibilityIdentifier("host.\(terminal.paneID)")
        }
    }

    /// Fits the terminal (or a browser card's web view) to itself once its size stops changing (a window drag, a
    /// divider drag, the sidebar or layout motion): meanwhile the terminal keeps its grid, clipped, so neither
    /// libghostty nor the program reflows at every step. A web view laid its page out at every step, and the
    /// motion stuttered.
    final class Host: NSView {
        private var fitting: Task<Void, Never>?
        /// e2e (`-recordMotion YES`): the sizes this host took, and the ms from the first to the last size of the
        /// latest motion, as its accessibility label ("12 113"). Layout motion gives many sizes; a card made again,
        /// or one that jumps, only one or two.
        static let record = UserDefaults.standard.bool(forKey: "recordMotion")
        private var sizes = 0, motion: (start: TimeInterval, last: TimeInterval)?

        /// A held terminal stays at the top, as the card's content does.
        override var isFlipped: Bool {
            true
        }

        override func resizeSubviews(withOldSize old: NSSize) {
            if Self.record, frame.size != old {
                sizes += 1
                // A motion's sizes come a frame apart; a pause starts the next one.
                let now = ProcessInfo.processInfo.systemUptime
                let start = motion.map { now - $0.last < 0.1 ? $0.start : now } ?? now
                motion = (start, now)
                setAccessibilityLabel("\(sizes) \(Int((now - start) * 1000))")
            }
            fitting?.cancel()
            // At once until its first stream opened (it opens at the card's size; the terminal waits for that to
            // settle), and for a view that never had a frame.
            let surface = view as? PaneSurfaceView
            guard let view, surface == nil || surface?.terminal?.grid != nil, !view.frame.isEmpty else {
                fit()
                return
            }
            fitting = Task {
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled {
                    fit()
                }
            }
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            fitting?.cancel()
            fit()
        }

        /// Gone from here once a newer host adopted it. Last: WebKit docks the Web Inspector below its web view.
        private var view: NSView? {
            subviews.last
        }

        private func fit() {
            guard let view, !bounds.isEmpty, view.frame.size != bounds.size else { return }
            // Before libghostty hears of the size.
            (view as? PaneSurfaceView)?.terminal?.hold()
            view.frame = bounds
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
