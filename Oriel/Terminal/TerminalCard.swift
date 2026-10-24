#if os(macOS)
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
            return host
        }

        func updateNSView(_ host: Host, context _: Context) {
            host.alphaValue = alpha
        }

        /// Fits the terminal to itself once its size stops changing (a window drag, a divider drag, the sidebar or
        /// layout motion): meanwhile the terminal keeps its grid, clipped, so neither libghostty nor the program
        /// reflows at every step.
        final class Host: NSView {
            private var fitting: Task<Void, Never>?

            /// A held terminal stays at the top, as the card's content does.
            override var isFlipped: Bool {
                true
            }

            override func resizeSubviews(withOldSize _: NSSize) {
                fitting?.cancel()
                // At once until its first stream opened (it opens at the card's size; the terminal waits for that to
                // settle), and for a view that never had a frame.
                guard let view, view.terminal?.grid != nil, !view.frame.isEmpty else {
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

            /// Gone from here once a newer host adopted it.
            private var view: PaneSurfaceView? {
                subviews.first as? PaneSurfaceView
            }

            private func fit() {
                guard let view, !bounds.isEmpty, view.frame.size != bounds.size else { return }
                // Before libghostty hears of the size.
                view.terminal?.hold()
                view.frame = bounds
            }
        }
    }

    /// A card's terminal, with what to do when it does not stream.
    struct TerminalCard: View {
        let terminal: PaneTerminal
        /// Another window controls the session (D66): the window's capsule offers Take Back instead of the card.
        let watched: Bool
        /// The content's opacity: the fade (D64) and the watching dim.
        let alpha: CGFloat

        var body: some View {
            TerminalHost(terminal: terminal, alpha: alpha)
                // A new terminal in the same spot (panes swapped) needs a new host to adopt it.
                .id(ObjectIdentifier(terminal))
                .overlay(alignment: .bottom) {
                    switch terminal.state {
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
                    if !terminal.ready, !terminal.state.isFailed {
                        Waiting(delay: .milliseconds(500))
                    }
                }
        }
    }
#endif
