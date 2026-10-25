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
                recorded.append("\(pending.name) \(Int(elapsed * 1000))ms \(pending.turns)")
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

        /// The sidebar's pages after a swipe's lift: their offset at each frame for 0.8 s, in ms from the lift; first
        /// the ms to the last change: "swipe 230ms 0:145,8:152,…" (phase 27).
        func lifted(_ offset: Double) {
            guard Self.isOn else { return }
            lifted = ProcessInfo.processInfo.systemUptime
            slide = []
            slid(offset)
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                let path = slide.map { "\($0.0):\(Int($0.1.rounded()))" }.joined(separator: ",")
                recorded.append("swipe \(slide.last?.0 ?? 0)ms \(path)")
                lifted = nil
            }
        }

        func slid(_ offset: Double) {
            guard let lifted, slide.last?.1 != offset else { return }
            slide.append((Int((ProcessInfo.processInfo.systemUptime - lifted) * 1000), offset))
        }

        @ObservationIgnored private var lifted: TimeInterval?
        @ObservationIgnored private var slide: [(Int, Double)] = []

        private static func glyphs(_ flags: NSEvent.ModifierFlags) -> String {
            [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .filter { flags.contains($0.0) }.map(\.1).joined()
        }
    }
#endif
