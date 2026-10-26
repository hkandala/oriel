#if os(macOS)
    import AppKit
    import HerdrKit

    /// Oriel marks the panes it shows, so a tool in one knows a click there came through Oriel and asks it to float a
    /// pane instead of opening herdr's popup (talking-to-herdr#float-requests).
    extension HostStore {
        /// The app quits: no pane is shown any more.
        private static var quitting = false
        /// Every store's marks again every 10 s, each store once however many windows show it, apart from git's
        /// pass, which can take longer (D67).
        private static let refresh = Task { @MainActor in
            while await (try? Task.sleep(for: .seconds(10))) != nil {
                all.forEach { $0.markShown(refresh: true) }
            }
        }

        /// Marks its panes in view of a visible window, the shown tab of its page in view there and its floats, and
        /// clears the ones no longer so: the changes, or every one again (`refresh`; a mark lasts 30 s, so an app
        /// that crashed stops claiming its panes). One batch after the other, so a quick hide and show of a pane
        /// cannot land out of order.
        func markShown(refresh: Bool = false) {
            _ = Self.refresh
            guard let client else { return }
            let shown = Self.quitting ? [] : Set(windows.filter(\.visible).flatMap { window in
                window.withFloats.filter { $0.store === self }.flatMap { page in
                    page === window.current ? Array(page.shownTerminals.values) : panes.filter(page.floats).map(\.id)
                }
            })
            let changes = (refresh ? shown : shown.subtracting(marked)).map { ($0, true) }
                + marked.subtracting(shown).map { ($0, false) }
            marked = shown
            guard !changes.isEmpty else { return }
            marking = Task { [marking] in
                await marking?.value
                for (pane, shown) in changes {
                    try? await client.mark(pane, shown: shown)
                }
            }
        }

        /// Clears every mark before the app quits, for at most 1 s: a click in a marked pane meanwhile would ask an
        /// app that is gone, and nothing would open.
        static func unmarkAll() async {
            quitting = true
            all.forEach { $0.markShown() }
            let marks = all.compactMap(\.marking)
            let (done, finish) = AsyncStream<Void>.makeStream()
            Task {
                for mark in marks {
                    await mark.value
                }
                finish.yield()
            }
            Task {
                try? await Task.sleep(for: .seconds(1))
                finish.yield()
            }
            for await _ in done {
                break
            }
        }
    }

    extension WindowPages {
        func markShown() {
            withFloats.forEach { $0.store.markShown() }
        }
    }
#endif
