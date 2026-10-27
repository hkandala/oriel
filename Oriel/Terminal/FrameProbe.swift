import AppKit
import IOSurface
import Observation

/// e2e (`-recordFrames YES`): for 1.5 s after the first window shows another tab (a tab, workspace or session
/// change, or the overview closing), what each of the tab's cards showed at each run loop turn's Core Animation
/// commit, each drawn (a display link's frames missed a commit of a strip at its first page). A commit counts
/// as a flicker when a card shows neither its first picture nor its last one: no terminal view in the window, no
/// picture or an emptied one, a fade, a third picture, or its terminal moved (a held grid keeps its top left, so a
/// size change is no move). `recorded`: "tab bad/states codes" per change, each card's states
/// as they changed, the codes of bad ones (`-` gone, `0` no picture, `s` a small still, `f` fading, `p` another
/// picture, `j` moved, with the first move in points).
/// Not seen: commits off the main thread or from a flush within a turn, and a card's own SwiftUI opacity (only the
/// terminal layer's fade). libghostty sets a new picture on the main thread, so each is a turn's commit.
@MainActor @Observable
final class FrameProbe {
    static let shared = FrameProbe()
    static let isOn = UserDefaults.standard.bool(forKey: "recordFrames")
    /// The changes' records, "; " between them.
    private(set) var recorded = ""
    /// The page and tab being recorded.
    @ObservationIgnored private var shown: (page: String, tab: String)?
    @ObservationIgnored private var start = 0.0
    /// Each card's states of the change being recorded; nil while its terminal is in no card's host of the window.
    @ObservationIgnored private var samples: [ObjectIdentifier: [Sample?]] = [:]
    /// The ink of each picture (surface and seed) seen in this change.
    @ObservationIgnored private var inks: [String: [Bool]?] = [:]

    private struct Sample: Equatable {
        /// Ink per cell of a coarse grid; nil without a picture.
        let ink: [Bool]?
        let fading: Bool
        /// A still narrower than the card's pixels shows (the overview's snapshot): blurred.
        let small: Bool
        /// In the window (bottom-left based): a held view keeps its top left while its card's size changes.
        let topLeft: CGPoint
    }

    func install() {
        if Self.isOn {
            afterCommit { _ in self.turned() }
        }
    }

    private func turned() {
        guard let pages = WindowPages.windows.first, let window = pages.window, let page = pages.current
        else { return }
        // Its zoom is the overview's; the strip after it is a change, also to the tab shown before.
        guard !pages.overview else {
            finish()
            shown = nil
            return
        }
        let tab = (page: page.id, tab: page.selectedTab?.id ?? "")
        let now = ProcessInfo.processInfo.systemUptime
        if shown.map({ $0 != tab }) ?? true {
            finish()
            shown = tab
            start = now
            // Its record ends with a turn after 1.5 s, also in an idle app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.turned() }
        }
        guard now - start < 1.5 else { return finish() }
        let ids = page.store.panes.filter { $0.tabID == page.selectedTab?.id && !page.floats($0) }
            .compactMap(\.terminalID)
        for terminal in pages.terminals.terminals(Set(ids)) {
            let sample = sample(terminal.view, in: window), id = ObjectIdentifier(terminal)
            if samples[id]?.last != .some(sample) {
                samples[id, default: []].append(sample)
            }
        }
    }

    private func sample(_ view: PaneSurfaceView, in window: NSWindow) -> Sample? {
        guard view.window === window, view.superview is TerminalHost.Host else { return nil }
        let ink = (view.picture as? IOSurface).flatMap { surface in
            let key = "\(ObjectIdentifier(surface)) \(IOSurfaceGetSeed(surface))"
            if let ink = inks[key] {
                return ink
            }
            let ink = Self.ink(surface)
            inks[key] = ink
            return ink
        }
        // A snapshot's still (stretched, as `dropSmallStill` drops), narrower than the card.
        let still = view.still.flatMap { $0 !== view.layer && $0.superlayer != nil && $0.contentsGravity == .resize
            ? $0 : nil
        }
        return Sample(ink: ink, fading: view.layer?.animation(forKey: "reveal") != nil,
                      small: still?.small(in: view) == true,
                      topLeft: view.convert(view.bounds, to: nil).integral.topLeft)
    }

    /// The change's record, once.
    private func finish() {
        guard let shown, !samples.isEmpty else { return }
        var bad = 0, frames = 0, codes = ""
        for list in samples.values {
            guard let first = list.first, let last = list.last ?? nil else { continue }
            frames = max(frames, list.count)
            for sample in list {
                guard let sample else {
                    bad += 1
                    codes += "-"
                    continue
                }
                let blank = sample.ink.map { !$0.contains(true) && last.ink?.contains(true) == true } ?? true
                let code = blank ? "0" : sample.small ? "s" : sample.fading ? "f"
                    : !Self.same(sample.ink, first?.ink) && !Self.same(sample.ink, last.ink) ? "p"
                    : sample.topLeft != last.topLeft ? "j" : ""
                if !code.isEmpty {
                    bad += 1
                    codes += code
                }
                if code == "j", !codes.contains("(") {
                    codes += "(\(Int(sample.topLeft.x - last.topLeft.x)),\(Int(sample.topLeft.y - last.topLeft.y)))"
                }
            }
        }
        recorded += (recorded.isEmpty ? "" : "; ") + "\(shown.tab) \(bad)/\(frames) \(codes)"
        samples = [:]
        inks = [:]
    }

    /// Ink in each of 48 × 32 cells: a cell with a pixel of 4 × 4 far from the picture's corner (its
    /// background). nil for an emptied surface.
    private static func ink(_ surface: IOSurface) -> [Bool]? {
        guard !surface.emptied, surface.bytesPerElement == 4, surface.width > 0,
              surface.height > 0 else { return nil }
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self), row = surface.bytesPerRow
        let pixel = { (column: Int, line: Int) in
            let byte = base + line * row + column * 4
            return Int(byte[0]) + Int(byte[1]) + Int(byte[2]) + Int(byte[3])
        }
        let background = pixel(1, 1)
        let columns = 48, lines = 32, dots = 4, width = surface.width, height = surface.height
        return (0 ..< columns * lines).map { cell in
            (0 ..< dots * dots).contains { dot in
                let column = ((cell % columns) * dots + dot % dots) * width / (columns * dots)
                let line = ((cell / columns) * dots + dot / dots) * height / (lines * dots)
                return abs(pixel(column, line) - background) > 60
            }
        }
    }

    /// The same picture but for a few cells (a cursor).
    private static func same(_ one: [Bool]?, _ two: [Bool]?) -> Bool {
        guard let one, let two else { return one == nil && two == nil }
        return zip(one, two).count { $0 != $1 } <= 8
    }
}

private extension CGRect {
    var topLeft: CGPoint {
        CGPoint(x: minX, y: maxY)
    }
}
