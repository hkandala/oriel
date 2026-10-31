# Phase 47: The plugin system

Goal: every plugin is a package (a `package.json` with an `oriel` key, TypeScript and its own `node_modules`), as pi's
packages are, that Oriel installs, builds with the esbuild it ships,
loads in a web view and connects to the card's machine through one typed `oriel` object. File Explorer and Git move
onto it and behave exactly as they do on main after phase 46. Every plugin, the two default ones too, is installed in
`~/.config/oriel/plugins/` (or loaded from a local path), and a user or an agent can edit it, then reload.

Design: [Pane kinds and plugins](../../docs/content/docs/future-work/plugins/index.mdx) and its pages (manifest,
api, building, security, browser-and-native, labels), approved by the user with the decisions below. The built
behavior of the two plugins: [Default plugins](../../docs/content/docs/ui/plugins.mdx). Where this file and a design
page disagree, this file wins; the docs pass moves the pages from future-work to the built pages.

Branch: everything lands on `plugin-system` (on origin, made from main after phase 46). A track branches from
`origin/plugin-system` and merges into it (rebase, `make lint build test`, `git push origin HEAD:plugin-system`). CI:
`gh workflow run ci.yml --ref plugin-system` (or a tag on a track's head). main stays untouched until the user says
merge.

## Decisions (the design's open questions, settled)

1. **One plugin, many places.** A plugin draws every place of its card itself: File Explorer's tree, File, Preview
   and Markdown; Git's home and diff. `oriel.card.go(arg)` moves the card to a new place (the label follows, as
   today); the app keeps Back and Forward per card and draws them when the manifest says `"history": true`;
   `on("place")` tells the page where it is after Back, Forward or a rename from elsewhere. Heavy views load with
   dynamic `import()` (esbuild splitting), so a tree card does not load CodeMirror or pdf.js.
2. **Header controls** are declared in the manifest and drawn natively: button, toggle (in the accent while on),
   segmented (the app's pill segments), menu (items set by the page), field, text, spacer, plus two the app fills:
   `openWith` (the default app's icon, a menu of apps with icons, for a path the page sets) and the Back/Forward pair
   from decision 1. `oriel.controls.set(id, …)` changes a control's value, title, badge, items, enabled or hidden
   state, so one header serves every place of the card.
3. **API additions** the two plugins need, beyond the api page: `card.go`, `card.ready()` (ends the loader),
   `card.setDirty(bool)` (the Edited dot; the app asks Discard / Keep Editing on a move or close), `menu.show(items)`
   (the native context menu at the pointer), `pick.folder()` (Choose Folder…; a folder field on a remote machine),
   `symbol(name, size)` (an SF Symbol as an image), git writes (stage, unstage, commit, fetch, pull, push, switch,
   under the `git` permission, one at a time, `GIT_TERMINAL_PROMPT=0`), `open(arg, { how: "card" | "tab" | "side",
   at })`, and `theme.textSize` (the app's text size, which web cards ignore today).
4. Network from a page: no. Plugins from a project folder: later. Settings drawn from the manifest: later.
5. **Plugins work like pi packages** ([pi's packages](/usr/local/bin/pi_cli/docs/packages.md) and extensions, the
   user's model). Only the browser is native; every other plugin, File Explorer and Git too, is a package the user
   or an agent can install, edit and reload.
   - **A plugin is a package:** a folder with a `package.json` whose `oriel` key is the manifest (the manifest page's
     fields: entry, opens, chooser, header, commands, permissions, `api`), its TypeScript, and its own
     `node_modules`. Its `version` is the package's. No separate `manifest.json`.
   - **Install, update, remove, list,** as `pi install`: sources `npm:@scope/name@1.2.0`, `git:github.com/x/y@v1`,
     or a local path. npm and git sources install into `~/.config/oriel/plugins/` with their `dependencies`, using
     the npm, pnpm or bun on the user's login `PATH` (the app ships no package manager and no packages). A local path
     loads in place and is never installed or changed: its dependencies are its author's (`npm install` in the
     folder). The list lives in `~/.config/oriel/settings.json` (`packages`). Versioned specs are pinned; **Update**
     reinstalls the newest version a spec allows. From the app: Settings › Plugins (each plugin's name, version,
     source, Update, Reload, Remove) and ⌘K; agents get the same through the agent-control CLI later.
   - **The default plugins are packages too,** each with its `package.json`, lockfile and `node_modules`; nothing of
     theirs is bundled into the app's build. The app carries their source (no `node_modules`) and installs each one
     on first launch as a local-copy install: copied to `~/.config/oriel/plugins/<id>/`, then `npm ci` from its
     lockfile. They are then ordinary plugins the user can edit. An app update with a newer default version updates an
     unedited copy and offers **Update to Version x.y.z** / **Reset to Default** for an edited one. With no package
     manager on `PATH` (or offline at first launch), a default plugin's card says what failed, with **Retry**.
   - **The `oriel` API is host-provided,** as pi's packages are: a plugin lists `@oriel/plugin-api` in
     `peerDependencies` as `"*"` for its types and never bundles it; the app writes the types package into the plugins
     folder for `tsc`, and the runtime passes the `oriel` object to the entry's default export.
   - **Build:** the app ships esbuild as its loader (as pi ships jiti), never packages. It bundles a plugin's entry
     with the plugin's own `node_modules` only: no fallback to anything else. A build is cached by its inputs' hash.
   - **Reload, not a watcher,** as pi's `/reload`: **Reload Plugin** (the card's menu, ⌘K, ⌥⌘R over a plugin card)
     and **Reload Plugins** (⌘K, Settings) rebuild and reload the open cards, keeping each card's state. Nothing
     watches the folders. A failed build keeps the old page and shows the errors in the card.
   - **Testing:** open a card on a sample file and press Reload; the Web Inspector (the card's menu) for the console,
     the DOM and breakpoints; `~/Library/Logs/Oriel/plugins/<id>.log` for build errors and console lines, which agents
     read; `tsc --noEmit` against the host types; the plugin's own tests with any runner in its `node_modules`.
   - **Trust,** as pi: installing a package asks once, showing its source and permissions; it asks again only when an
     update grows the permissions. The default plugins need no prompt.
6. The browser stays a native web view and joins the registry as a manifest written in Swift, with no entry file.
7. **Parity is the bar.** Every UI test of File Explorer, File, Preview, Markdown, Git and the chooser passes with
   only accessibility-id changes that the new header forces (none if the ids can stay). Before/after dark and light
   screenshots of each view, in a pane and floating, match (pixel compare; any difference is a bug or a listed,
   approved change). Memory and load time of a File Explorer and a Git card stay within 10 % of main.

## Track A: the registry (goes first, merges early)

Files: a new `Oriel/Plugins/Registry*.swift`, `PluginKind` and its uses, the scheme handler, the chooser, ⌘K and Open
With lists, `plugins/<id>/package.json` (the `oriel` key) for explorer and git, `make web`'s output layout.
1. Read the `oriel` key of every package in `~/.config/oriel/settings.json`'s list and in `~/.config/oriel/plugins/`
   (decision 5; until track F lands, the repository's default plugins are read in place); validate (the manifest page's fields and rules); a bad
   manifest is skipped with its error in the log.
2. `PluginKind` goes; the registry's entries replace it everywhere (browser from Swift). Old label words still map.
3. The scheme serves `oriel-plugin://<id>/` per plugin with the CSP per plugin and the navigation lock.
4. Chooser rows, ⌘K commands and Open With come from `chooser`, `commands` and `opens`.
5. A label naming a missing plugin shows the missing card (id, argument, Show Placeholder, Close Pane).

## Track B: the runtime and the API

Files: `web/oriel/` (the runtime and `oriel.d.ts`), a new Swift bridge (`Oriel/Plugins/Bridge*.swift`), state files.
Owner of the bridge messages; agrees the controls messages with track C.
1. The runtime makes `oriel` before the page runs and calls the entry's default export with it; types in
   `oriel.d.ts`, versioned by the integer `api` (1).
2. The Swift bridge checks each call against the manifest's permissions and runs it with the card's `Exec`
   (HerdrKit `Files`, `Git`, `Exec.run` with the envelope).
3. Every part of the api page plus decision 3's additions. State: in the app at once, written to the instance state
   file 500 ms after the last set.
4. Events: control, place, save, find, keyboard, theme, visible.
5. Unit tests for each bridge call and a fixture plugin that calls every part (one UI test).

## Track C: the header

Files: a new `Oriel/Plugins/Header*.swift`, `PluginCard`'s header row, floating plugin windows' row 2. Uses track
B's controls messages.
1. Draw decision 2's controls from the manifest before the page loads, update them from `controls.set`, send their
   events.
2. Back/Forward and `openWith` as app controls; the Edited dot from `setDirty`.
3. The same header in a pane and in a floating window, light and dark, starting at the left edge.

## Track D: File Explorer on the API (after A, B, C merge)

Files: `plugins/explorer/**` (a package: `package.json` with the `oriel` key, lockfile, its own deps) (from `web/src/{files,file,preview,markdown}*` and `web/src/lib/{editor,info}*`),
deletions of `FileBars`, `MarkdownBar`, `FilesCard`'s bar, `Document.swift`'s logic (moves to TypeScript), the old
bridge's explorer paths.
1. One manifest, one `main.ts` that routes the four places; same looks, keys, saves by hash, conflict toasts, watches,
   reveal, root control, filter, Open With, open gestures.
2. Parity per decision 7 with FilesTests, FileTests, MarkdownTests, PreviewTests, PluginTests.

## Track E: Git on the API (after A, B, C merge)

Files: `plugins/git/**` (a package, as track D) (from `web/src/{git,diff}*`, `web/src/lib/rows.css`), deletions of `GitBar`,
`DiffToolbar`, `GitRepo`'s page code that moves to TypeScript, the old bridge's git paths.
1. Home and diff as places of one card; branch menu, Fetch/Pull/Push with counts, commit, stage, history of every
   branch, Unified | Side by Side, file list, Viewed, steps.
2. Parity per decision 7 with GitTests and PluginTests.

## Track F: packages (after A and B merge; beside D and E)

Files: esbuild in `Contents/Helpers` (from the locked npm package's darwin binary; `make app` signs it), install,
update, remove and list (decision 5) with `~/.config/oriel/settings.json`, Settings › Plugins, the default plugins'
first-launch install and their update and reset rules, the build cache, Reload Plugin and Reload Plugins, the trust
prompt, the Web Inspector toggle, the logs, the host types package `@oriel/plugin-api`. Tracks D and E keep `make web`
working until this track switches the default plugins to installed packages.
1. Install from npm, git and a local path with the npm, pnpm or bun on the login `PATH`; a clear card when none is
   there or the install fails, with Retry.
2. Build on first load (cached by input hash) and on Reload (tens of ms) from the plugin's own `node_modules` only; a
   failed build keeps the old page and shows the errors; a card with unsaved edits asks before it reloads.
3. Reload keeps each card's state. No file watcher.
4. The default plugins installed on first launch (copy + `npm ci`), updated when unedited, Update to Version / Reset to
   Default when edited.
5. Test fixtures: the building page's CSV Table as a local-path package (a UI test writes it, opens a card, edits
   `main.ts`, presses Reload Plugin, sees the change) and a package that imports a dependency from its own
   `node_modules`; an install from a local git repository (no network in tests).

## Track G: parity and the end (after D, E, F)

1. The parity screenshots and measurements of decision 7, against main.
2. The old bridge (`web/src/lib/bridge.ts`), `web/src/` and every Swift piece the migration left unused are gone.
3. Docs pass, final review, two full CI runs green in a row and the on-demand suite, on `plugin-system`.

## Findings

### Track A

- **Decisions:** the `oriel` key holds the manifest page's fields with `entry` for `main` and an `id` of its own (a
  package name can be scoped); `version`, `description` and `keywords` are the package's. The description is the
  chooser row's detail line and the keywords are ⌘K's extra words, so the three rows read as before. `opens` may
  hold `files` and `folders` together: File Explorer opens both (`*` and folders), Git `{ "git": true }`.
- **Decisions:** the registry reads, first id wins: the browser (Swift), the app's default plugins (`make web` now
  writes `.build/web/<id>/` with each one's pages, `card.css` and `package.json`; read in place until track F),
  `settings.json`'s local paths (`/`, `~` or `.`; relative to its folder), then `~/.config/oriel/plugins/*/`. A bad
  manifest or a taken id is skipped and logged to the unified log (`log show --predicate 'subsystem ==
  "dev.hkandala.oriel"'`) until track F's log files. `-configFolder` points it elsewhere; UI tests pass a folder
  that does not exist unless a test writes one.
- **Decisions:** the manifest model and its rules live in HerdrKit (`PluginManifest`, unit tested), with the
  file-pattern rank of the manifest page. Header controls and commands are decoded and checked (types, unique ids,
  ⌘ chords) but not drawn or put in ⌘K yet: their picks need the control event (tracks B and C).
- **Fix:** the scheme serves `oriel-plugin://<id>/<page>` from that plugin's folder only, with the security page's
  CSP for `oriel-plugin://<id>` (`default-src 'none'`, own scripts, styles, fonts and fetches); the navigation
  lock allows only the card's own URL.
- **Decisions:** a user plugin's card shows its loader (it has no page until tracks B and F); File Explorer and
  Git keep `PluginPage` for their pages until tracks D and E. A missing plugin's card (any well-formed
  `oriel:` label the registry lacks) shows the id, the argument, Show Placeholder and Close Pane; Show Placeholder
  is kept on the pane model, not saved. Open With lists the other plugins whose patterns match after the apps
  (none today, so it looks as before; on a remote machine it shows only when one matches); a pick renames the
  pane to that plugin with the same iid. The tree's row-menu Open With and URL patterns for links wait for a
  plugin that needs them (tracks D, B).
- **For the user:** nothing changes on screen with no packages of your own. A label `oriel:<unknown>#abc123 x`
  shows the missing card.

### Track C (the header)

- **Decisions:** `Header` (one per card, in `Plugin`, so a dropped or reloaded card keeps it) holds the manifest's
  controls with the page's changes over them. `controls.set` takes value, title, label, symbol, badge, items, hidden,
  enabled and busy; `""` or `0` clears a badge, `""` a symbol or label. A toggle, segments and a field change their
  value natively, then the page hears `{ id, value, submit? }`; a menu pick only sends (an item may be an action such
  as Choose Folder…), and the page sets the menu's value. A field's value changes as the user types: the page sets it
  only to replace or clear it (after Return), never to echo it, or a late echo puts back text the user typed past. The
  same segment again, or a field writing back its text, sends nothing. `values` is `controls.get`'s and the state file's
  `"controls"`; `restore` puts saved values back; `changed` fires on every change for track B's 500 ms write.
- **Decisions:** the manifest grew what the two plugins need: `history: true` draws Back and Forward first
  (`pane.<id>.go-back` / `go-forward`, the card's own history); the type `openWith`, whose value is the path the page
  sets (no path, not drawn); a `path` text's value is a list of parts; a text's `symbol` draws before its last part
  (File's `{}` before the scope); menu items take a `symbol`, and `{ title }` starts a section ("Remote"); a button's
  `badge` and `busy` (a count after its symbol, a spinner in its place), and `label` for VoiceOver ("Push, 1 ahead").
- **Decisions:** controls sit 6 pt apart; a control's `gap` sets the points before it, because the built bars group
  icon buttons only the plugin knows about: 0 between Preview's zoom buttons and before Diff's Previous and Next, 2
  for Git's Pull and Push, 6 between Preview's last zoom button and Show in File Explorer. A text's `"digits": "mono"`
  gives monospaced digits (Preview's `3 of 12`); paths stay proportional. Free space goes to a spacer or a field;
  with neither, after the last control, so the row starts at the left. Every control's id is `pane.<pane>.<id>` and
  segments keep `<id>.<title lowercased>`, so the built bars' ids (`filter`, `root`, `jump`, `mode.read`, `outline`,
  `git.branch`, `diff.layout.side by side`, …) can stay. A user plugin with neither header nor history has one header
  row, in a pane and floating.
- **For D and E:** a place's controls that other places lack default to `hidden: true` in the manifest, and the page
  shows them in `main` before `card.ready()`: a brand-new card draws the manifest's row until then (a card made again
  draws its saved values). `OpenWith` moved to `HeaderView.swift`; the built bars' row uses it until D deletes that
  row. The manifest page's Header section gets `gap`, `digits`, `label`, `badge`, `busy`, `history`, `openWith`, a
  text's `symbol` and menu headings (docs pass).
- **For the user:** a plugin's row 2 in a pane and floating, light and dark: the fixture in
  `OrielUITests/HeaderTests.swift` shows every control type.

### Track B (the runtime and the API)

- **Decisions:** the runtime (`web/oriel/runtime.ts`, built by `make web` into `oriel.js` beside `card.css`) is the
  page of a plugin's entry: `oriel-plugin://<id>/main` loads `card.css`, the entry's CSS and `oriel.js`, which reads the
  card's context (`window.oriel_card`, a user script at document start) and imports the entry's built `.js`. The
  types are `web/oriel/oriel.d.ts` with its `package.json` (`@oriel/plugin-api`); `make web` checks the runtime
  against them with `tsc` (TypeScript 7, a dev dependency of `web/`). Until track F builds packages, a user plugin's
  folder is served as it is, so its entry must be JavaScript in the package's root (the scheme serves no subfolders).
- **Decisions:** the bridge messages are `{ call, args }` to the app, answered with a JSON string or rejected with
  `<code>: <text>` (the runtime makes the `OrielError`), and `oriel_receive(name, data)` to the page. Calls that wait
  for the user (toast) answer through an event, so no Swift task hangs on a page that never hears back. A plugin page
  gets only these; File Explorer's and Git's pages keep their old messages until tracks D and E.
- **Decisions:** the calls on the card's machine (files, git, run) and the permission table live in HerdrKit
  (`PluginCalls`), unit tested against real files, a real repository with a bare remote, and real processes. Their
  arguments decode with `JSONDecoder`: `JSONSerialization` drops a byte order mark inside a string. The card's own
  calls (place, state, header, toast, menu, Choose Folder…, symbols, clipboard, watches, commands) are the app's
  `Bridge`, one per card, made with the `Plugin`.
- **Decisions:** `place` fires on every move, the page's own `card.go` too (after Discard when it was dirty), so a
  page draws its places in one handler. After Back, `at` is where the card came back from (that place's landing, else
  its argument): the tree reveals the file it opened, Git's home the change. `open` defaults to a new tab; no
  `plugin` picks the browser for http(s), the first folders plugin for a path ending in `/`, else the file's default.
- **Decisions:** API additions for tracks D and E beyond decision 3: `git.changes`, `git.head`, `git.branches`, and
  `Commit.author`/`refs`; `controls.set` also takes `symbol`, `label`, `badge`, `busy` and items' `symbol` and
  headings (track C's header). The manifest's `commands` are in the menu bar and ⌘K while the card has the keyboard,
  their `title`/`checked`/`enabled` set with `controls.set`; a key the app uses is left off and logged once.
- **Decisions:** the state file holds `{"controls": …, "state": …}`, read once before the first load, written 500 ms
  after the last change of either, not after the pane closed; closing any plugin pane (not only a browser's) removes
  it. A drop keeps nothing in memory (the `Plugin` goes): the card made again reads the file.
- **Decisions:** `run` keeps `Exec`'s shape: stdout as lines up to 4 MiB (then `truncated`), stderr's last 8 KB, a
  last line break added to stdin. `visible` follows the cards in view (the shown tab's and the floating ones, as the
  web card budget counts them), not the card view's `.task`, which a tab switch does not end. `files.watch` runs only
  while the card is in view and calls each watch once when it comes into view again, changed or not. An entry whose `main` throws shows "‹name› stopped", the message, its first stack line and
  Reload; an `api` above 1 shows "‹name› needs a newer Oriel".
- **For the docs pass:** the trust prompt's words for `git` must say it can commit, pull and push.
- **For the user:** nothing changes for File Explorer and Git. A plugin package with a `.js` entry in
  `~/.config/oriel/plugins/` now loads in its card and can call the whole API.

### Track D (File Explorer on the API)

- **Decisions:** `plugins/explorer` is a package with its own `node_modules` (CodeMirror, `@pierre/trees`,
  markdown-it, pdf.js) and lockfile; `make web` runs `npm ci` there, checks it with `tsc` against
  `@oriel/plugin-api` (a link `plugins/node_modules/@oriel/plugin-api` to `web/oriel`, as track E) and bundles
  `main.ts` with esbuild into `.build/web/explorer`. The manifest's `assets` (pdf.js's files, places.json) is
  track F's key for its build; `make web` copies the same files until then. `card.css` is the app's base for every plugin page
  (`web/oriel/card.css`); the explorer's own CSS is imported by `main.ts` (a dynamic import's CSS gets no link),
  scoped by `data-place`.
- **Decisions:** `main.ts` routes the four places, each a module loaded with `import()`. A move draws the new place
  in a hidden root over the old one and swaps them once it drew, so the old frame stays until then; the same place
  with a landing only lands. Each place ends its handlers, watches and views on leaving (`keep`). Row 2 is the
  manifest's (every place control `hidden` until the page shows its own); Edit Mode is a manifest command (⌘E).
- **Decisions:** one rule picks an explorer's place, in the page (`kind`) and the app (`ExplorerPlace`, for the tab
  icon, the page id `files/file/preview/markdown.<pane>.page`, so no test id changed, and which places take ⌘S and
  ⌘F), from one list of extensions (`plugins/explorer/places.json`, which the app reads from the plugin's folder): a
  page has no file types. File shows the info view for any other file that is not UTF-8. Show in File Explorer's
  "tree it came from" is the page's own list of trees shown.
- **Decisions:** `files.info` also gives the file's hash (track B agreed), so File and Preview check it before a full
  read when the file may have changed, as main's `Files.hash` did; a command disabled with `controls.set` drops its
  key, so ⌘E has its key only over Markdown.
- **Fix:** a header text takes its whole width before a spacer (`layoutPriority`): the jump bar and Preview's path
  were cut at half the row. A card's move drops the old place's toast, as a page load did.
- **Fix:** a PDF changed on disk redraws: the old page called `PDFDocumentProxy.destroy`, which pdf.js 6 lacks, and
  stopped there; the loading task's `destroy` ends the document and its worker.
- **Approved changes** (parity screenshots in `/tmp/oriel-shots/47d`, everything else pixel-equal): a Markdown
  card no longer takes the keyboard as it loads (main's `article.focus()` made it the keyboard card); Collapse All is
  in the card buttons' color, as the design says (main drew it in the text color); Edit Mode is in the View menu only
  while a File Explorer card has the keyboard, disabled outside Markdown; the filter of a root inside a repository
  (not its root) lists git's files (the API's `files.paths`); `.pem`, `.crt`, `.cer`, `.eml` and `.ps` open in File
  (main: Preview's info view, by `UTType`). `pick.folder` on a remote machine shows main's "No folder ‹path›" notice.
- **Runs:** 41214627809 (on eb3aebed…d66509b8): 11 of 12 green; File's Overwrite asked again, because
  `save(undefined)` took the default `over`. 41216469734 (e716cd99): 11 of 12; the new tab's order was read before the app moved
  it after the card's (a race in the test, which now waits for the move). 41217702085 (439bc03e): 11 of 12; Back to the
  tree showed the filter field with the last tree's text until the page cleared it, and a field shown with text takes
  the keyboard, so ⌘] went to the field. The filter now shows empty in the same change that shows it.

### Track E (Git on the API)

- **Decisions:** Git is the package `plugins/git` (its own `package.json`, lockfile and `node_modules` with
  `@pierre/diffs`; `@oriel/plugin-api` an optional peer, as npm would fetch it otherwise). `main.ts` routes the two
  places in one page; the diff and `@pierre/diffs` load with `import()` on the first diff. `make web` builds it with
  web's esbuild and checks it with `tsc` against the host types, found through a gitignored
  `plugins/node_modules/@oriel/plugin-api` link to `web/oriel`, the layout the app's plugins folder has.
- **Decisions:** one document holds both places, so each place's CSS is nested under its container (`#home`,
  `#diff`) and the shared rows stay global; all CSS is imported by `main.ts`, as esbuild links no CSS of a
  dynamic chunk. The diff lets go of its patch while the home shows, as each move loaded a new page before.
- **Decisions:** row 2 is the manifest's header: the branch menu (`label: "Branch"`, items and value from the page,
  a `{ title: "Remote" }` heading), Fetch, Pull and Push with `badge`, `label` ("Push, 1 ahead") and `busy`; the
  diff's Git Home, `Unified | Side by Side`, the file list button (its title Hide/Show File List) and Previous/Next
  with `gap: 0`. One spacer serves both places; the diff's controls start hidden and the page swaps them per place.
  Every control keeps its old id, and the page ids stay `git.<pane>.page` and `diff.<pane>.page`
  (`Plugin.name()`); another plugin's entry page is `<plugin id>.<pane>.page`.
- **Decisions (to approve):** the commit message and the file list are in the card's state, Side by Side is the
  header's saved value: all three now also survive a drop, a reload and a relaunch (they were kept while the app ran),
  as decision 5's Reload keeps a card's state. The docs pass changes plugins.mdx's "not saved". Writes and
  their toasts (Copy, OK) go through the API; `clipboard` joined the permissions for Copy.
- **Fix:** `GitBar`, `DiffToolbar`, `GitRepo`, `DiffPatch`, the old pages and the old bridge's `repo`, `patch`,
  `layout`, `list`, `step` and `symbols` are gone; `@pierre/diffs` left `web/package.json`.
- **Runs:** parity is pixel-equal against main: the home, the diff, Side by Side, no file list, and the home and the
  diff floating, dark and light (a throwaway test with a fixed-date repository, run on both builds): the only
  differences were the caret's blink and the glass's ±3 levels, which the terminal beside it shows too.
- **For the user:** the Git card looks and works as before. A dropped or relaunched card now keeps its typed commit
  message and its Side by Side and file list.
