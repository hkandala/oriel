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
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                MainActor.assumeIsolated { self.meter.scrolled() }
                return event
            }
            // After Core Animation's commit (order 2000000), as `-recordLights` does.
            let turn = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue
                | CFRunLoopActivity.afterWaiting.rawValue
            let observer = CFRunLoopObserverCreateWithHandler(nil, turn, true, Int.max) { _, activity in
                MainActor.assumeIsolated {
                    if activity == .afterWaiting {
                        self.awake = ProcessInfo.processInfo.systemUptime
                    } else {
                        self.turned()
                    }
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            Task {
                while true {
                    try? await Task.sleep(for: .seconds(5))
                    recordMain()
                }
            }
        }

        /// The main thread's work in the last 5 s (phase 29): run loop turns from wake to sleep, the longest, the
        /// snapshots applied and their own time: "main 812ms 120ms 34 210ms".
        private func recordMain() {
            // A turn still running counts up to now, so a main thread that never sleeps does not show as idle.
            if let awake {
                let now = ProcessInfo.processInfo.systemUptime
                busy += now - awake
                longest = max(longest, now - awake)
                self.awake = now
            }
            recorded
                .append("main \(Int(busy * 1000))ms \(Int(longest * 1000))ms \(snapshots) \(Int(applying * 1000))ms")
            (busy, longest, snapshots, applying) = (0, 0, 0, 0)
        }

        /// A snapshot's apply on the main thread, from `start` on.
        func applied(since start: TimeInterval) {
            guard Self.isOn else { return }
            snapshots += 1
            applying += ProcessInfo.processInfo.systemUptime - start
        }

        @ObservationIgnored private var awake: TimeInterval?
        @ObservationIgnored private var busy = 0.0
        @ObservationIgnored private var longest = 0.0
        @ObservationIgnored private var applying = 0.0
        @ObservationIgnored private var snapshots = 0
        @ObservationIgnored private lazy var meter = ScrollMeter { self.recorded.append($0) }

        private func event(_ event: NSEvent) {
            let name = event.type == .keyDown
                ? Self.glyphs(event.modifierFlags) + (event.charactersIgnoringModifiers ?? "").uppercased() : "click"
            pending = Pending(name: name, time: event.timestamp, state: state)
        }

        private func turned() {
            if let awake {
                let turn = ProcessInfo.processInfo.systemUptime - awake
                busy += turn
                longest = max(longest, turn)
                self.awake = nil
            }
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
        /// the ms to the last change, last the ms to the session's show (-1: none): "swipe 230ms 0:145,8:152,… 190"
        /// (phases 27, 28).
        func lifted(_ offset: Double) {
            guard Self.isOn else { return }
            lifted = ProcessInfo.processInfo.systemUptime
            slide = []
            shownAt = -1
            slid(offset)
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                let path = slide.map { "\($0.0):\(Int($0.1.rounded()))" }.joined(separator: ",")
                recorded.append("swipe \(slide.last?.0 ?? 0)ms \(path) \(shownAt)")
                lifted = nil
            }
        }

        func slid(_ offset: Double) {
            guard let lifted, slide.last?.1 != offset else { return }
            slide.append((Int((ProcessInfo.processInfo.systemUptime - lifted) * 1000), offset))
        }

        /// The swipe's session showed.
        func shown() {
            if let lifted {
                shownAt = Int((ProcessInfo.processInfo.systemUptime - lifted) * 1000)
            }
        }

        /// A test's note in the record.
        func note(_ text: String) {
            if Self.isOn {
                recorded.append(text)
            }
        }

        @ObservationIgnored private var shownAt = -1
        @ObservationIgnored private var lifted: TimeInterval?
        @ObservationIgnored private var slide: [(Int, Double)] = []

        private static func glyphs(_ flags: NSEvent.ModifierFlags) -> String {
            [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .filter { flags.contains($0.0) }.map(\.1).joined()
        }
    }

    /// Frames while the window scrolls (phase 29): a display link runs from a scroll event until 0.3 s after the
    /// last, and records "scroll <frames> <hitches> <ms>"; a hitch is a frame more than 25 ms after the one before.
    @MainActor
    private final class ScrollMeter: NSObject {
        let record: (String) -> Void
        private var link: CADisplayLink?
        private var start = 0.0, last = 0.0, lastScroll = 0.0
        private var frames = 0, hitches = 0

        init(record: @escaping (String) -> Void) {
            self.record = record
        }

        func scrolled() {
            lastScroll = ProcessInfo.processInfo.systemUptime
            guard link == nil, let screen = NSScreen.main else { return }
            (start, last, frames, hitches) = (lastScroll, lastScroll, 0, 0)
            link = screen.displayLink(target: self, selector: #selector(frame))
            link?.add(to: .main, forMode: .common)
        }

        @objc private func frame(_ link: CADisplayLink) {
            let now = ProcessInfo.processInfo.systemUptime
            frames += 1
            hitches += now - last > 0.025 ? 1 : 0
            last = now
            if now - lastScroll > 0.3 {
                link.invalidate()
                self.link = nil
                record("scroll \(frames) \(hitches) \(Int((now - start) * 1000))ms")
            }
        }
    }
#endif
