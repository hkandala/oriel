# Phase 36: The browser pane on This Mac

Goal: a pane can be a browser: a WKWebView card with mock-up A's toolbar, Web Inspector in its own window,
and its address kept across relaunches and session restarts. It is the first built-in plugin kind, so the
pane, label and state rules it sets are the ones later plugins follow. Remote machines come in phase 37.

Design: [Browser](../../docs/content/docs/future-work/web-page.mdx), the plugin pages under
`docs/content/docs/future-work/plugins/`, and `resources/research/plugins/browser.md`. The user approved
WKWebView (not CEF), Web Inspector in a separate window, and mock-up A
(`~/Downloads/oriel-research/browser-view.html`).

## Track A: the browser pane (items 1–6)

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

6. **Agents open plugin panes.** Any agent that can run herdr opens a browser pane next to itself: a new
   pane with the label `oriel:browser#<iid> <url>` (iid: 6 random `[a-z0-9]`, not used by another pane in
   the session) and, optionally, the placeholder script. Oriel shows it from the label alone, local and
   remote. Write the contract (label format, iid rule, args per kind, placeholder optional, file:// only on
   This Mac; remote files go through a server and phase 37's proxy) for the docs pass, and a skill
   (`oriel-panes/SKILL.md`, in pi-hkandala's skills folder; follow its AGENTS.md) with the exact herdr
   commands to split beside the agent's own pane (`$HERDR_PANE_ID`), set the label and start the
   placeholder, and when to use it (show an HTML report, a dev server, docs). e2e: a pane labeled by the
   herdr CLI (not by Oriel) shows the browser with its URL.

e2e: open a browser from the chooser and the palette on a local test page (a file or a tiny server the test
starts), navigate, relaunch and see the same address, restart the herdr session and see it again, the
herdr label and placeholder text, Web Inspector opens a window.

## Findings
