import AppKit
import HerdrKit

/// The web cards' budget and the cards' pictures.
extension PaneViewRegistry {
    /// The web cards in view now: the ones that left keep a picture, the ones that came show theirs until drawn; past
    /// the `spareWeb` most recently shown others, the oldest are dropped.
    func showWeb(_ shown: Set<String>) {
        for id in webInView.subtracting(shown) {
            webView(id)?.takePicture()
        }
        for id in shown.subtracting(webInView) {
            webView(id)?.coverUntilDrawn()
        }
        // Once the strip scrolled to them: WebKit hears of its view's place in the window only from its own frame or
        // window, so a page the lazy strip made before a jump to it painted one page off (blank, on CI).
        let came = shown.subtracting(webInView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            for id in came {
                // ponytail: deprecated but still WebKit's hook (`WebViewImpl::renewGState` updates its frames).
                self?.webView(id)?.perform(NSSelectorFromString("renewGState"))
            }
        }
        // Also the ones made since the last call (a card is made as its page draws).
        let touched = webInView.union(shown).filter { webView($0) != nil }
        webInView = shown
        Self.recentWeb.removeAll { kept in
            kept.registry == nil || kept.registry === self && (touched.contains(kept.id) || webView(kept.id) == nil)
        }
        // A card made out of view (a page the lazy strip keeps): the oldest.
        let tracked = Set(Self.recentWeb.filter { $0.registry === self }.map(\.id)).union(touched)
        let untracked = Set(browsers.keys).union(plugins.keys).subtracting(tracked)
        Self.recentWeb = untracked.map { Kept(registry: self, id: $0) } + Self.recentWeb
            + touched.sorted { shown.contains($1) && !shown.contains($0) }.map { Kept(registry: self, id: $0) }
        Self.trim(terminals: Self.spare, web: Self.spareWeb)
        prewarm()
    }

    /// The selected tab's neighbors' web cards, made 0.5 s after a tab shows while the strip rests (not under the
    /// overview) and the kept bound has room for the cards in view too, one a turn 0.1 s apart, at their size in the
    /// page: a swipe or a key to them finds them made and drawn (making one took 40 ms of a frame as the strip
    /// rested). They count as the least recently shown. Snapshots of the same tab do not start it again.
    func prewarm() {
        let selected = pages?.current?.selectedTab?.id
        guard selected != prewarmed else { return }
        prewarmed = selected
        prewarming?.cancel()
        prewarming = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, let page = pages?.current, let workspace = page.selectedWorkspace, stripSize != .zero,
                  let index = workspace.tabs.firstIndex(where: { $0.id == page.selectedTab?.id }) else { return }
            let area = Strip.area(stripSize)
            for tab in [index - 1, index + 1].filter(workspace.tabs.indices.contains).map({ workspace.tabs[$0] }) {
                for card in tab.tree.map({ Parts($0, in: area, held: [:]).cards }) ?? [] {
                    guard !Task.isCancelled, !page.stripMoving, pages?.overview != true,
                          Self.recentWeb.count(where: { $0.registry?.droppable($0.id) == true }) + webInView.count
                          < Self.spareWeb else { return }
                    guard let pane = page.store.pane(card.id), pane.plugin != nil, let id = pane.terminalID,
                          webView(id) == nil, !page.floats(pane),
                          let made = pane.browser != nil ? page.browser(pane)?.view : page.plugin(pane)?.web.view
                    else { continue }
                    let inset = pane.browser != nil ? 6 : PaneCard.inset
                    made.frame = CGRect(x: 0, y: 0, width: max(card.rect.width - 2 * inset, 1),
                                        height: max(card.rect.height - page.headerHeight(pane) - inset, 1))
                    made.pictureLoadsOutOfWindow()
                    Self.recentWeb.insert(Kept(registry: self, id: id), at: 0)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }

    /// Down to these many kept cards out of view: the least recently shown go.
    static func trim(terminals: Int, web: Int) {
        while recent.count(where: { !$0.inView }) > terminals, let index = recent.firstIndex(where: { !$0.inView }) {
            recent.remove(at: index).hide()
        }
        let droppable = { (kept: Kept) in kept.registry?.droppable(kept.id) == true }
        while recentWeb.count(where: droppable) > web, let index = recentWeb.firstIndex(where: droppable) {
            let kept = recentWeb.remove(at: index)
            kept.registry?.drop(kept.id)
        }
    }

    /// Out of view, not floating, and with no unsaved edits.
    func droppable(_ id: String) -> Bool {
        !webInView.contains(id) && pages?.floats(id) != true && plugins[id]?.dirty != true && webView(id) != nil
    }

    /// The card goes; its picture stays for its tile and its next card. One with no picture yet (the one asked as it
    /// left view is not there) takes one; the snapshot's reply keeps the web view
    /// until then.
    func drop(_ id: String) {
        let view = webView(id)
        browsers[id] = nil
        plugins[id] = nil
        if let picture = view?.shot.image {
            return keep(id, picture)
        }
        view?.takePicture { [weak self] picture in
            withExtendedLifetime(view) {}
            // Not for a card made again meanwhile.
            if self?.webView(id) == nil {
                self?.keep(id, picture)
            }
        }
    }

    /// A dropped web card's or a chat's picture, while its pane is there.
    func keep(_ id: String, _ picture: CGImage) {
        guard pages?.withFloats.contains(where: { $0.store.panes.contains { $0.terminalID == id } }) == true
        else { return }
        pictures.removeAll { $0.id == id }
        pictures.append((id, picture))
        noted(id)
    }

    /// The card's picture is the newest; past 200 MB of them in the app, the oldest go.
    func noted(_ id: String) {
        Self.pictured.removeAll { $0.registry === self && $0.id == id }
        Self.pictured.append(Kept(registry: self, id: id))
        let bytes = { (kept: Kept) in kept.registry?.picture(kept.id).map { $0.bytesPerRow * $0.height } ?? 0 }
        Self.pictured.removeAll { bytes($0) == 0 }
        var total = Self.pictured.reduce(0) { $0 + bytes($1) }
        while total > 200 << 20, let oldest = Self.pictured.first {
            total -= bytes(oldest)
            Self.pictured.removeFirst()
            oldest.registry?.webView(oldest.id)?.shot.image = nil
            oldest.registry?.pictures.removeAll { $0.id == oldest.id }
        }
    }

    func keptPicture(_ id: String) -> CGImage? {
        pictures.firstIndex { $0.id == id }.map { pictures.remove(at: $0).picture }
    }

    func webView(_ id: String) -> BrowserView? {
        browsers[id]?.view ?? plugins[id]?.web.view
    }

    /// Pictures of these cards' terminals and web cards as they are now (the overview opens).
    func takePictures(of ids: [String]) {
        for id in ids {
            terminals[id]?.takeSnapshot()
            webView(id)?.takePicture()
            if let picture = chatViews[id]?() {
                keep(id, picture)
            }
        }
    }

    /// The web card's or chat's last picture: its overview tile.
    func picture(_ id: String) -> CGImage? {
        webView(id)?.shot.image ?? pictures.last { $0.id == id }?.picture
    }
}
