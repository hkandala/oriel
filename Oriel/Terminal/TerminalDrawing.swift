#if os(macOS)
    import AppKit
    import GhosttyTerminal
    import IOSurface

    /// What a card draws: herdr's frames once they settled at its grid, only while it is shown, and its last picture
    /// meanwhile; never a blank (phase 24, lanes A and F; phase 25, lane O).
    extension PaneTerminal {
        /// The app's paste mode; no cursor until herdr's first frame says whether it shows.
        static let modes = "\u{1B}[?2004h\u{1B}[?25l"

        /// The grid may change (a new card size or text size): the old picture stays until herdr's frames at the new
        /// grid settle (100 ms if it stayed). Before libghostty hears of it, whose renderer thread may draw at once
        /// (CI: garbled glyphs for 3 frames after a ⌘- paused late), and on libghostty's grid change for other paths.
        /// Also with no stream (an evicted card back at a new size); a watcher shows the reflow: it cannot resize.
        func hold() {
            guard ready, !observing else { return }
            ready = false
            settle()
        }

        /// libghostty draws nothing until frames stop for 100 ms (a watcher cannot resize: shown at once), so the
        /// view's layer keeps its last picture: the old text, at the top left (libghostty's layer gravity), or nothing
        /// on a new surface (its background is clear). Not an alpha hide: the text went blank between two pictures.
        func settle() {
            // A rebuilt watcher settles too: its new surface has not parsed the first frame when that reveal would
            // draw.
            if observing, view.still == nil {
                return reveal()
            }
            view.setSurfaceVisible(false)
            // A program that redraws all the time never settles. Under the waiting spinner's 0.5 s.
            deadline = deadline ?? Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled {
                    reveal()
                }
            }
            settling?.cancel()
            settling = Task {
                try? await Task.sleep(for: .milliseconds(100))
                if !Task.isCancelled {
                    reveal()
                }
            }
        }

        /// Draws while shown; an old picture over a new surface goes once that drew.
        func draw() {
            view.setSurfaceVisible(inView)
            if inView {
                view.dropStill()
            }
        }

        /// Drawing resumes: the new picture at once. The first fades in from 0: a fade that never ran leaves it shown.
        private func reveal() {
            settling?.cancel()
            deadline?.cancel()
            deadline = nil
            ready = true
            draw()
            let first = !revealed
            revealed = true
            if first, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.duration = 0.12
                view.layer?.add(fade, forKey: "reveal")
            }
        }
    }

    /// A terminal out of the recently shown set gives up its surface: libghostty's three IOSurfaces of the card's size
    /// (17 MB each for a full-window card on a Retina screen). Its last picture stays: libghostty's old layer, which
    /// keeps showing its last IOSurface, volatile while no window shows it, so it costs no memory then (the system may
    /// take it back under memory pressure). A new surface draws under it until its frames are drawn (design D46).
    extension PaneSurfaceView {
        /// Frees libghostty's surface; the view keeps its picture.
        func free() {
            guard controller != nil else { return }
            // One not dropped yet (shown and evicted again before its new surface drew) stays the picture.
            still = still ?? layer
            controller = nil
            purgeable(window == nil)
        }

        /// A new surface once the view is in a window, with the old picture over it (`terminalDidAttachSurface`).
        func rebuild() {
            guard controller == nil else { return }
            purgeable(false)
            controller = PaneTerminal.controller
        }

        /// The picture the view shows: the old one over a new surface that has not drawn yet.
        var picture: Any? {
            still?.superlayer == nil ? layer?.contents : still?.contents
        }

        /// The new surface draws again: the old picture goes once it drew (its layer's contents changed; libghostty
        /// draws when it stops being occluded). One that never draws keeps showing the old picture.
        func dropStill() {
            // Over a new surface only: not the old layer itself, before its rebuild.
            guard let still, still !== layer, still.superlayer != nil else { return }
            let id = ObjectIdentifier(still)
            // libghostty sets the contents on the main thread: gone in the same transaction as the new picture.
            stillWatch = layer?.observe(\.contents) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.drop(id) }
            }
        }

        private func drop(_ id: ObjectIdentifier) {
            guard let old = still, ObjectIdentifier(old) == id else { return }
            old.removeFromSuperlayer()
            still = nil
            stillWatch = nil
        }

        /// A new surface (`rebuild`) under the old picture: it draws once
        /// herdr's frames settle, as a first stream's, or soon from what a live stream sent meanwhile. Not the first
        /// surface (no grid yet): that one waits for its first stream's frames anyway.
        func coverNewSurface() {
            if let still, let layer, still !== layer {
                // Sized with the view, as it was as its layer; its gravity keeps the picture in place.
                still.frame = layer.bounds
                still.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.addSublayer(still)
            }
            guard let terminal, terminal.grid != nil else { return }
            // A settle begun before (a resize while evicted) would reveal the empty surface.
            terminal.settling?.cancel()
            terminal.deadline?.cancel()
            terminal.deadline = nil
            terminal.ready = false
            setSurfaceVisible(false)
            if terminal.state != .idle {
                terminal.settle()
            }
        }

        /// Volatile while the view is in no window; back in one, a picture the system took is gone, and the next
        /// reveal fades in as a first one. A kept surface's picture too while it does not draw: libghostty let go of
        /// its swap chain then (occlusion, as Ghostty's hidden tabs), so the layer alone holds that IOSurface; taken
        /// back, it shows the card's fill until the surface draws.
        func purgeable(_ volatile: Bool) {
            let live = controller != nil
            guard !(live && volatile && terminal?.inView == true),
                  let picture = live ? layer : still, let surface = picture.contents as? IOSurface else { return }
            var old: UInt32 = 0
            IOSurfaceSetPurgeable(surface, volatile ? 1 : 0, &old)
            if live, !volatile, old == 2 {
                picture.contents = nil
            } else if !volatile, old == 2 {
                still?.contents = nil
                still = nil
                // The next reveal fades in, as a first one.
                terminal?.revealed = false
            }
        }
    }
#endif
