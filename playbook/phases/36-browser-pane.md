# Phase 36: The browser pane on This Mac

Goal: a pane can be a browser: a WKWebView card with mock-up A's toolbar, Web Inspector in its own window,
and its address kept across relaunches and session restarts. It is the first built-in plugin kind, so the
pane, label and state rules it sets are the ones later plugins follow. Remote machines come in phase 37.

Design: [Browser](../../docs/content/docs/future-work/web-page.mdx), the plugin pages under
`docs/content/docs/future-work/plugins/`, and `resources/research/plugins/browser.md`. The user approved
WKWebView (not CEF), Web Inspector in a separate window, and mock-up A
(`~/Downloads/oriel-research/browser-view.html`).

## Track A: the browser pane (items 1–5)

1. **The pane in herdr.** Picking Browser in the chooser (phase 35), "Open Browser Here" in ⌘K, or a URL
   opened from a terminal link with ⌥ (if it fits) makes the pane a browser: herdr label
   `oriel:browser#<iid> <url>`, and the ~20-line placeholder script in the pane so herdr's TUI shows
   "Browser / url / Shown in Oriel", redraws on resize and ignores keys. Moves, tabs, zoom, floating and
   session restarts keep working because it is a normal herdr pane.
2. **The card.** WKWebView with mock-up A's toolbar (back, forward, reload or stop, the address field with
   ⌘L, the Web Inspector button), loading and error states, the loader then fade-in as in phase 35. One
   `WKWebsiteDataStore(forIdentifier:)` for This Mac. `isInspectable` on every card; the button opens Web
   Inspector in its own window (check `_WKInspector.show` in the running app; Safari's Develop menu always
   works).
3. **State.** A small state file on the pane's machine, keyed by iid, holds the address; Oriel reads it when
   it rebuilds the card (relaunch, session restart, moved pane) and writes it on navigation. The load rule
   from the design (saved URL, else the label's URL).
4. **Kind-aware commands.** "Open Browser Here" hides on a browser pane; ⌘R on a browser pane shows the
   chooser (phase 35's rule for non-terminals); keys that only make sense in a terminal (Find, Insert Path)
   do the browser's own thing or nothing.
5. **Floating** a browser pane works like any pane.

e2e: open a browser from the chooser and the palette on a local test page (a file or a tiny server the test
starts), navigate, relaunch and see the same address, restart the herdr session and see it again, the
herdr label and placeholder text, Web Inspector opens a window.

## Findings
