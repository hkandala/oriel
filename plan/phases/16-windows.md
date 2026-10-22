# Phase 16: several windows

Goal: the user can open several Oriel windows. Each window shows one machine and its own open session
pages. Windows that show the same session share its live data, keep their own selection, and agree on
one controller per session (D66): the window where the user last typed or clicked in a terminal
controls; the other watches and offers Take Back. Windows come back after a relaunch.

Read first: `plan/ui-polish.md`, `plan/ui-layout.md` (windows and machines, sidebar: open pages and
restore), `resources/mockups/layout.html` (scenes E, I, J), `docs/content/docs/talking-to-herdr.mdx`
(terminal plane, one controller per pane, control between windows), `docs/content/docs/data.mdx`,
`docs/content/docs/platform.mdx`, decisions D7, D8, D34, D46, D66, `Oriel/App/OrielApp.swift`,
`Oriel/Store/HostStore.swift`, `Oriel/Terminal/PaneTerminal.swift` (`open(observe:takeover:)`),
`Oriel/Terminal/PaneViewRegistry.swift`, `Oriel/Terminal/PaneSurfaceView.swift`, `Oriel/Views/Strip.swift`
(`SwipeRouter`).

Phase 14 already built the store registry (a dictionary by session name), the per-window page state
(selection, zoom, keyboard card, `arriving`) and one `PaneViewRegistry` per window. This phase adds the
`WindowGroup`, the window counts per store and control.

## Build

### Windows

1. **Scene.** Replace the single `Window("Oriel", id: "main")` with `WindowGroup(id: "main")`, same
   size, toolbar style, resizability and commands. Keep `allowsAutomaticWindowTabbing = false` (no
   window tabs). File ▸ New Window ⌘N: an entry in phase 13's command list whose action calls
   `openWindow(id: "main")`, shown in the `.newItem` group (that group is replaced today, so SwiftUI's
   own item does not exist). The new window has one
   page by the phase 14 first page rule (`-session` in e2e, else `default`).
2. **⌥-click.** In the machine menu (phase 13), ⌥-click on This Mac (read `NSEvent.modifierFlags` in the
   item's action) opens a new window, as ⌘N. `ponytail:` no machine id is stored until remote machines
   exist; then `WindowGroup(id:for:)` and `openWindow(id:value:)` carry it.

### Shared stores, own selection

3. **One store per session, shared.** A page open in two windows uses the same store from the phase 14
   registry: one snapshot read path and one event stream per session. Each store holds `windows`, the
   windows that have its page open, the most recent controller first. An empty list disconnects the
   store and removes it from the registry.
4. **Per window.** The sidebar view (Workspaces or Agents), the sort, the sidebar width and the page in
   view are per window. Two windows on one session can show different tabs.
5. **Seen (D14)** stays in the store: a pane counts as looked at when any key window shows its tab.
   Notifications, the Dock badge and the Dock menu count each session once, over every window.
   A notification click shows the pane in the window that was key last among those with the page open,
   else adds the page to the front window.

### Control per session (D66)

6. **The controller** is `windows.first`. The first window that opens a session controls it. The
   window where the user last pressed a key, pasted or clicked in a terminal card of that session moves
   to the front of `windows` (D8's triggers).
7. **Streams.** On input in a card of session S in window W, W calls `takeBack()` on every shown
   terminal of S. herdr's takeover drops the other window's streams, which reopen as `observe` (D8).
   The store only decides what a newly opened stream does: `observe` when another window controls S.
   Spike: record herdr's close reason on a takeover; it must map to `.held`.
8. **The watching window.** Its cards of that session draw their content at 0.85 of their normal
   opacity, and a bottom capsule (built with the notice view, so phase 21's restyle covers it;
   centered on the strip, 30 pt above the bottom) says "Controlled in another window" with a
   **Take Back** button. Take Back, or a key press or a click in one of its terminal cards, makes this
   window the controller; the key press is then sent. The capsule shows only while the page in view
   is watched. Cards watched because another Oriel window controls the session show no per-card
   "In use elsewhere · Take Back"; that stays for other devices.
9. **Hand-off on close.** When the controlling window closes or closes the page, it leaves `windows`,
   and the next window in the list becomes the controller. The new controller calls `takeBack()` on its
   shown terminals of S (no one else holds them), so the PTY takes its card size.
10. **Two surfaces for one pane.** Each window has its own `PaneViewRegistry` (phase 14), so a pane
    shown in two windows has two libghostty surfaces and two streams (one control, one observe). The
    registries share one count of about 24 streams over all windows (D46). Two statics become per
    window: `PaneSurfaceView.request` (a keyboard claim in one window must not void a claim in another)
    and `SwipeRouter.strip` (look the anchor up from the hit view's window).

### Restore

11. Remove `window.isRestorable = false` (`FullScreenReader`, `OrielApp.swift`), or macOS never
    restores a window. Handle the full-screen title-bar case another way (for example, leave full
    screen in `windowWillClose` or at quit, so a window never restores in full screen). Record what you
    chose. `@SceneStorage` per window: the open page names and the page in view (phase 14),
    each page's selected workspace and tab ids (one JSON string), sidebar open, sidebar view, sort and
    width. macOS restores every window. A restored id that is gone falls back to herdr's focused
    workspace and that workspace's focused tab (reading herdr's focus is fine; the app never sets it,
    D13).

### Docs

12. D34 and D66 already describe several windows; make them and the pages match what you built:
    `platform.mdx` (windows), `data.mdx` (per window storage), `talking-to-herdr.mdx` (control between
    windows, as D66 says), `ui/window.mdx` (New Window, ⌥-click, the watching capsule), the keyboard
    table (⌘N).

## e2e

The tests use the sessions `scripts/e2e.sh` makes: `ORIEL_SESSION` (launched with `-session`) and
`ORIEL_SESSION2`. A test that needs another name adds it to e2e.sh and the helper.

- ⌘N: two windows (`app.windows.count == 2`), both on `ORIEL_SESSION`. Window 1 still controls: window 2 shows
  "Controlled in another window" (id `notice.controlled`), window 1 does not.
- Type `echo one` and Return in window 2: window 2 controls (no capsule there), window 1 shows the
  capsule, and window 1's card shows the echoed text (observe works). herdr's PTY size equals window
  2's card size (`expectPTYSize`).
- Take Back in window 1: the capsule moves to window 2.
- Select another tab in window 2: window 1's selected tab stays.
- In window 2, open `ORIEL_SESSION2` through the Open Session sheet and close page `ORIEL_SESSION`: no
  capsule in either window; both control their own session.
- Close window 1 while both show `ORIEL_SESSION`: window 2 controls it (no capsule), and herdr's PTY
  size equals window 2's card size (`expectPTYSize`).
- With two windows open, the helper's `/children` shows the same count of `remote-api-bridge` runs as
  with one window (the events bridge and request bridges look alike).

## Done when

- Screenshots: two windows on different sessions; two windows on one session, one watching with the
  capsule.
- Window restore after quit and relaunch checked by hand (XCUITest launches with
  `-ApplePersistenceIgnoreState YES`).

## Findings
