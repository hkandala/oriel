# Floating panes

Research for the request "speaking of floating panes we should have support
for it as well". It covers two things:

1. herdr's own floating things (popups and overlays) and how the app shows them.
2. Floating panes that the user makes in the app: a scratch terminal, an agent,
   or a plugin pane that floats above the tabs.

- herdr 0.9.3, its source, schema and a throwaway server.
- Labels: **fact** = read in code or docs, or seen in the live test.
  **guess** = not checked.

---

## 0. Answer in one screen

1. **herdr has exactly one real floating object: the popup.** It is a
   terminal drawn as a centred box over the tab. There is at most one popup per
   server. It is **not a pane**: it has no `pane_id`, it is not in
   `session.snapshot`, it sends no events, it is not saved, and herdr does not
   detect agents in it. Its `terminal_id` exists, but only herdr's private
   client socket reports it. The public API can only open it (`plugin.pane.open
   placement:"popup"`, plugin entrypoints only) and close it (`popup.close`).
2. **"Overlay" and "zoomed" are not floating.** Each one is a normal split
   pane in a tab, and herdr then sets that tab's `zoomed` flag. The app already
   shows these as normal cards (D10 ignores herdr's zoom).
3. **So the app cannot show herdr popups in v1.** No public call reveals one.
   herdr-gpui and roamgate show them through the private client socket. That is
   rejected (D6, D20), and roamgate's observer also calls `workspace.focus`,
   which D12 forbids. To fix this, ask herdr to add a `popup` field to
   `session.snapshot`. The app could then stream the popup by its
   `terminal_id`, which works today (§2.4).
4. **Floating panes made in the app are normal herdr panes that live in a
   floating tab.** That is one tab per workspace whose label is `oriel:float`.
   Every pane in that tab floats. herdr keeps the tab, its label and its panes
   across restarts (tested). The app stores nothing except where each card sits
   on the screen and whether the floating panes are shown. Both are kept in
   memory only.
5. **To float a pane:** `pane.move` into the floating tab, or
   `pane.move {type:"new_tab", workspace_id, label:"oriel:float"}` when there is
   no floating tab yet. **To dock it:** `pane.move` into a strip tab. herdr
   closes the floating tab when its last pane leaves (tested). The
   `terminal_id` stays the same, so the stream and the cached view survive.
6. **macOS and iPad:** the card floats inside the main window, above the strip
   and the zoom overlay. It is not a separate `NSPanel`: a second window that
   opens terminal streams breaks D24. **iPhone:** no floating. The floating tab
   shows as one more tab named "Floating".
7. **⌥⌘F** shows or hides the selected workspace's floating panes. If there
   are none, it opens the new-pane picker and the new pane floats. The "⧉ n"
   button at the end of the tab bar does the same, and you can drop a card on it.
8. Every existing rule is unchanged. D7 (one controller per pane), D12 (no
   focus calls), D10 (zoom is the app's), the status area, chat view and pills
   all work, because a floating pane is just a pane.

---

## 1. What floats in herdr 0.9.3

### 1.1 The three "floating" placements

`plugin.pane.open` accepts `placement` = `overlay` (the default), `popup`,
`split`, `tab` or `zoomed` (schema `PluginPanePlacement`;
`src/api/schema/plugins.rs:441`). Custom-command keybindings in the herdr TUI
have matching types: `type = "popup"` and `type = "pane"` (a temporary zoomed
pane) (`src/config/keybinds.rs:112`).

| Placement | What it really is | In snapshot | `pane_id` / `terminal_id` | Saved across restart | Events | Moves herdr focus |
|---|---|---|---|---|---|---|
| `popup` | a single terminal for the whole server, drawn as a centred box (`AppState.popup_pane`) | **no** | no public `pane_id`; `terminal_id` only on the private client socket | **no** | **none** | no, but it is modal for TUI clients on its owner tab |
| `overlay` | a split of herdr's **focused** pane, then that tab gets `zoomed = true`; when its process exits, herdr restores the old focus and zoom (`App.overlay_panes`, kept in memory) | yes, a normal pane; `layouts[].zoomed: true` | yes, both | the pane is saved like any pane; the "restore when done" record is not | `pane.created`, `layout.updated`, `pane.focused`, `tab.focused`, `workspace.focused` (live test) | **yes** |
| `zoomed` | a split of `target_pane_id`, then the tab is zoomed; it stays open | yes; `zoomed: true` | yes, both | yes | as for a split, plus focus | **yes** (`src/app/api/plugins/panes.rs:119-160`) |

Facts from the live test on 0.9.3:
- `plugin.pane.open {placement:"popup"}` returned `{"type":"ok"}`, with no pane
  information. The snapshot and `pane.list` did not change. The event stream
  (workspace, tab, pane, layout and focus events) sent nothing.
- A second popup open returned `ui_busy` "a popup pane is already open".
- `popup.close` returned `ok`. A second `popup.close` returned
  `popup_not_open`.
- An overlay open returned `plugin_pane_opened` with a full pane (`w1:p4`,
  `label: "Ov"`, which is the manifest pane's `title`). The snapshot showed
  `zoomed: true` and `focused_pane_id` = the overlay. `pane.move` of the
  overlay returned `changed:false, reason:"zoomed_tab"`.
- A popup placement with `width` on a non-popup placement returns
  `invalid_params` "width and height are only supported when placement is
  popup".

### 1.2 The popup in detail (source)

- **One per server.** `spawn_popup_command` refuses with "popup already open"
  (`src/app/popup.rs:116`).
- **Context is herdr's focus.** It uses `state.active` (herdr's focused
  workspace), its active tab and focused pane for the cwd (`popup.rs:119-136`).
  `overlay` and `popup` refuse `workspace_id`, `target_pane_id` and
  `direction`: "overlay and popup plugin panes target the active pane"
  (`src/app/api/plugins/mod.rs:505-515`).
- **Size:** `width` and `height` are cells or `"N%"` of the terminal area,
  including the border. The default is half the area, at least 6×4, and the
  box is centred (`src/popup_size.rs:50-80`).
- **Agents are never detected in it.** It is spawned with
  `AgentDetection::Disabled` (`popup.rs:54, 85`).
- **Owner tab.** The server remembers `popup_owner_tab_id`: the tab of the TUI
  client that opened it, or the default shell target. Only TUI clients on that
  tab see it. Their pane input and clipboard paste are blocked while it is open
  (`src/server/headless.rs:1189, 2000, 2379`). If the owner tab closes, herdr
  closes the popup (`src/server/headless/client_views.rs:128-141`).
- **Closes** when its process exits (`PaneDied` → `close_popup_pane`,
  `src/app/api.rs:209-218`), on `popup.close` (`api.rs:1209`), or when its owner
  tab goes away.
- **Not saved.** `src/persist/` has no popup state. herdr's docs say: "A popup
  is a singleton session resource rather than a Herdr pane: it has no pane ID,
  … emits no pane lifecycle events, and does not participate in pane, layout,
  persistence, or agent APIs" (`docs/next/website/src/content/docs/plugins.mdx:332`,
  also https://herdr.dev/docs/plugins/ and https://herdr.dev/docs/socket-api/).
- Added in herdr 0.7.4: "session-modal popup floating terminal panes for
  `type = "popup"` custom command keybindings and plugin panes" (CHANGELOG,
  #1125).

### 1.3 How the herdr TUI draws it
The TUI composites the popup over the tiled tab as a bordered box at
`resolve_popup_geometry(width, height, terminal_area)`. While a direct attach
holds the popup terminal, the box resizes its PTY only if no resize lock is set
(`src/ui/panes.rs:524-550`). Toasts and Kitty images are cropped around the box
(CHANGELOG 0.9.x). On the private client protocol the popup arrives as
`PaneSurfaceFrame.popup: ClientShellPopupSurface {terminal_id, title, width,
height, frame, …}`, and input goes back as `ClientShellPopupInput {terminal_id,
events}` (herdr-gpui's copy of the protocol:
`crates/herdr-protocol/src/wire.rs:188, 544-580`).

### 1.4 Can `herdr terminal session control/observe` target a popup?
- **Yes, if you know its `terminal_id`.** The server looks the target up in
  `state.terminals`, and that map holds the popup terminal
  (`terminal_id_by_string`, `src/server/headless.rs:1079-1104`). herdr's own
  invariant check says the popup terminal is in `terminals` but not attached to
  a tiled pane (`src/app/state.rs:1290`). `resize_popup_pane` honours
  `direct_attach_resize_locks`, so a `control` stream keeps our size.
  roamgate does exactly this: "the popup terminal uses direct attach"
  (`roamgate/docs/ARCHITECTURE.md:103`).
- **But the public API never gives that id.** `plugin.pane.open` returns
  `ok`, the snapshot leaves it out, no event carries it, and ids are
  `term_<micros><counter>` (`src/terminal/id.rs:16`), so it cannot be guessed.
  Not tried live, for this reason.

### 1.5 Events
None for popups. The event list (`src/api/schema/events.rs`) has no
popup or overlay kind. Overlays send the normal pane, layout and focus events.

---

## 2. What others do

### 2.1 herdr plugins that "float"
| Plugin | How | Persistence |
|---|---|---|
| **Tyru5/herdr-floax** (`d6b2831`, targets herdr 0.7.1) | No popup existed then. Its toggle action opens a `split` plugin pane labelled `⌂ floax`, then calls `pane zoom --on`. A Rust TUI inside it draws a centred box over a solid backdrop and hosts a shell PTY. It finds "its" pane by label in the workspace: none → open; open but not focused → `pane zoom --on`; focused → `plugin pane close`. The README says overlay/zoomed "vanish when opened from a keybinding action" on 0.7.1 (**not checked on 0.9.3**; the live overlay above stayed open) | the shell runs inside `dtach`/`abduco`/`tmux`, one session per workspace (`scripts/floating-shell.sh`), so closing the pane only detaches |
| **meerzulee/herdr-float** (`6301b7e`, ≥0.7.4) | native `placement = "popup"`, 86%×82%; the toggle action checks that herdr's focused workspace is the one asked for, otherwise "Space changed" | one tmux session per Space; a `workspace.closed` event hook cleans up |
| **jeromychu23/herdr-popupx** (`84a5ea3`) | popup, 85%×80%, workspace or session scope | its own detach helper |
| **maro114510/herdr-toggle-popup** (`a34d8c6`, ≥0.9.0) | popup 100%×100% plus tmux | tmux |
| **coryshaw1/herdr-cliamp** (`8963932`) | popup that runs `herdr --session cliamp attach`: a hidden herdr session holds the player | the hidden herdr session |

The lesson: herdr's popup is short-lived by design. Every "persistent float"
plugin keeps its state in a second multiplexer (tmux, dtach, or a hidden herdr
session) behind the popup. herdr-floax shows the other way: a **real pane found
by a label marker**. That pane is persistent, movable and agent-detectable.

### 2.2 Other clients
| Client | Popups | Overlays / zoom |
|---|---|---|
| **herdr-gpui** (`3871183`) | Speaks the private client protocol, so it gets `surface.popup` and paints it centred over the grid (`window/render.rs:459`, `terminal.rs:66-125`). Input goes to the popup, and pane menus, find, copy mode and splits turn off while one is open | herdr's server-drawn layout, zoom included |
| **roamgate** / herdr-studio (`4476392`) | Keeps one extra private-socket "endpoint observer" open only to learn popup identity. It calls `workspace.focus` so the popup follows the browser's Space (`server/src/bridge/terminal-bridge.ts:290-360`). It draws `PopupOverlay.tsx` (xterm.js) sized from herdr's cells-or-percent, streams the popup over direct attach, and closes it with `popup.close`. Its toggle tries `popup.close` first and invokes the `herdr-float` action on `popup_not_open` (`web/src/store.ts:3912-3960`) | normal panes |
| **bigtty** (`2c20e1f`) | none | follows herdr's `layout.zoomed` and shows herdr's focused pane full size (`MainWindowController.swift:533`) |
| **herdr-web-ui** (`4f074f4`) | none | normal panes |

Nobody shows herdr popups through the public API, because they cannot.

---
