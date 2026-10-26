#if os(macOS)
    import SwiftUI

    /// A jump key's hint ("⌘1") on a tab or a workspace row while its modifiers are held.
    struct Keycap: View {
        let text: String
        static let transition = AnyTransition.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.13)),
                                                         removal: .opacity.animation(.easeOut(duration: 0.1)))

        var body: some View {
            Text(text).font(.system(size: 10, weight: .semibold)).fixedSize()
                .padding(.horizontal, 4).padding(.vertical, 1)
                .glassEffect(.regular, in: .rect(cornerRadius: 4))
        }
    }

    extension View {
        /// `shown` turns on once one of `modifiers` alone is held 0.7 s with the window key, and off when they change;
        /// a
        /// key pressed first (⌘T) cancels. ⌘ for the tabs' keycaps, ⌘ or ⌃⌘ for the workspace rows' (user, phase 29).
        func keycapHints(_ modifiers: NSEvent.ModifierFlags..., shown: Binding<Bool>) -> some View {
            modifier(KeycapHints(modifiers: modifiers, shown: shown))
        }
    }

    private struct KeycapHints: ViewModifier {
        let modifiers: [NSEvent.ModifierFlags]
        @Binding var shown: Bool
        @State private var pending: Task<Void, Never>?
        @State private var monitor: Any?
        @Environment(\.appearsActive) private var appearsActive

        func body(content: Content) -> some View {
            content
                .onAppear {
                    if monitor == nil {
                        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: watch)
                    }
                }
                .onDisappear {
                    pending?.cancel()
                    monitor.map(NSEvent.removeMonitor)
                    monitor = nil
                }
                // ⌘-Tab away: the ⌘ release goes to the other app.
                .onChange(of: appearsActive) {
                    if !appearsActive {
                        pending?.cancel()
                        shown = false
                    }
                }
        }

        private func watch(_ event: NSEvent) -> NSEvent? {
            MainActor.assumeIsolated {
                pending?.cancel()
                let held = modifiers.contains(event.modifierFlags.intersection([.command, .shift, .option, .control]))
                // ponytail: any key window of the app, so keys held in one window light every window's keycaps;
                // compare event.window to this view's window to stop that.
                if event.type == .flagsChanged, held, event.window?.isKeyWindow == true {
                    pending = Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        if !Task.isCancelled {
                            shown = true
                        }
                    }
                } else if !held {
                    shown = false
                }
            }
            return event
        }
    }
#endif
