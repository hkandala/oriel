#if os(macOS)
    import AppKit
    import IOSurface
    import Observation

    /// e2e (`-recordFrames YES`): for 1.5 s after the first window shows another tab (a tab, workspace or session
    /// change, or the overview closing), what each of the tab's cards showed at each run loop turn's Core Animation
    /// commit, each drawn (a display link's frames missed a commit of a strip at its first page). A commit counts
    /// as a flicker when a card shows neither its first picture nor its last one: no terminal view in the window, no
    /// picture or an emptied one, a fade, a third picture, or its terminal moved (a held grid keeps its top left, so a
    /// size change is no move). Phase 29, lane T. `recorded`: "tab bad/states codes" per change, each card's states
    /// as they changed, the codes of bad ones (`-` gone, `0` no picture, `f` fading, `p` another picture, `j` moved,
    /// with the first move in points).
    @MainActor @Observable
    final class FrameProbe {
        static let shared = FrameProbe()
        static let isOn = UserDefaults.standard.bool(forKey: "recordFrames")
        private(set) var recorded: [String] = []
        @ObservationIgnored private var shown = ""
        @ObservationIgnored private var start = 0.0
        /// Each card's states of the change being recorded.
        @ObservationIgnored private var samples: [ObjectIdentifier: [Sample]] = [:]
        /// The ink of each picture (surface and seed) seen in this change.
        @ObservationIgnored private var inks: [String: [Bool]?] = [:]

        private struct Sample: Equatable {
            /// In its window, in a card's host.
            var there = false
            /// Ink per cell of a coarse grid; nil without a picture.
            var ink: [Bool]?
            var fading = false
            var frame = CGRect.zero
        }

        func install() {
            guard Self.isOn else { return }
            // After Core Animation's commit (order 2000000), as `Latency` does.
            let turn = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue
            let observer = CFRunLoopObserverCreateWithHandler(nil, turn, true, Int.max) { _, _ in
                MainActor.assumeIsolated { self.turned() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        private func turned() {
            guard let pages = WindowPages.windows.first, let page = pages.current else { return }
            // Its zoom is the overview's; the strip after it is a change, also to the tab shown before.
            guard !pages.overview else {
                finish()
                shown = ""
                return
            }
            let tab = "\(page.id) \(page.selectedTab?.id ?? "")"
            let now = ProcessInfo.processInfo.systemUptime
            if tab != shown {
                finish()
                shown = tab
                start = now
            }
            guard now - start < 1.5 else { return finish() }
            let ids = page.store.panes.filter { $0.tabID == page.selectedTab?.id && !page.floats($0) }
                .compactMap(\.terminalID)
            for terminal in pages.terminals.terminals(Set(ids)) {
                let sample = sample(terminal.view, in: pages.window), id = ObjectIdentifier(terminal)
                if samples[id]?.last != sample {
                    samples[id, default: []].append(sample)
                }
            }
        }

        private func sample(_ view: PaneSurfaceView, in window: NSWindow?) -> Sample {
            guard window != nil, view.window === window, view.superview is TerminalHost.Host else { return Sample() }
            let still = view.still?.superlayer == nil ? nil : view.still
            let picture = (still ?? view.layer)?.contents as? IOSurface
            let ink = picture.flatMap { surface in
                let key = "\(ObjectIdentifier(surface)) \(IOSurfaceGetSeed(surface))"
                if let ink = inks[key] {
                    return ink
                }
                let ink = Self.ink(surface)
                inks[key] = ink
                return ink
            }
            return Sample(there: true, ink: ink,
                          fading: view.layer?.animation(forKey: "reveal") != nil,
                          frame: view.convert(view.bounds, to: nil).integral)
        }

        /// The change's record, once.
        private func finish() {
            guard !samples.isEmpty else { return }
            var bad = 0, frames = 0, codes = ""
            for list in samples.values {
                guard let first = list.first, let last = list.last else { continue }
                frames = max(frames, list.count)
                for sample in list {
                    let blank = sample.ink.map { !$0.contains(true) && last.ink?.contains(true) == true } ?? true
                    let code = !sample.there ? "-" : blank ? "0" : sample.fading ? "f"
                        : !Self.same(sample.ink, first.ink) && !Self.same(sample.ink, last.ink) ? "p"
                        : sample.frame.origin != last.frame.origin ? "j" : ""
                    if !code.isEmpty {
                        bad += 1
                        codes += code
                    }
                    if code == "j", !codes.contains("(") {
                        let move = [sample.frame.minX - last.frame.minX, sample.frame.minY - last.frame.minY]
                        codes += "(" + move.map { "\(Int($0))" }.joined(separator: ",") + ")"
                    }
                }
            }
            recorded.append("\(shown.split(separator: " ").last ?? "") \(bad)/\(frames) \(codes)")
            samples = [:]
            inks = [:]
        }

        /// Ink in each of 48 × 32 cells: a cell with a pixel of 4 × 4 far from the picture's corner (its
        /// background). nil for an emptied surface (the system took it back).
        private static func ink(_ surface: IOSurface) -> [Bool]? {
            var state: UInt32 = 0
            IOSurfaceSetPurgeable(surface, 3, &state)
            guard state != 2, surface.bytesPerElement == 4, surface.width > 0, surface.height > 0 else { return nil }
            surface.lock(options: .readOnly, seed: nil)
            defer { surface.unlock(options: .readOnly, seed: nil) }
            let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self), row = surface.bytesPerRow
            let pixel = { (column: Int, line: Int) in
                let byte = base + line * row + column * 4
                return Int(byte[0]) + Int(byte[1]) + Int(byte[2]) + Int(byte[3])
            }
            let background = pixel(1, 1)
            let width = surface.width, height = surface.height
            return (0 ..< 32 * 48).map { cell in
                (0 ..< 16).contains { dot in
                    let column = ((cell % 48) * 4 + dot % 4) * width / 192
                    return abs(pixel(column, ((cell / 48) * 4 + dot / 4) * height / 128) - background) > 60
                }
            }
        }

        /// The same picture but for a few cells (a cursor).
        private static func same(_ one: [Bool]?, _ two: [Bool]?) -> Bool {
            guard let one, let two else { return one == nil && two == nil }
            return zip(one, two).count { $0 != $1 } <= 8
        }
    }
#endif
