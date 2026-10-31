import AppKit

/// Fits the terminal (or a browser card's web view) to itself once its size stops changing (a window drag, a
/// divider drag, the sidebar or layout motion): meanwhile the terminal keeps its grid, clipped, so neither
/// libghostty nor the program reflows at every step. A web view laid its page out at every step, and the
/// motion stuttered.
final class SettlingHost: NSView {
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
        // settle), for a view that never had a frame, and for a web view on its new host's first size (it comes with
        // its old one).
        let surface = view as? PaneSurfaceView
        guard let view, surface == nil || surface?.terminal?.grid != nil, !view.frame.isEmpty,
              surface != nil || old != .zero
        else {
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
    private var view: NSView? {
        subviews.first
    }

    private func fit() {
        guard let view, !bounds.isEmpty, view.frame.size != bounds.size else { return }
        // Before libghostty hears of the size.
        (view as? PaneSurfaceView)?.terminal?.hold()
        view.frame = bounds
    }
}
