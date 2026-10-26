#if os(macOS)
    import AppKit
    import CoreImage
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

        /// Leaving view, a kept one's picture is kept first (`keepPicture`, a full copy); every one's small copy for
        /// the
        /// overview. One the overview alone showed lets go of its surface next: its snapshot is all it needs.
        func inViewChanged() {
            if !inView {
                if PaneViewRegistry.recent.contains(where: { $0 === self }) {
                    view.keepPicture()
                }
                takeSnapshot()
            }
            if ready {
                draw()
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
            // Not in an overview tile: its snapshot or fill shows until it drew, then the terminal at once.
            if first, !(view.superview is MiniTerminal.Mini),
               !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.duration = 0.06
                view.layer?.add(fade, forKey: "reveal")
            }
        }
    }

    /// The overview's snapshots (phase 28): a tile that is not live shows its terminal's last picture, 360 px wide at
    /// most (about 0.4 MB), so one scrolled into view shows at once, with no fade, until it is live. An IOSurface: Core
    /// Animation shows it without a copy of its own (a `CGImage` doubled the memory, phase 28 on Retina).
    extension PaneTerminal {
        /// ponytail: a count, not bytes; 256 at most is about 100 MB. Least recently taken first out.
        @MainActor static var snapshots: [PaneTerminal] = []
        private static let context = CIContext(options: [.cacheIntermediates: false])

        func takeSnapshot() {
            guard let surface = view.picture as? IOSurface, surface.width > 0 else { return }
            let space = IOSurfaceCopyValue(surface, kIOSurfaceColorSpace)
            let image = CIImage(ioSurface: surface).applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: min(1, 360 / CGFloat(surface.width)),
            ])
            let size = image.extent.integral
            guard !surface.emptied, let small = IOSurface(properties: [
                .width: Int(size.width), .height: Int(size.height), .bytesPerElement: 4,
                .pixelFormat: surface.pixelFormat,
            ]) else { return }
            if let space {
                IOSurfaceSetValue(small, kIOSurfaceColorSpace, space)
            }
            Self.context.render(image, to: small, bounds: size,
                                colorSpace: space.flatMap { CGColorSpace(propertyListPlist: $0) })
            snapshot = small
            Self.snapshots.removeAll { $0 === self }
            Self.snapshots.append(self)
            while Self.snapshots.count > 256 {
                Self.snapshots.removeFirst().snapshot = nil
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

        /// The overview alone showed it: no picture stays (a full-size IOSurface each; the tile has its snapshot), and
        /// its first show fades in again.
        func dropPicture() {
            if still !== layer {
                still?.removeFromSuperlayer()
            }
            still = nil
            layer?.contents = nil
            terminal?.revealed = false
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

        /// An evicted card's: volatile while the view is in no window; back in one, a picture the system took is gone
        /// (it takes them within seconds), and the next reveal fades in as a first one. A kept card's stays, so it
        /// comes back as it was.
        func purgeable(_ volatile: Bool) {
            guard controller == nil, let surface = still?.contents as? IOSurface else { return }
            var old: UInt32 = 0
            IOSurfaceSetPurgeable(surface, volatile ? 1 : 0, &old)
            if !volatile, old == IOSurfacePurgeabilityState.purgeableEmpty.rawValue {
                still?.removeFromSuperlayer()
                still = nil
                // The next reveal fades in, as a first one.
                terminal?.revealed = false
            }
        }

        /// The card leaves view: a copy of its last frame stays over the surface until it draws again. libghostty
        /// frees its swap chain while it does not draw (as Ghostty does for hidden tabs) and empties those IOSurfaces
        /// as it frees them (`kIOSurfacePurgeableEmpty`), so the layer's own picture is gone when the view is in a
        /// window again: a blank frame on every return (CI, phase 27), and lane O's evicted stills came back empty and
        /// faded in. About 2 ms and 17 MB for a full-window card on Retina.
        func keepPicture() {
            guard still == nil, let layer, let surface = layer.contents as? IOSurface, !surface.emptied,
                  let copy = Self.copy(surface) else { return }
            let still = CALayer()
            still.contents = copy
            still.contentsGravity = layer.contentsGravity
            still.contentsScale = layer.contentsScale
            still.frame = layer.bounds
            still.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.addSublayer(still)
            CATransaction.commit()
            self.still = still
        }

        private static func copy(_ surface: IOSurface) -> IOSurface? {
            guard let copy = IOSurface(properties: [
                .width: surface.width, .height: surface.height, .bytesPerElement: surface.bytesPerElement,
                .bytesPerRow: surface.bytesPerRow, .pixelFormat: surface.pixelFormat,
            ]) else { return nil }
            if let space = IOSurfaceCopyValue(surface, kIOSurfaceColorSpace) {
                IOSurfaceSetValue(copy, kIOSurfaceColorSpace, space)
            }
            surface.lock(options: .readOnly, seed: nil)
            copy.lock(options: [], seed: nil)
            let row = min(surface.bytesPerRow, copy.bytesPerRow)
            for line in 0 ..< surface.height {
                memcpy(
                    copy.baseAddress + line * copy.bytesPerRow,
                    surface.baseAddress + line * surface.bytesPerRow,
                    row,
                )
            }
            copy.unlock(options: [], seed: nil)
            surface.unlock(options: .readOnly, seed: nil)
            return copy
        }
    }

    extension IOSurface {
        /// libghostty freed it (`kIOSurfacePurgeableEmpty`), or the system took back a volatile one: its pixels are
        /// gone.
        var emptied: Bool {
            var state = IOSurfacePurgeabilityState()
            setPurgeable(.purgeableKeepCurrent, oldState: &state)
            return state == .purgeableEmpty
        }
    }
#endif
