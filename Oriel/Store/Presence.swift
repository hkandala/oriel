#if os(macOS)
    import HerdrKit

    /// Oriel marks the panes it shows, so a tool in one knows a click there came through Oriel and asks it to float a
    /// pane instead of opening herdr's popup (talking-to-herdr#float-requests).
    extension HostStore {
        /// Marks its panes in view of a visible window, the shown tab of its page in view there and its floats, and
        /// clears the ones no longer so: the changes, or every one again (`refresh`; a mark lasts 30 s, so an app
        /// that quit or crashed stops claiming its panes). One batch after the other, so a quick hide and show of a
        /// pane cannot land out of order.
        func markShown(refresh: Bool = false) {
            guard let client else { return }
            let shown = Set(windows.filter(\.visible).flatMap { window in
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
                await withTaskGroup { group in
                    for (pane, shown) in changes {
                        group.addTask { try? await client.mark(pane, shown: shown) }
                    }
                }
            }
        }
    }

    extension WindowPages {
        func markShown(refresh: Bool = false) {
            withFloats.forEach { $0.store.markShown(refresh: refresh) }
        }
    }
#endif
