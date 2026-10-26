# Phase 16: several windows

Goal: the user can open several Oriel windows. Each window shows one machine and its own open session
pages. Windows that show the same session share its live data, keep their own selection, and agree on
one controller per session (D66): the window where the user last typed or clicked in a terminal
controls; the other watches and offers Take Back. Windows come back after a relaunch.

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

## Findings

### Deviations

- **The control capsule is in `Detail`, built on a new `Notice` view** (`Oriel/Views/Detail.swift`): the failed-write
  notice and the capsule are the same capsule (text, optional action, glass), stacked 30 pt above the strip's bottom,
  so phase 21's restyle covers both. The old notice sat 16 pt above; the design says 30.
- **Control moves every stream of the session, not only the shown ones.** On a control change the new controller's
  observing streams of the session take over (recent tabs too) and the other windows' control streams reopen as
  `observe`. Taking back only the shown tab's streams left the old controller holding the recent tabs' panes: the new
  controller's next tab then opened `control`, was refused, and showed "In use elsewhere". A card held by another
  device is taken over too when a window takes the session (D66: "that window opens its streams again as control").
- **The dim is `alphaValue` on the terminal's host view, not SwiftUI's `opacity`.** `.opacity` moved the terminal's
  accessibility frame half a card down, so XCUITest's click at its center landed in the card's padding.
- **Full screen is left after a restore, not at quit.** Leaving full screen in `applicationShouldTerminate`
  (`.terminateLater`, reply after `didExitFullScreen`, even with `invalidateRestorableState`) still restored the window
  in full screen: AppKit had saved the state before. Now the window reader, which joins once the window shows its first
  page, toggles full screen off when the window is already in it then (only a restore can do that before the user
  acts). `window.isRestorable = false` is gone. Only windows that were in full screen when launch ended
  (`AppDelegate.restoredFullScreen`) leave it, so a ⌘N window macOS opens in full screen from a full-screen window
  stays there (spec review).
- **The app keeps running with no window**, as Mac apps with `WindowGroup` do (the old `Window` scene quit with its
  window). Closing the last window disconnects every store; the Dock icon opens a new window.

### Decisions

- **Spike (herdr 0.9.5):** a `control --takeover` closes the other client's `control` stream with
  `{"type":"terminal.closed","reason":"terminal attach taken over"}` (already `.held` in `TerminalStream.Closed`); an
  `observe` stream stays open through a takeover; a refused `control` says "terminal attach failed: terminal … already
  has an attached client; retry with --takeover"; a stream whose stdin closes ends with "detached".
- **`HostStore.windows: [WindowPages]`** (macOS only, observed): the windows with the page open, the controller first.
  `WindowPages.control(store)` moves a window to the front and switches the streams; `leave(store)` (Close Page, window
  close) hands control to the next window or, the last one gone, removes the session's notifications and disconnects
  the store. `Page.watched` is `store.windows.first` being another window (compared by registry). The store calls
  `snapshotted(changes)`: each window settles its page, and notifications post once, with the controller's page.
- **Input hook:** `PaneTerminal.onInput` (key, paste, mouse down) → the registry's `onInput(terminalID)` → the window
  of that terminal's page takes control when it watches. A new stream asks `watches()` (the registry → the window's
  page) and opens `observe` while another window controls; takeovers never watch. A reopen after `.held` or a live
  update checks the stream generation first, so a reopen that control overtook does nothing; a live-update reopen keeps
  its mode, so a card another device holds stays a watcher (D8). A window that loses control drops keys it had not
  sent yet. A window closed while it restores opens nothing, and a closed window drops its page in view.
- **D46 shared:** one static `recent: [PaneTerminal]` over every registry; a terminal its window shows (`inView`) is
  never evicted, so a tab with more panes than 24 keeps them all, as before. A pane in two windows counts twice.
- **Per-window statics:** the keyboard claim counter became a per-view `claimed` flag the registry drops on its own
  views (`dropClaim`), so a claim in one window never voids one in another; `SwipeRouter.strip` became a weak
  `NSHashTable` of anchors, picked by the scroll view under the pointer.
- **Window registry:** `WindowPages.windows`, the window that was key last first (`look(key:)` moves it), for
  notification clicks (the last key window with the page, else the front window, which is brought forward with
  `makeKeyAndOrderFront`), the Dock menu's New Tab and a click that started the app (`early`). `WindowPages.main` is
  gone. The Dock menu and the badge read `HostStore.all` (each session once).
- **Seen across windows:** `look(key:)` sets a store's looking tab from the key window; a window that stops being key
  clears only stores no key window shows, as the two windows' calls come in either order.
- **Scene storage:** `selection`, one JSON string `{session: {workspace, tabs: {workspace: tab}}}` (sorted keys, so
  the same selection is the same text and `onChange` does not loop). With `-session`, the selection of that session
  still comes back.
- **Window close:** `NSWindow.willCloseNotification` in the window reader (now `WindowReader`, which also hands the
  window to `WindowPages.window`), not `onDisappear`.
- **⌥-click:** the This Mac toggle's setter reads `NSEvent.modifierFlags`; a plain click does nothing, as before.
- **Files:** `WindowPages` moved to `Oriel/Store/WindowPages.swift` and `Detail` to `Oriel/Views/Detail.swift`, and
  `PaneTerminal`'s font statics to an extension: SwiftLint's file and type length limits.
