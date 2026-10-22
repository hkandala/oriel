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
`Oriel/Terminal/PaneViewRegistry.swift`.

## Build

### Windows

1. **Scene.** Replace the single `Window("Oriel", id: "main")` with `WindowGroup(id: "main")`, same
   size, toolbar style, resizability and commands. Keep `allowsAutomaticWindowTabbing = false` (no
   window tabs). File ▸ New Window (⌘N, SwiftUI's item) opens a window on the same machine as the key
   window, with one page by the phase 14 first page rule (`-session` in e2e, else `default`).
2. **Machine per window.** The window keeps its machine id in `@SceneStorage` (`this-mac`, the only
   one for now). In the machine menu (phase 13), ⌥-click on a machine opens a new window on it
   (`openWindow(id: "main")` with the machine passed through a one-shot app value); the menu shows no
   item for it. Picking another machine replaces the window's pages with that machine's first page
   (no other machine exists yet, so this path only switches to the same machine and does nothing).

### Shared stores, own selection

3. **One store per session, shared.** An app-level registry holds one `HostStore` per open session
   (key: machine id + session name), with a count of the windows that have it open. A page open in two
   windows uses the same store: one snapshot read path and one event stream per session. The store
   disconnects when the last window closes its page or closes.
4. **Selection per window.** Move the selection out of `HostStore` into a small per-window value per
   page: selected workspace and tab, the keyboard card per tab, the app's zoom (D11). The sidebar view
   (Workspaces or Agents), the sort, the sidebar width and the page in view are per window too. Two
   windows on one session can show different tabs.
5. **Seen (D14)** stays in the store: a pane counts as looked at when any key window shows its tab.
   Notifications, the Dock badge and the Dock menu count each session once, over every window.
   A notification click shows the pane in the window that was key last among those with the page open,
   else adds the page to the front window.

### Control per session (D66)

6. **The controller.** The registry keeps, per session, the window that controls it. The first window
   that opens a session controls it. The window where the user last pressed a key, pasted or clicked
   in a terminal card of that session becomes its controller (D8's triggers).
7. **Streams.** In the controlling window, that session's terminal streams run `control` (D8: the
   first key in the card takes over with `--takeover`). In every other window that shows the session,
   its streams run `observe`, which never resizes the PTY. A change of controller restarts the
   affected streams in both windows (each card keeps its surface; only the stream reopens).
8. **The watching window.** Its cards of that session draw their content at 0.85 of their normal
   opacity, and a bottom capsule (the notice style, centered on the strip, 30 pt above the bottom)
   says "Controlled in another window" with a **Take Back** button. Take Back, or a key press or a
   click in one of its terminal cards, makes this window the controller; the key press is then sent.
   The capsule shows only while the page in view is watched.
9. **Hand-off on close.** When the controlling window closes or closes the page, the window that was
   key last among the others with that page becomes the controller.
10. **Two surfaces for one pane.** `PaneViewRegistry` keys surfaces by window and terminal id, so a
    pane shown in two windows has two libghostty surfaces and two streams (one control, one observe).
    The 24-surface cache is per window.

### Restore

11. `@SceneStorage` per window: the machine id, the open page names and the page in view (phase 14),
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

Two throwaway sessions, `oriel-e2e-<id>-a` (launched with `-session`) and `oriel-e2e-<id>-b`.

- ⌘N: two windows (`app.windows.count == 2`), both on `a`. Window 1 still controls: window 2 shows
  "Controlled in another window" (id `notice.controlled`), window 1 does not.
- Type `echo one` and Return in window 2: window 2 controls (no capsule there), window 1 shows the
  capsule, and window 1's card shows the echoed text (observe works). herdr's PTY size equals window
  2's card size (`expectPTYSize`).
- Take Back in window 1: the capsule moves to window 2.
- Select another tab in window 2: window 1's selected tab stays.
- In window 2, open `b` through the Open Session sheet and close page `a`: no capsule in either
  window; both control their own session.
- Close window 1 while both show `a`: window 2 controls `a` (no capsule).
- Only one events stream per session runs with two windows open (`pgrep` as in `e2e-helper.py`).

## Done when

- Screenshots: two windows on different sessions; two windows on one session, one watching with the
  capsule.
- Window restore after quit and relaunch checked by hand (XCUITest launches with
  `-ApplePersistenceIgnoreState YES`).
