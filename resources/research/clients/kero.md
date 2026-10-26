# Kero: terminal panes beside a browser and a changes panel

## Summary

Kero is a desktop app (macOS, Windows, Linux) for running coding agents in terminals. A daemon, `kerod`,
owns the PTYs, the layout and all state. The app is a window onto it, like Oriel is a window onto herdr.
Kero has two pane kinds: terminal and browser. The diff viewer is not a pane. It is a "Changes" side panel
at the right of the selected session, and it follows the worktree of the focused pane. The browser pane is a
daemon pane that has a URL and no PTY. The daemon keeps its place in the split tree and its URL. The app
draws a `WKWebView` (on macOS) in that place. This is the same split of work that Oriel's design D51/D57
already uses for web cards. The best new idea for Oriel is the Changes panel, with its "Last turn" view: a
diff of what the agent changed since its turn started.

## 1. The pane model

### Kinds of pane

Kero has two pane kinds. Both are the same struct, `proto.Pane` (`internal/proto/proto.go:151-211`). There is
no interface, no registry and no kind field. A pane is a browser when its `URL` field is set:

```go
func (p *Pane) Browser() bool { return p.URL != "" }   // internal/proto/proto.go:354
```

- Terminal pane: a shell or a command in a PTY. kerod also runs a headless terminal emulator
  (libghostty-vt) per pane, which keeps the screen and the scrollback (`internal/daemon/session.go:26-30`).
- Browser pane: "the daemon only keeps the place and page of" it (`internal/proto/proto.go:149-150`). kerod
  starts no shell for it (`internal/daemon/sessions.go:229-240`). It refuses input to it
  (`internal/daemon/rpc.go:185`: "pane %s is a browser, which takes no input").

Other surfaces exist, but they are not panes:

- The Changes side panel (`side.go`). Its comment says a Files view (the worktree's tree) "is to join it"
  (`side.go:21-26`). Only Changes exists now.
- An image peek flyout. If you hold Command over an image path that a terminal printed, Kero shows the image
  in a small window beside the path (`peek.go:17-30`, `panes.go:611`).
- The command palette (`palette.go`), the find bar (`find.go`), and the Settings window.

There is no editor pane, no file tree pane and no notes pane.

### Layout

Kero has two levels above panes: projects (folders) and sessions (tasks). There are no tabs and no
workspaces (`docs/sessions.md`). A session is one sidebar row, and it shows its panes side by side. So a Kero
session is about the same as one herdr tab.

The split tree is `proto.Layout` (`internal/proto/layout.go:6-12`): a leaf has `Pane`, a split has `Row`
(side by side, else stacked), `Ratio`, `A` and `B`. It is almost the same as Oriel's `SplitNode`. Kero splits
in all four directions in the tree itself: `Split(at, pane, direction, ratio)` puts the new pane first for
left and up (`layout.go:51-76`). herdr has only right and down, so Oriel needs a swap after a move for left
and top (see `docs/content/docs/ui/drag-and-drop.mdx`).

Other layout operations: `Remove` (`layout.go:80-100`), `Neighbor` by pane centers on a unit square
(`layout.go:104-137`), `Move` as remove then split beside a target at 0.5 (`layout.go:169-178`) and `Swap`
(`layout.go:181-205`). The session also has `Focus` (last focused pane) and `Zoomed` (one pane fills the
session) (`proto.go:252-269`).

The app draws the tree as nested flex rows and columns, with an 8 pt gap that is the divider
(`panes.go:15`, `panes.go:109-139`). A divider drag clamps the ratio to 0.12-0.88 and sends the layout to
kerod only when the drag ends (`panes.go:160-185`).

### Persistence

- kerod saves projects, sessions, layouts and panes in `state.json` in Kero's directory, which is
  `~/Library/Application Support/kero` on macOS (`internal/proto/proto.go:553-566`,
  `internal/daemon/store.go:14-56`). The format is indented JSON, version 2, written atomically
  (`store.go:74-97`, `store.go:114-120`). A save runs 300 ms after a change (`store.go:58-72`).
- Each saved pane has `id`, `dir`, `command`, `url` and `title` (browser only), the agent's own session id
  (to resume Claude Code, Codex, Pi or OpenCode), the last turn's snapshot, `created`, `cols` and `rows`
  (`store.go:37-51`).
- Scrollback goes to `sessions/<id>.vt`, written every 10 s for panes that changed (`store.go:55-72`,
  `store.go:99-112`).
- The app saves only window preferences in `app.json` in the same folder: the selected session, the sidebar
  width, collapsed projects, font size, and the side panel's view and width (`app.go:43-53`, `app.go:171`).
- A browser pane's URL and title go to kerod each time the page commits a navigation or changes its title
  (`browser.go:164-177`, RPC `pane.page`, `internal/daemon/rpc.go:190-202`,
  `internal/daemon/session.go:476-490`). kerod saves them with the pane.

## 2. The diff viewer and the browser pane

### The Changes panel (diff viewer)

The plan is `plans/git.md`. Phases 1 and 2 are built.

Where it sits. The panel is a card at the right of the session's panes. You toggle it with ⌥⌘G
(`internal/actions/actions.go:57`) or with a click on the git chip in a pane header (`branch.go:13-40`). It is
one scroll of all changed files: a sticky header per file, then its diff. A click on a header folds the
file (`plans/git.md`, "As built" under Phase 2, and `side.go:409-560`).

Which worktree it shows. The panel follows the focused pane. It shows the worktree of that pane's
foreground program, else its shell's directory (`proto.Pane.WorkDir`, `proto.go:356-364`). kerod reads the
foreground process's cwd, so an agent that went into a worktree is followed (`proto.go:161-163`,
`internal/daemon/proc_darwin.go:62-69`, `proc_pidinfo`). See `side.go:175-206`.

Three bases, as a segmented control (`side.go:240-262`, `internal/git/diff.go:50-82`):

| Base | Compares | Question it answers |
|---|---|---|
| Last turn | a snapshot of the worktree when the agent last went from idle to working, against now | "What did the agent just do?" |
| Uncommitted | `HEAD` against now, untracked files included | "What is not committed?" |
| Branch | `merge-base HEAD origin/<default>` against now | "What will the pull request hold?" |

The "Last turn" snapshot. When a pane with a known agent goes from idle or error to working, kerod takes a
snapshot (`internal/daemon/session.go:282-296`). The snapshot writes a git tree of the working tree without
touching the user's index (`internal/git/diff.go:20-48`):

```sh
cp .git/index $tmp/index
GIT_INDEX_FILE=$tmp/index git add --all -- .
GIT_INDEX_FILE=$tmp/index git write-tree
```

The tree id goes on the pane as `Turn{Tree, Root, At}` (`proto.go:236-240`) and is saved in `state.json`.
The objects are loose and unreferenced, so `git gc` prunes them later. "Now" is also a snapshot tree, so
untracked files show in every base (`diff.go:108-120`).

Git integration. Kero runs the user's `git` CLI. It does not use libgit2 or go-git (`plans/git.md`,
"Principles"). Every call adds `--no-optional-locks -c core.quotepath=false -c color.ui=false`
(`internal/git/git.go:50-55`). Every diff adds `--no-ext-diff --no-textconv`, so a repository cannot run a
program when you look at it. Commands, with sources:

| Purpose | Command | Source |
|---|---|---|
| Find the repository | `git rev-parse --show-toplevel --absolute-git-dir --git-common-dir` | `internal/git/git.go:85` |
| Branch, upstream, ahead and behind, files | `git status --porcelain=v2 --branch -z --untracked-files=all` | `internal/git/git.go:124` |
| Line counts for the header chip | `git diff --numstat -z HEAD` | `internal/git/git.go:165` |
| Changed files for a base | `git diff -M -z --name-status <rev> <now-tree>`, then `--numstat` | `internal/git/diff.go:119`, `:155` |
| Old text of a file | `git cat-file blob <rev>:<path>` | `internal/git/diff.go:216`, `:266` |
| Branch base | `git merge-base HEAD refs/remotes/origin/<default>` | `internal/git/diff.go:71` |
| Patch for large files and `kero diff` | `git diff -M <rev> <now> -- <paths>` | `internal/git/diff.go:176-180` |

On macOS, Kero runs no git when `/usr/bin/git` is the stub and `xcode-select -p` fails
(`internal/git/git.go:35-41`). Oriel's `GitStatus.usable` does the same check
(`Packages/HerdrKit/Sources/HerdrKit/Git.swift:42-52`).

Refresh. kerod does not watch the working tree. Once a second it stats a few files in the git directory:
`HEAD`, `index`, `MERGE_HEAD`, `rebase-merge`, `rebase-apply`, `packed-refs` and the branch's ref
(`internal/git/git.go:247-265`). It runs `git status` only when that stamp changes, when a pane's status
changes, every 4 s while an agent works in the worktree, and every 30 s otherwise
(`internal/daemon/git.go:16-21`, `:51-53`, `:160-172`). One cache serves every pane in a worktree. After two
timeouts (3 s each) a worktree stops refreshing by itself. In the open panel, the app fetches the file list
again every 5 s while an agent works (`side.go:270-281`). It fetches a shown file's text again with the hash
of the text it has (`Known`), so kerod sends text only when the file changed (`side.go:428-472`,
`side.go:668-692`).

The view. The diff view is MyGo's `editor.DiffView` (`side.go:500`, MyGo `docs/ui/diff-viewer.md`). It is
native-drawn, not a web view. The app feeds it the whole old and new texts, not a patch. With both texts it
can highlight changed words, expand the collapsed lines between changes, and revert one hunk. New text is
applied as one edit, so the scroll position stays (`side.go:694-741`). Files over 1 MB come as a patch and
show without expansion (`internal/git/diff.go:16-18`, `side.go:703-706`). The layout is unified while the
panel is narrow and side by side when it is wide (`side.go:744-752`, setting `diff-layout`). The colors come
from the terminal theme's green, red and yellow, so a diff looks like one printed in the pane beside it
(`side.go:631-655`).

Hunk review. In the Last turn base, each hunk has Revert and Keep while no agent in the session works
(`side.go:754-785`). Revert writes the file through kerod, and kerod refuses when the file changed since it
was shown or when an agent works in the worktree (`internal/daemon/git.go:337-372`,
`side.go:859-880`). Keep hides the hunk, in app memory only.

Not built (Phase 3 and 4 in `plans/git.md`): new session in a new worktree, a close dialog that warns about
unpushed work, "Open Pull Request", "Ask the Agent to Commit", and line comments that the app types into the
agent's pane as one prompt.

### The browser pane

- On macOS the page is a `WKWebView`. MyGo wraps the system web view: WKWebView on macOS, WebKitGTK on
  Linux, WebView2 on Windows (MyGo `README.md`, MyGo `internal/darwin/window.go:360`, `:1471`). It is not
  Electron, not Tauri and not an iframe. MyGo draws it "inside native UI, under the menus and dialogs it shows
  over them" (MyGo `README.md`).
- The app keeps one web view per browser pane in a map, `a.webs` (`browser.go:17-48`, `:59-80`). It drops it
  when the pane closes (`browser.go:179-186`, `panes.go:770-771`).
- The page loads where kerod last had it (`browser.go:136-138`). If the web content process dies, the page
  reloads (`browser.go:135`).
- The user agent gets the suffix `Version/18.0 Safari/605.1.15`, because some sites serve old pages to a bare
  WKWebView (`browser.go:50-57`).
- The address bar is the pane's header (`panes.go:239-241`). ⌘L focuses it. Typed text is a URL or a search
  (`internal/proto/url.go:16-35`). ⌘F finds text in the page. The header shows the site's icon
  (`favicon.go`).
- Ads and trackers are blocked with EasyList and EasyPrivacy, converted to WebKit content rules
  (`internal/adblock/convert.go`, MyGo `internal/darwin/content_rules.go:40-41`, `docs/panes.md`).
- A browser card does not fade when it is not focused, but terminals do (`panes.go:200-204`).
- Agents can drive a page with `kero browser` (click, type, read text, wait, screenshot). The page lives in
  the app, so kerod sends the request to every connected app. The first app that shows the pane answers
  (`internal/daemon/rpc.go:516-578`). With no app open, the call fails.
- Ways to open one: ⌘⇧B, an address typed in the palette (`palette.go:68-71`), and `kero split --url`
  (`docs/panes.md`). A new browser pane splits to the right of the focused pane (`browser.go:208-222`).

A URL clicked in a terminal does not open in a browser pane. Kero's `openLink` returns false for any
`scheme://` link on this Mac, and the terminal opens it with the system (`app.go:936-960`). File paths open
in the default app.

## 3. Terminals and agents

- PTY: Kero's own code, `posix_openpt` style on macOS and Linux (`internal/daemon/pty_unix.go:1-40`,
  `pty_darwin.go`), ConPTY on Windows (`pty_windows.go`). No PTY library.
- Emulator: libghostty-vt, loaded at run time with no cgo, through MyGo's `plugins/terminal`
  (MyGo `plugins/terminal/README.md`, `library.go:15-44`). It is the VT parser only. MyGo paints the cells
  itself on the GPU. It is not a full libghostty surface like Oriel's. Ghostty themes and config keys load
  (`app.go:696-706`).
- kerod runs one headless libghostty-vt per pane. A client that attaches gets frames of that emulator's
  screen, not the raw byte history (`internal/daemon/session.go:26-30`, `internal/client/client.go:313-352`).
  This is the same model as herdr's terminal stream.
- The app keeps at most 12 terminals attached, the most recently shown (`app.go:60`).
- Size between clients: a client "claims" a pane when the user types, scrolls or selects the session in it.
  The pane then takes that client's size (`internal/client/client.go:373-379`, `app.go:756-761`). The app
  claims again when the user comes back to the machine after being away, from the system idle time
  (`app.go:640-683`). This is automatic. There is no "Take Back" button. Oriel's control hand-off is the
  same idea with an explicit button.

Agent awareness:

- Status from the screen. `internal/detect` reads one TOML manifest per agent (Claude, Codex, Pi, OpenCode,
  Gemini, Amp and others). The package comment says: "The rules are herdr's (github.com/ogulcancelik/herdr,
  Apache-2.0)" (`internal/detect/detect.go:1-10`, `internal/detect/manifests/`). So Kero copied herdr's
  status detection. Pane states are idle, working, waiting, error and exited (`proto.go:100-127`).
- Status from programs. Kero reads OSC 7501, the "Program Status Protocol" from Rex
  (https://www.superlogical.com/rex/docs/build/program-status), with states, an id per task, a kind
  (permission, question, auth), progress and a message (`docs/status.md`, `internal/daemon/osc.go`).
  `kero report` writes it.
- Hooks. `kero skill setup` installs a skill and a SessionStart hook for Claude Code
  (`~/.claude/settings.json`), Codex (`~/.codex/hooks.json`), a Pi extension and an OpenCode plugin
  (`docs/agents.md`, `internal/cli/hook.go:22-190`). The hook tells the agent its Kero session and pane,
  asks it to name the session after its task, and tells kerod the agent's own session id. After a reboot,
  kerod resumes that conversation (`proto.go:244-247`, `docs/sessions.md`).
- Notifications on waiting, done and error when the user is not looking. ⌘J jumps to the session that needs
  you. The Dock badge counts sessions that need you (`docs/status.md`).
- Multiplexer integration: none with herdr or tmux. kerod is Kero's own multiplexer. The README names Rex
  and herdr as prior art.

## 4. UI and interaction ideas worth taking

1. The Changes panel, docked at the right of the panes, that follows the focused pane's worktree.
2. The Last turn base, from a snapshot taken when the agent starts working.
3. A git chip in each pane header: branch plus `+N −M`. A click opens the Changes panel. In a narrow card it
   shrinks to the counts, and under 320 pt it hides (`branch.go:13-40`).
4. Cheap git refresh: stat the files in the git directory once a second. Run `git status` only on a change,
   on an agent status change, or on a slow timer.
5. Diff colors from the terminal theme's ANSI green, red and yellow.
6. An address typed in the command palette opens a browser beside the focused pane.
7. Browser pane details: Safari user agent suffix, reload when the web content process dies, address bar as
   the card header, ⌘L, ⌘F in the page, favicon, no fade for web cards.
8. Drop zones on a card: the middle 40 % swaps, else the nearest edge splits. A pill in the zone names the
   action ("Split Left", "Swap") (`panes.go:299-387`). After a move, the moved card springs in
   (`panes.go:256-271`).
9. ⌘J: jump to the next pane that needs you.
10. Hunk Revert and Keep in the Last turn base, and (planned) line comments sent to the agent as one prompt.
