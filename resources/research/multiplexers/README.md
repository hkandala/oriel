# Does Oriel's model fit other multiplexers?

## Answer

Oriel's model fits all three multiplexers that we looked at, each with an adapter. No multiplexer
fits as-is, and none is ruled out.

- tmux fits with an adapter. Nothing in Oriel is impossible on tmux, but the adapter is the largest.
- Rex fits with an adapter. Two things cannot work: a pane cannot move to another workspace, and the
  pane viewport has no shared scroll offset.
- tuios fits with an adapter, and it is the closest to herdr. It already serves herdr's socket API.
  Its best path for Oriel is a hidden bridge with no stability promise.

The four levels under the machine exist in every tool: something like a server, a workspace, a tab
and a pane. So Oriel does not need a smaller common model. The weak level is Oriel's "session" (one
herdr server). Rex has one server per user. tmux and tuios have named servers, but users seldom run
more than one.

Recommendation: keep herdr as the only backend for now, and keep the five-level model. When a second
backend is chosen, make the `Multiplexer` seam in HerdrKit neutral first (option 2 below). If the user
wants one more backend, take tmux for reach, or tuios for the lowest cost. See
[Options for Oriel](#options-for-oriel).

## The reports

| File | Tool | Verdict |
|---|---|---|
| [herdr.md](herdr.md) | herdr 0.9.x | The backend Oriel uses: the baseline |
| [tmux.md](tmux.md) | tmux 3.8 | Fits with an adapter |
| [rex.md](rex.md) | Rex, API revision 5 | Fits with an adapter |
| [tuios.md](tuios.md) | tuios 0.10 | Fits with an adapter |
| [../clients/kero.md](../clients/kero.md) | kero | Ideas to take |

## Mapping table

Each cell names the concept in that tool and how well it fits. "Adapter" means Oriel's adapter must
fake or store it. Each report has the sources and the gaps.

| Oriel level or feature | herdr | tmux | Rex | tuios |
|---|---|---|---|---|
| machine | host, through `Exec` (local or SSH) | host, through `Exec` | host (`server.status`, `hosts.list`) | host, through `Exec` |
| session (sidebar page) | herdr server, `--session NAME` | server, `-L NAME` socket. List the socket folder | the one server per user. Weak: `sessions()` returns one entry | daemon, default or `--server NAME`. List the socket folder |
| workspace | workspace | tmux session `$N`. No order: adapter stores it (`@oriel_order`) | Rex session. Ordered, labeled | tuios session. No reorder: Oriel stores the order |
| workspace git info, worktree groups | `worktree` on the workspace, plus Oriel's own `git` | none. Oriel runs git. Groups in a session option | none. Oriel runs git. No groups | branch and repo in the bridge. No groups |
| tab | tab | window `@N` | window | numbered workspace slot, at most 9 by default |
| pane | pane, plus a terminal id | pane `%N`. Id survives every move | block. Id survives moves inside its session | window. PTY id survives moves |
| split tree with ratios | `layouts` with binary splits and ratios | adapter: converts the n-ary cell layout to a binary tree. One-cell borders | tiled layout: binary, ratios, stable split ids. Floating and detached blocks fall outside | bridge only: binary tree with ratios, for the `bsp` layout. The herdr socket sends no splits |
| agent status | `agent_status`, `completion_seq` | none. Adapter: a pane option set by agent hooks, or polling | OSC 7501 records through the API. Only programs that send OSC 7501. No `completion_seq` | agent state, richer than herdr (errored, Inbox, approvals) |
| notifications | from agent status | bell and activity flags, OSC 133 events | status events, OSC 9 and 777, bell | OSC 9, 777 and 99, bell, attention |
| drag a pane to another tab | `pane.move` | `join-pane`, with left and top drops too | `session.move_block` | `move-window`. A drop beside a pane only through the bridge |
| drag a pane to another workspace | `pane.move`, new pane id | `join-pane` across sessions. Id stays | cannot: blocks never leave their session | `move-window` across sessions |
| drag a pane to a new workspace | `pane.move` `new_workspace` | adapter: 2 to 3 commands | cannot | adapter: 2 steps |
| rename | workspace, tab and pane labels | session and window names. Pane label in `@oriel_label` | labels. A block label cannot be cleared | names on all three levels |
| terminal stream | herdr's own rendering of the screen, as frames | raw PTY bytes (`%output`). Seed with `capture-pane` | raw PTY bytes after a GHOSTSNP snapshot. One stream per block per client | raw PTY bytes after a VT snapshot (`stream-pane` or the bridge) |
| control hand-off between windows and devices | `control` and `observe` streams, takeover | adapter: client flags `read-only` and `ignore-size`, size per window | block owner (`own_block`). Stale owners need `take` | adapter: size leases. No exclusive owner |
| find, read pane text | `pane.read` | `capture-pane` | `terminal.format` (screen and scrollback together) | `capture-pane`, herdr `pane.read` |
| shared scroll offset | `pane.scroll` | none. Oriel scrolls its own surface | none | none |
| focus | Oriel never calls focus. `pane.swap` moves it | no forced focus | create calls need `focus: false`. Swap and move can move it | current workspace is shared state. The bridge must move it to place a pane |
| `Multiplexer.swift` methods | all (the only conformer) | 16 direct, 14 adapter, 2 local, 0 impossible | 22 direct, 8 adapter, 2 impossible | 25 direct or bridge, 3 partly, 2 not available |

Note: the method counts differ a little (30 to 32) because each report counted overloads its own way.

## Verdict per tool

### tmux: fits with an adapter

tmux has every level and every move that Oriel needs. Pane ids survive moves across windows and
sessions, and `%output` carries the raw PTY bytes, which suits libghostty better than herdr's frames.

The adapter must store or fake these things: the workspace order, pane labels, agent status, worktree
groups, the binary split tree (from tmux's n-ary cell layout), the control hand-off, the scroll
offset, the neighbor of a pane (from pane geometry) and the foreground program (from `ps` on the
pane's tty).

The costs:

- A control client sees output and layout events only for its own tmux session. So the adapter runs
  one control client per workspace that Oriel shows.
- tmux sizes windows, not panes. The cards of a tab must add up to one window size, with one cell per
  divider.
- tmux has no agent model. Status needs agent hooks that set a pane option, or polling.
- Flow control: a paused pane loses output and must be seeded again.

### Rex: fits with an adapter

Rex's model is the closest in shape: server, session, window, block, and a binary tiled layout with
ratios and stable ids.

Two things cannot work. A block never leaves its Rex session, so the drop targets "another workspace"
and "new workspace" must not show for Rex. Rex also has no shared scroll offset.

Things an adapter must handle ([rex.md](rex.md)):

- One Rex client can open only one data stream per block. Two Oriel windows on one block need a
  shared stream or two Rex clients.
- A block made by a short-lived CLI keeps its dead creator as owner. The adapter must check
  `client.list` and use `take`.
- A floated block leaves the tiled layout, so it disappears from Oriel's strip.

### tuios: fits with an adapter

tuios publishes its own herdr mapping: herdr workspace = tuios session, tab = tuios workspace, pane =
tuios window. It serves herdr 0.9.5's socket API on `tuios.sock.herdr`. Its `stream-pane` verb sends
raw program bytes after a snapshot, with sequence numbers and resume.

The gaps on the herdr socket: `splits` is always empty, and `layout.set_split_ratio`,
`workspace.move_block`, `pane.scroll` and `terminal.attach` answer `unsupported`. Swap, resize and
split need an attached tuios client. The hidden `tuios gui-bridge` fills these gaps over stdio, which
fits Oriel's `Exec.run`. But it has no stability promise, and the project changes fast (746 commits
in one week after v0.10.1). A tuios session has 9 tab slots by default.

## Options for Oriel

The `Multiplexer` protocol (design D49, `Packages/HerdrKit/Sources/HerdrKit/Multiplexer.swift`)
already keeps herdr's JSON and argv out of the views. But the types and a few files still assume
herdr. This list is what each option must change.

Where the code assumes herdr today:

| File | What assumes herdr |
|---|---|
| `Packages/HerdrKit/Sources/HerdrKit/Models.swift` | `Snapshot`, `Workspace`, `Tab`, `Pane`, `Agent` have only decoding inits for herdr's JSON. `Snapshot.trees` has an internal setter. `Agent.completionSeq`, `Worktree`, `PaneScroll` and `Session.isValidName` are herdr concepts. |
| `Packages/HerdrKit/Sources/HerdrKit/TerminalStream.swift` | Parses herdr's NDJSON frames from a `Channel`. Its init is internal. `Closed` reasons match herdr's error text. |
| `Packages/HerdrKit/Sources/HerdrKit/Exec.swift` | `Exec.herdr()` finds herdr's path. `Channel` gives stdout as UTF-8 lines, not bytes. |
| `Packages/HerdrKit/Sources/HerdrKit/HerdrClient.swift` | `HerdrError` is the error type of `Update.error`. Its messages name herdr. |
| `Packages/HerdrKit/Sources/HerdrKit/Seen.swift` | Finish detection uses `completionSeq`. |
| `Oriel/Store/HostStore.swift` | `State.failed(HerdrError)`. Makes `HerdrClient`. |
| `Oriel/App/OrielApp.swift`, `Oriel/Views/OpenSession.swift` | Make `HerdrClient` directly. |
| `Oriel/Store/PaneWrites.swift` | Throws `HerdrError` with herdr's name in the text. |
| `Oriel/Terminal/PaneTerminal.swift` | Draws herdr's frames. The observe and takeover rules follow herdr's `control`/`observe`. |
| `Oriel/Views/FindBar.swift` | Uses the shared scroll offset (`pane.scroll`). |
| `Oriel/Store/HostModels.swift`, `Oriel/Views/WorkspaceRow.swift` | Worktree groups from herdr's `worktree`. |
| `Oriel/Views/Sidebar.swift`, `Oriel/Views/ListDrops.swift`, `Oriel/App/CommandList.swift` | Offer "move to a new workspace" without a check. Rex cannot do it. |

### Option 1: keep herdr only (recommended now)

Cost: none. The `Multiplexer` protocol stays as it is, with one conformer. This follows Oriel's rule
of no code "for later". The research shows that the model is not a trap: when a second backend
comes, the five-level UI stays.

### Option 2: a neutral backend seam in HerdrKit (recommended when a second backend starts)

Keep the five levels. Make HerdrKit's types neutral and give the app a small capability value per
backend. The work, in order:

1. Public memberwise inits for `Snapshot`, `Workspace`, `Tab`, `Pane`, `Agent` and `SplitNode`
   (`Models.swift`, `SplitNode.swift`).
2. `TerminalStream` as a struct of closures, with two kinds of output: herdr's frames, and raw bytes
   after a seed. All three other tools send raw bytes. `PaneTerminal.swift` then keeps a real
   scrollback for raw streams and drops `FindBar.swift`'s shared scroll.
3. A byte `Channel` in `Exec.swift`. tmux control mode is lines, but Rex's data socket and the tuios
   bridge are binary.
4. A neutral error in place of `HerdrError` (`HerdrClient.swift`, `HostStore.swift`,
   `PaneWrites.swift`).
5. One factory for the backend per machine, in place of the `HerdrClient(...)` calls
   (`HostStore`, `HostModels`, `OrielApp`, `OpenSession`).
6. A capability value that the views read: cross-workspace move (Rex: no), workspace reorder (tuios:
   no, Oriel stores it), many sessions per machine (Rex: no, so the Open Session panel hides), worktree
   groups, tab limit (tuios: 9).
7. A neutral finish marker in place of `completionSeq` (`Seen.swift`): a counter or a timestamp that
   the backend gives.

Guess: steps 1 to 7 take about one week. Each backend adapter then costs more: tuios the least,
then Rex, then tmux (layout conversion, control clients per workspace, agent status).

### Option 3: a smaller common model (session > tab > pane) with herdr-only extras

Cost: high, and the research gives no reason for it. Every tool has a workspace-like level, so the
workspace rows would be lost for nothing. The change would touch the sidebar and its pages
(`Sidebar.swift`, `WorkspaceRow.swift`, `Page.swift`, `WindowPages.swift`), the workspace button and
menu (`TitleBar.swift`), the drop targets (`Drag.swift`, `ListDrops.swift`), the palette
(`Palette.swift`, `CommandList.swift`), the Agents view (`Agents.swift`) and `HostModels.swift`. Not
recommended.

### Which second backend, if one is wanted

| Backend | For | Against |
|---|---|---|
| tmux | The most users, on every server. A stable protocol. Raw bytes. Every move works. | The largest adapter. No agent status without hooks. Size per window. |
| Rex | The closest model shape. Owner per block. | Panes cannot move to another workspace. One server per user. A closed, commercial product. Status only from OSC 7501 programs. |
| tuios | The lowest cost: it speaks herdr's API, and its bridge sends trees and raw bytes. | Young and fast-changing. The bridge is hidden with no stability promise. 9 tabs by default. |

## Decision: stay herdr only

Oriel stays herdr only. These facts settled it:

- **Agent status is part of Oriel's model.** Each pane in the snapshot carries an agent with a status and a
  finish counter (`completion_seq`). The agents list, dots, notifications and the Dock badge come from it.
  herdr finds agents itself.
- **tmux has no agent model.** A tmux backend must make the status itself: agent hooks that set a pane
  option (`tmux set -p -t "$TMUX_PANE" @oriel_status working`, read with `refresh-client -B`, up to 1 s
  late), or detection by polling the pane's program, title and screen text, as herdr does. See
  [tmux.md](tmux.md) section 3.9. Rex gets status only from programs that send OSC 7501. tuios finds agents
  itself.
- **No backend removes the install.** macOS does not ship tmux (Homebrew puts it in `/opt/homebrew/bin`).
  Rex is a separate app, and tuios a separate binary.
- **Bundling herdr would remove it** (in [Future work](../../../docs/content/docs/future-work/index.mdx)). herdr
  is Apache-2.0 (ship its license and NOTICE) and is one 22 MB arm64 binary with no other dependencies:
  - Oriel uses a herdr found on the PATH, else the copy inside `Oriel.app`. The setup screen with the
    install command goes away for this Mac.
  - On first connect to an SSH machine without herdr, Oriel copies a herdr build to `~/.local/bin` there,
    as VS Code Remote installs its server. Linux machines need herdr's Linux build.
  - Costs: about 22 MB more app, and a new herdr needs a new Oriel release, unless Oriel prefers a newer
    herdr already on the PATH.

## Assumptions

- "Fits" means that Oriel's current UI (`docs/content/docs/ui/window.mdx`) works with the tool, with any missing
  data kept by the adapter or by Oriel. It does not mean that every herdr call has a twin.
- The cost guesses assume one developer who knows the Oriel code.
- The tmux facts are for tmux 3.8. Older servers on remote machines lack JSON layouts and floating
  panes, so an adapter must read `#{version}`.
