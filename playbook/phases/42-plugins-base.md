# Phase 42: Default plugins: the shared spec and base

Goal: five default plugins (File, Preview, Markdown, Diff, Files) built twice with the same features, once with
native views ([phase 43](43-plugins-native.md)) and once with web components ([phase 44](44-plugins-web.md)), so the
user can try both and choose. This phase is what both share: the feature spec below, the plugin plumbing, and the
file and git data. Research: `resources/research/plugins/default-plugins.md` and
`~/Downloads/oriel-research/plugins.html` (its Mockups section has the recommended layouts).

## The user's words

"let's also work in parallel on other plugins, so for these other plugins its hard for me to decide between webview
and native ones, so let's create two branches one with webview impl and one with native impl with similar features,
at the end of all tracks and everything, i want all the fixes i mentioned to be on master, and from that latest
commit on master i want two branches pushed with impl for all other plugins one with native and one using web
components"

- "file viewer and editor - let's go with your recommendation, jump bar header, but two rows like chat and browser,
  let's go with two row header for all plugins by default, and file can be editable, shows an indicator when there
  are dirty changes and cmd+s saves the file, file should auto reload from disk on changes unless there are dirty
  changes, that time, we show small flaoting toast kinda thing saying whether to reload or not"
- "generic file viewer for images, pdf etc like you recommended, see how to design this, we can keep each file type
  viewer as one plugin, that way user can also control what to enable/disable later, so essentially one plugin for
  all file types we support"
- "markdown viewer/editor same like file viewer/editor, both read and edit, show dirty indicator, auto reload except
  when dirty changes are present, include option to open or collapse outline sidebar"
- "diff view - go with your recommended option with option to toggle between unfied or side by side and also a button
  to expand/collapse file list, and drop down to choose uncommitted, vs recent commit list"
- "file explorer - let's just show full file tree, with filter option at top to filter files, no full file search is
  needed, and if its git repo let's have a collapsed one at the bottom of file tree similar to vs code, and expanding
  it should show current changes and a simple git history graph, we don't need a dedicated git history plugin, and
  these plugins should be linked, what i mean is from file explorer, if we cmd click or double click on any file it
  should open that file in new tab using its corresponding file viewer or makrdown viewer/editor plugins. and same
  with git view from the git history if we cmd+click or double click paricular commits, it should open our diff view
  plugin with that commit selected, and from diff view plugin we should be able to go to full file viewer/editor
  plugin, essentially use cmd+click or explicit button to open etc link all plugins where possible."
- "if the device is local, then within file viewer/editor or makrdown we should have option to open with default app
  or list of apps to choose from"
- "no need of cmd+k changes to go to or open a given file for now"
- "similar feature set, but ui look can have slight differences, feature parity should be same betwen the two
  branches"

## Branches

- `plugins-base` (local): this phase, from main. Phase 43 and 44 branch from it as `plugins-native` and
  `plugins-web` (local). Track branches merge into their integration branch with a fast-forward:
  `git rebase <integration> && make lint build test && git push . HEAD:refs/heads/<integration>`.
- Phase 41 and this phase run at the same time; phases 43 and 44 start together when this phase's tracks are on
  `plugins-base`. None of them waits for phase 41.
- CI: no pushes along the way. Each track runs its own UI tests once, at its end (one chosen-tests run on a tag,
  deleted after); each branch gets one full run at the end.
- Code: the ponytail rules hold here as everywhere: the least code that does the spec, no layer, protocol or option
  for a later plugin, no copied logic between kinds.
- At the end, after phase 41 is all on main: each integration branch rebases on main's last commit, gets its docs
  pass, a final review, a parity review across the two, and a full CI run (`gh workflow run ci.yml --ref <branch>`).
  Then the orchestrator pushes `plugins-native` and `plugins-web` to origin (the user asked for these two remote
  branches; nothing else goes remote). main never gets plugin code in this phase.

## The spec (both variants build all of it)

**Every plugin pane.** A herdr pane labeled `oriel:<kind>#<iid> <arg>` (as the browser), restored after a relaunch or
a session restart, on This Mac and on remote machines (through `Exec`). Two header rows like the browser and agents:
row 1 the kind's icon, the title, a dirty dot when unsaved, the state, and the pane buttons on hover or the active
card; row 2 the kind's controls. The tab and the floating window read `‹Kind› ‹title›` (` | ` in plain text, phase 41).
Linked opens go to a new herdr tab next to the current one, in the same workspace, on the same machine.

| Kind | Label arg | Title | Row 2 |
|---|---|---|---|
| `file` | path | file name | jump bar `folder › file › symbol at the caret`; Open With ▾ (local only) |
| `preview` | path | file name | the path; zoom (Fit, −, +) for images and PDF, page `n of m` for PDF; Open With ▾ (local only) |
| `markdown` | path | file name | `Read \| Edit`; outline sidebar toggle; Open With ▾ (local only) |
| `diff` | repo root, source | `Changes` / short hash | source pop-up (Uncommitted, then the last 50 commits); `Unified \| Side by Side`; file list toggle; previous / next change |
| `files` | root | the root's name | filter field; collapse all |

**Which kind opens a file:** `.md`, `.markdown`, `.mdx` → markdown; images, PDF, audio and video → preview; text →
file; anything else → preview (an icon, name, size and Open With).

1. **File.** An editable text view: syntax colors for about 15 languages (Swift, TypeScript, JavaScript, Python, Go,
   Rust, C, C++, Java, Kotlin, Ruby, shell, JSON, YAML, TOML, HTML, CSS), line numbers, the current line lit, find
   (⌘F), undo. The dirty dot shows on an edit; ⌘S saves, checked by hash: if the disk changed since the load, the
   toast offers Overwrite or Reload. A change on disk reloads the file when it is clean; when it is dirty, a small
   toast at the card's top offers Reload or Keep Mine. Caps: 4 MiB to edit on a remote machine, 16 MB to view
   (above it: read only, then the preview's info view).
2. **Preview.** Images (fit, zoom, actual size), PDF (pages, zoom, page `n of m`), audio and video (the system
   player). Other files: icon, name, size, kind and Open With. Reloads on change.
3. **Markdown.** Read mode (rendered, links open in the browser plugin or the right plugin for a relative path) and
   Edit mode (edits the file's own text, a live preview of the marks around the caret). ⌘E toggles. The outline
   sidebar (headings, click to jump) opens and closes from row 2. Dirty, save, reload and the toast as File.
4. **Diff.** One unified scroll with a sticky header per file (disclosure, `+n −m`, Viewed), or Side by Side; a file
   list column that row 2 opens and closes; word changes marked inside lines. Each file header has an Open File
   button (the file plugin in a new tab); ⌘-click on a line opens the file at that line.
5. **Files.** The whole tree of the root (the git repo's root when the pane's folder is in one, else the folder),
   folders opened on demand, git letters and colors, ignored files dimmed. The filter field shows matching files
   with their folders. Double-click or ⌘-click on a file opens it in a new tab with its kind. At the bottom, when the
   root is a git repo: a collapsed `Git` section (VS Code's place) with Changes (double-click or ⌘-click: the diff,
   Uncommitted, at that file) and History (a graph of the last 100 commits; double-click or ⌘-click: the diff with
   that commit).
6. **Open With** (This Mac only): the default app, then the other apps that open the file (`NSWorkspace`).
7. **Ways in:** the new-pane chooser gets `Files` and `Changes` rows under Browser; ⌘K gets Open Files Here and Open
   Changes Here. File, Preview and Markdown open from the links.
8. **Not in this phase:** a ⌘K Go to File, project search, git actions (stage, commit), ⌘-click on a path in a
   terminal, Quick Look for every other file type (both variants show the info view instead, for parity).

**Parity.** Both variants share every native part (the header rows, the plumbing, the data) and the accessibility
identifiers of the header controls. Only the content area differs. Each variant's tests cover every numbered item.

## Track A: plugin plumbing (items 1–3)
1. The plugin kinds (`file`, `preview`, `markdown`, `diff`, `files`) as values like the browser's: label, creation
   (`layout.apply` + move + close, with a placeholder), restore, close, Replace Pane, the two-row header frame with a
   row-2 slot per kind, the dirty dot, tab and floating titles, the toast view (top of the card, one line, two
   buttons), Open With, the chooser rows and ⌘K items, and one `Page.open(kind:arg:)` that makes the new tab.
2. Each kind's content is a placeholder view the variants replace.
3. UI tests: open each kind from the chooser, ⌘K and `Page.open`; the label survives a restart; the dirty dot.

## Track B: file and git data in HerdrKit (items 4–6)
4. `Files`: list a folder (`ls -1Ap` style, ignored and git state from `git status --porcelain=v1 -z` and
   `git check-ignore`), read (`cksum` + `base64`, caps), save (stdin, hash check, atomic `mv`), watch (local: a file
   system source; remote: a poll every 2 s while a card shows).
5. `Git`: repo root, status, log with parents for the last 100 commits, the lane layout for the graph, the patch for
   Uncommitted or one commit (`git diff -M`, `git show -M`), parsed into files, hunks and lines, word changes.
6. Check that the relay passes NUL bytes from `-z` output unchanged (research open question 7); if not, use a
   newline-safe form. Unit tests on real output from this repo.

## Findings

### Track A

- **Decisions:** `PluginKind` holds the browser too, so one label, placeholder, creation (`layout.apply` + move +
  close), close and Replace Pane path serves all six; `Pane.plugin` (any kind's label) replaced every
  `browser != nil` check that means "runs only a placeholder". The other five kinds share one `Plugin` card object
  per pane (kind, label, `dirty`, `toast`, `wantsKeyboard`), kept by terminal id as browsers are; variants hang their
  state on it and replace the arms of `PluginCard` (content) and `PluginToolbar` (row 2).
- **Decisions:** label args: `files` = root, `file|preview|markdown` = absolute path, `diff` = `<root> <source>` with
  the source the last word (`uncommitted` or a hash). Titles come from the label alone (`PaneLabel.title`), so menus
  build no card. The diff's kind name is `Diff` (tab `Diff Changes`); the chooser row and ⌘K say Changes.
- **Decisions:** Files and Changes take the git root of the pane's live folder (`Git.root`, only when This Mac's
  git check passed, inside Replace Pane's write so a second pick cannot start a second replace), else the folder.
  "Which kind opens a file" is left to the first variant track that opens one (no caller here).
- **Decisions:** `Page.open(_:arg:)` makes the tab with `layout.apply`, then `tab.move` to right after the selected
  tab (herdr adds it last; spiked: no focus change), and selects it on the next snapshot.
- **For the variants:** each placeholder has an `Open in New Tab` button (it drives `Page.open` in the test) and file
  and markdown an empty editor that sets `dirty`; replace both. A content view takes the keyboard on
  `plugin.wantsKeyboard` and calls `page.tookKeyboard` when it gets it, as the placeholder does.
- **For the variants:** Find (⌘F) is off on every plugin pane and a disabled menu item swallows its key: enable it
  (and add ⌘S, ⌘E) for the kinds that use them. `Page.swift`, `HostStore.swift`, `FloatingPane.swift` and
  `PaneCard.swift` are near the 400-line limit: split before adding.
- **For the user:** Open With ▾ lists the default app first; check its icons and that it is absent on a remote
  machine.
