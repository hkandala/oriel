#if os(macOS)
    import AppKit
    import SwiftUI

    /// Shows a pane's terminal view. The registry owns the view; the newest host adopts it, so a page
    /// SwiftUI rebuilds while the strip scrolls never destroys the surface (design: making the strip
    /// work).
    struct TerminalHost: NSViewRepresentable {
        let terminal: PaneTerminal
        /// The content's opacity. On the host view: SwiftUI's `opacity` moved the terminal's accessibility frame half a
        /// card down, so clicks at its center missed it.
        let alpha: CGFloat
        @Environment(\.layoutMoving) private var moving
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeNSView(context _: Context) -> Host {
            let host = Host()
            host.clipsToBounds = true
            host.addSubview(terminal.view)
            return host
        }

        func updateNSView(_ host: Host, context _: Context) {
            // The first frame fades in over 0.2 s instead of popping in (alpha 0 until then).
            if host.alphaValue == 0, alpha > 0, !reduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    host.animator().alphaValue = alpha
                }
            } else {
                host.alphaValue = alpha
            }
            host.holding = moving
        }

        /// Fits the terminal to itself, except while cards move (layout motion): then the terminal keeps its size,
        /// clipped, and fits once when they stop.
        final class Host: NSView {
            /// A held terminal stays at the top, as the card's content does.
            override var isFlipped: Bool {
                true
            }

            var holding = false {
                didSet {
                    // Not before its first layout (a re-hosted terminal would go 0 × 0 for a moment).
                    if !holding, !bounds.isEmpty {
                        subviews.first?.frame = bounds
                    }
                }
            }

            override func resizeSubviews(withOldSize _: NSSize) {
                // A terminal that never had a size takes one at once.
                if !holding || subviews.first?.frame.isEmpty == true {
                    subviews.first?.frame = bounds
                }
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
            TerminalHost(terminal: terminal, alpha: terminal.drawn ? alpha : 0)
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
                        VStack {
                            Text("Restart herdr on This Mac")
                            Text(text).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(gap)
                    case .idle, .live, .watching:
                        EmptyView()
                    }
                }
        }
    }
#endif
