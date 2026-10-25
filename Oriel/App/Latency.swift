#if os(macOS)
    import AppKit
    import HerdrKit
    import Observation
    import SwiftUI

    /// e2e (`-recordLatency YES`): for each key or click, the time from the event to the end of the run loop turn whose
    /// Core Animation commit drew a change of the key window (its page, workspace, tab, tabs, cards, panel or dialog),
    /// and how many turns that took: "⌘T 12ms 0" (phase 25).
    @MainActor @Observable
    final class Latency {
        static let shared = Latency()
        static let isOn = UserDefaults.standard.bool(forKey: "recordLatency")
        private(set) var recorded: [String] = []
        /// The window's open panel, as it was last drawn.
        @ObservationIgnored var panel = ""
        @ObservationIgnored private var pending: Pending?
        private struct Pending {
            let name: String, time: TimeInterval, state: String
            /// When the app got the event.
            let got = ProcessInfo.processInfo.systemUptime
            /// Before the first turn's observers (SwiftUI's update, Core Animation's commit): the event handled.
            var handled: TimeInterval?
            var turns = 0
        }

        /// Once, at launch.
        func install() {
            guard Self.isOn else { return }
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { event in
                MainActor.assumeIsolated { self.event(event) }
                return event
            }
            // After Core Animation's commit (order 2000000), as `-recordLights` does.
            let turn = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue
            let observer = CFRunLoopObserverCreateWithHandler(nil, turn, true, Int.max) { _, _ in
                MainActor.assumeIsolated { self.turned() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            let early = CFRunLoopObserverCreateWithHandler(nil, turn, true, Int.min) { _, _ in
                MainActor.assumeIsolated {
                    if self.pending?.handled == nil {
                        self.pending?.handled = ProcessInfo.processInfo.systemUptime
                    }
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), early, .commonModes)
        }

        private func event(_ event: NSEvent) {
            let name = event.type == .keyDown
                ? Self.glyphs(event.modifierFlags) + (event.charactersIgnoringModifiers ?? "").uppercased() : "click"
            pending = Pending(name: name, time: event.timestamp, state: state)
        }

        private func turned() {
            guard var pending else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - pending.time
            if state != pending.state {
                self.pending = nil
                let got = Int((pending.got - pending.time) * 1000)
                let handled = Int(((pending.handled ?? 0) - pending.time) * 1000)
                recorded
                    .append("\(pending.name) \(Int(elapsed * 1000))ms \(pending.turns) got \(got) handled \(handled)")
            } else if elapsed > 3 {
                self.pending = nil
            } else {
                pending.turns += 1
                self.pending = pending
            }
        }

        /// What the key window shows, in short.
        private var state: String {
            guard let page = WindowPages.windows.first?.current else { return "" }
            let workspace = page.selectedWorkspace, tab = page.selectedTab
            return [page.id, workspace?.id ?? "", tab?.id ?? "", workspace?.tabs.map(\.id).joined(separator: ",") ?? "",
                    tab?.tree?.paneIDs.joined(separator: ",") ?? "", page.zoomedPaneID ?? "",
                    page.closing == nil ? "" : "closing", panel].joined(separator: " ")
        }

        /// The sidebar's pages: how long a swipe moved on after the fingers lifted, "swipe 480ms".
        func scrolled(_ phase: ScrollPhase) {
            guard Self.isOn else { return }
            if phase == .decelerating {
                lifted = ProcessInfo.processInfo.systemUptime
            } else if phase == .idle, let lifted {
                recorded.append("swipe \(Int((ProcessInfo.processInfo.systemUptime - lifted) * 1000))ms")
                self.lifted = nil
            }
        }

        @ObservationIgnored private var lifted: TimeInterval?

        private static func glyphs(_ flags: NSEvent.ModifierFlags) -> String {
            [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .filter { flags.contains($0.0) }.map(\.1).joined()
        }
    }
#endif
