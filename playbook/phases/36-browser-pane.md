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

## Track B: the user's first try (items 7–14)

Captures: `scrawl-1793181414481-118c7.scrawl` and `scrawl-1793181638672-118c7-3.scrawl` in
`~/Library/Application Support/scrawl/captures/`.

7. Clicking the address field does not start editing (⌘L does).
8. One color for every toolbar and card button (the dimmed one), disabled ones dimmer still.
9. Floating a browser pane selects the page's text, every time.
10. Web Inspector opens docked at the bottom of the card by default; its own control detaches it to a window.
11. The state keeps the page's back and forward history too, so it survives a relaunch.
12. An empty browser card turns white when clicked; it must stay the card's color.
13. An empty browser card shows a placeholder icon.
14. ⌘R reloads a browser card; Replace Pane moves to ⇧⌘R everywhere.
15. "Open ‹url›?" reads better: a symbol, "Open this page?", the address (host in full, path dimmed), Open and Not
    Now. No explanation line.
16. An agent changes a browser pane's address in place: a rename of its label to another address loads in the card
    as a new history entry, by the load rule; the skill says how.
17. "Opening Browser…" only while a new card first opens; a typed address shows the progress line alone.
18. A new browser card opens with the keyboard in its address field (a restored one with a page does not).
19. The empty address field says "Enter a URL".

## Findings

### Track A

- **Spike:** `layout.apply` with `label` and `command`, then `pane.move` beside the old pane, works (Replace Pane's
  steps; a failed move closes the new pane). After a session stop and start the label is back on a plain shell with
  a new terminal id; the card is rebuilt from the label and the state file. `_WKInspector show` works in the running
  app but docks under the page; `detach` moves it to WebKit's own window "Web Inspector — ‹page›" only after about
  1 s, so the app retries it until that window shows.
- **Decisions (for the docs pass):** the placeholder shows the address it started with, and nothing for none (the
  chooser and Open Browser Here start with none, and "No page" would stay after the first address); the TUI border
  shows the current label. A web origin is approved for the machine when typed and when a page finishes loading in
  the card (so a relaunch on a page reached by a link loads by itself), the newest 200 per machine; the safe list is
  the design's, plus This Mac's `file://`. A remote machine's `localhost` is not safe until phase 37's proxy (it
  would reach This Mac). Typing an address removes the saved one. Typed `file://` is accepted on This Mac. Popups
  (`window.open`) open over the card with a close button and close on `window.close()`; a `target=_blank` link loads
  in the card. ⌘+ ⌘− ⌘0 zoom the page while a browser card has the keyboard. Web views live in the window's
  registry by terminal id and leave the view tree with their card.
- **Decisions:** the tab title of a browser card is its page's title, else its host, else "New Tab"; the floating
  window's title row shows the label's address. Overview tiles of browser cards show a `globe`. Rename Pane stays
  (a rename that breaks the label turns the card back into a terminal). Open Location ⌘L and Show Web Inspector
  ⌥⌘I are Edit menu commands.
- **Decisions:** the temporary tab of `layout.apply` may show for one snapshot (as the design allows); state files of
  browser panes closed with their tab or replaced go with the 30-day prune. A `mailto:` or app link opens its app.
- **Not built:** Find in the page (⌘F is disabled on a browser card), the ⌥-click on a terminal link, the
  palette's "Open in Browser" row for a typed address, Refresh, and the Inspector button's lit state.
- **Contract (item 6, for the docs pass):** label `oriel:browser#<iid> <url>`; iid 6 `[a-z0-9]`, unique in the
  session, never changed; url `http(s)://` (bare `host:port` gets `http://`), ≤ 1024 characters, no control
  characters, `file://` only on This Mac (remote files through a server); the placeholder is optional; other
  plugins take their kind's argument the same way. The skill `oriel-panes` (pi-hkandala `skills/oriel-panes/`) has
  the exact commands: `herdr pane split "$HERDR_PANE_ID" --direction right --no-focus`, `herdr pane rename`, and
  `herdr pane run … placeholder.sh`.
- **For the user:** a real dev server page (`localhost:3000`) and a login that should persist across relaunches;
  Web Inspector from the button and from Safari's Develop menu; an OAuth popup; the address field's look in light
  mode; a floated browser pane; Increase Contrast on the toolbar.

### Track B

- **Cause (7):** the address field sits at opacity 0 under the shown address while not editing, and SwiftUI gives
  an invisible view no clicks. **Fix:** the shown address takes the click and starts editing.
- **Cause (9):** the address field's select-all went to the first responder; in a new floating window the web view
  had it by then, and selected its whole page. **Fix:** select-all goes to the field's editor only.
- **Cause (10):** WebKit keeps the inspector's last attach state in the app's defaults
  (`__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached`), which the old detach set to 0. **Fix:** no
  detach; the key is removed before each show, so it docks under the page every time; the inspector's own control
  moves it to a window.
- **Cause (12):** an empty web view draws white once clicked. **Fix:** it stays hidden until there is an address,
  under a 44 pt `globe` (13) that gives the address field the keyboard; a first typed address shows the loader.
- **Decisions (11, for the docs pass):** the state file is `{"url", "history"}`: `history` is WebKit's
  `interactionState` (the back and forward list) in base64, left out over 128 KiB; restored with the saved page
  (file:// pages too).
- **Decisions (8, 14):** toolbar buttons take the card buttons' `paneButton` color, at 0.35 when they cannot act.
  Replace Pane is ⇧⌘R everywhere; ⌘R is Reload Page (View menu, palette, floating window) on a browser card.
- **For the user:** float a browser pane (no selection); Web Inspector docked, then its own window control.
- **Decisions (15):** "Open this page?" under a `globe`, the address (host, path dimmed, middle-truncated), Not Now
  and Open; Return and Esc answer while the card has the keyboard. Not Now leaves the page the card had, or the
  empty card with its globe.
- **Cause (16):** herdr sends no event for `pane.rename` (spiked on 0.9.5, also `report-metadata --title`), so the
  app saw an agent's rename only at the next event or the 30 s heartbeat. **Fix:** the skill follows each rename
  with a `pane.report_metadata` token (`oriel-label`, 1 s), whose `pane.updated` makes the app read the layout. A
  card loads a label address that is not its own last one (it keeps the address its own rename replaced, so a
  snapshot read before that rename does not undo it). Design change for the docs pass: an open browser card
  follows its label.
- **Cause (18):** a new card's address field lost its first focus two ways. `layout.apply`'s temporary tab showed
  the new pane for a snapshot, then Replace Pane's hiding took it out again, and the page read that as the pane
  closing and dropped it from the keyboard history, so the keyboard went back to the old card. And SwiftUI focuses no
  view at opacity 0 (the field hid its text by opacity). **Fix:** the replace hides the new pane by its label in
  every tab (the temporary tab no longer shows); the field hides its text with a clear style and retries its focus
  while a just-made card is not in its window yet; a new card (no address) claims the field at once.
- **Decisions (17, 19):** the web view shows from its first commit; until then the globe and the 2 pt progress line.
  The field's prompt is "Enter a URL" (typed words that are no address go nowhere, so no "Search").
- **Cause (CI):** a browser card's header buttons showed on hover and took width from the address field, so the field
  moved under the pointer between the hover and the click (a narrow card on CI's screen). **Fix:** a browser card
  keeps the buttons' room while they are hidden.

