# Phase 44: Default plugins with web components

Goal: the five plugins of [phase 42's spec](42-plugins-base.md#the-spec-both-variants-build-all-of-it) with the
recommended web stack in `WKWebView`, on branch `plugins-web` (from `plugins-base`). Same features as
[phase 43](43-plugins-native.md); only the look of the content may differ. Stack and measurements:
`resources/research/plugins/default-plugins.md#key-findings` ("If web is ever needed") and the web sections of
`~/Downloads/oriel-research/plugins.html`.

The header rows, the toast, Open With and all file and git data stay native (phase 42); only each card's content
area is a web view. Track A goes first and merges early; tracks B–E start when it and phase 42's tracks are on
`plugins-base` / `plugins-web`.

## Track A: the web host (items 1–3)
1. A `web/` folder: `package.json` with a lockfile, CodeMirror 6, `@pierre/diffs`, `@pierre/trees`, a Markdown
   renderer for Read mode (a recognized one, for example `markdown-it`), `pdf.js`; no framework; one `esbuild` bundle
   per kind. `make web` builds it into the app's resources; `make build` runs it; CI installs Node. No built bundle
   in git.
2. A custom URL scheme (`oriel-plugin://`) that serves the bundle (`loadFileURL` runs no module scripts), one
   `WKWebView` per card with a shared process pool where WebKit allows it, the page's ⌘ keys handed back to the app
   (WebKit gives the page every ⌘ key first), the app's colors and fonts passed in as CSS variables, light and dark.
3. A small typed bridge (`WKScriptMessageHandlerWithReply`): the page asks for a file, a listing, a patch or a log and
   gets JSON; it reports dirty, the caret's symbol, a link to open. Row 2's controls send their changes in.

## Track B: File and Preview (spec items 1, 2, 6)
4. CodeMirror 6 with the language packs for the spec's languages, line numbers, the active line, search, history; the
   jump bar's symbol from its syntax tree. Preview: `<img>` with zoom, `pdf.js` (pages, zoom, page `n of m`),
   `<audio>` and `<video>`, the info view.

## Track C: Markdown (spec item 3)
5. Read mode with the Markdown renderer; Edit mode with CodeMirror's Markdown language and live-preview decorations
   around the caret; the outline sidebar from the document's headings.

## Track D: Diff (spec item 4)
6. `@pierre/diffs` for unified and split views, sticky file headers, word changes; the file list; previous / next.

## Track E: Files (spec item 5)
7. `@pierre/trees` for the tree and the filter; the `Git` section with Changes and an SVG History graph from phase
   42's lane layout.

## Findings

### Track A

- **Decisions:** `web/` uses npm (it comes with Node; `brew "node"` in the Brewfile, `brew install node` in CI's
  test job). `make web` runs esbuild (`web/src/*.ts` and `card.css` as entries, shared code in `web/src/lib/`) into
  `.build/web`, which a folder reference in the project copies into the app's `Resources/web`. The scheme serves
  `oriel-plugin://app/<kind>` as a generated page that loads `card.css` and `<kind>.js`, and any other name from that
  one folder. The card's label argument and the CSS variables go in by a document-start script, so the first paint
  has the app's colors; `color-scheme` follows the look. `UTType` knows no MIME type for `wasm` or `woff2`: the
  track that bundles them adds the two.
- **Decisions:** no shared process pool. `WKProcessPool` is deprecated and does nothing: three web views on one pool
  made three WebContent processes. Every web card is its own process.
- **Decisions:** the bridge has the `read` ask (`Files.read`, its text) and the `dirty` report, the two the test page
  uses. The hash for a save, listings,
  patches, logs, the caret's symbol, links and row 2's messages come with their first users in tracks B to E,
  next to phase 42's data API: each is one `case` in `WebCard.answer` and one type in `web/src/lib/bridge.ts`.
- **Decisions:** ⌘ keys go to the menu first, as over a native text view; only keys no menu item has (enabled or not)
  reach the page. So over a web card ⌘F runs the terminal's Find… today (`terminal` there means "not a browser"),
  ⌘D splits, ⌘/ opens Keyboard Shortcuts and ⌘G is swallowed by its disabled item. Tracks B and C route ⌘F, ⌘S and
  ⌘E through menu commands that know plugin panes. ⇧⌘← and ⇧⌘→ (Move Tab) go to the page first, as in a text field,
  and move the tab when the page does not take them.
- **Decisions:** `WebCardView` is a `BrowserView`, so phase 42's registry gives it the keyboard (`takeKeyboard`) and
  hears of it (`onKeyboard`) as it does for a browser; ⌘+ ⌘− still change the app's text size over it, not a page
  zoom. A crashed web process reloads the page once, as the browser does.
- **Measured** (load average 360-430, so upper bounds): one card's WebContent process 45 MB (`footprint`), six cards
  45 MB each; the test page with a 2,000-line file from `load` to the first frame with the editor: 0.7-1.2 s alone,
  1.4 s for six at once. Bundle: `test.js` 388 KB, 126 KB gzip (CodeMirror's basic setup).
- **Runs:** the UI test fails at ⌘[ with menu-first taken out (CodeMirror's indent keeps the keyboard) and passes
  with it (local, three green runs). One local run drew a blank card while the disk was full.
- **For the user:** nothing to try by hand yet: the test card shows only for a pane labeled `oriel:webtest#<iid>
  <path>`, and phase 42's integration replaces it with the five kinds.

### Track B

- **Decisions:** the file stays native: `read` gives the page the text and keeps its hash on the `WebCard`; ⌘S makes
  the page report its text and the app saves it by that hash. While a card shows (`PluginCard`'s `.task`, so a
  remote machine is polled only then), a change on disk reloads a clean file in place (only the changed middle is
  replaced, so caret and scroll stay) and gives a dirty one the toast `Reload | Keep Mine`; Keep Mine takes the
  disk's new hash, so the next ⌘S writes over that version without asking. A conflict at save: `Overwrite | Reload`.
  ⌘S on a clean file writes nothing. One `watch` serves File, Markdown, Preview and Files.
- **Decisions:** `lib/editor.ts` is the CodeMirror that File and Markdown share (no line numbers or colors: File adds
  them). Colors are Xcode's default roles, one `light-dark()` pair per role. A CRLF file saves as CRLF; a file not in
  UTF-8, or a remote one over 4 MiB, opens read only; over 16 MB both kinds show the info view.
- **Decisions:** File wraps lines (cards are often narrow); a wrapped line goes on at its own indent (a line
  decoration on the visible lines), and the lit line covers its rows. The jump bar's symbol has the `{}` glyph.
- **Decisions:** languages load by extension, each its own chunk. Swift, Kotlin, Ruby, shell and TOML have only
  CodeMirror's legacy modes (no Lezer grammar for Swift exists): no tree, so their jump bar symbol is the
  declarations less indented above the caret; the others read the Lezer tree.
- **Decisions:** Preview reads the file over the bridge (base64, 16 MB cap) and shows it from a blob: `<img>` (Fit
  never enlarges), pdf.js's own viewer (lazy pages, Fit is page width), `<audio>`/`<video>`. pdf.js loads its worker,
  decoders, fonts and maps by name from the bundle's one folder (`make web` copies them); the scheme gives `.wasm`
  its MIME type and the CSP allows wasm, blob images and media. A kind's page links `<kind>.css` when esbuild wrote
  one.
- **Decisions:** the menu's Save (⌘S) and Find… (⌘F) go to the page of a File or Markdown card with the keyboard
  (`Page.editor`), in the main and floating windows; over other plugin cards Find stays off.
- **Decisions (parity, with phase 43):** Preview draws PNG, JPEG, GIF, WebP, HEIC, TIFF, BMP, SVG, PDF, audio and
  video up to the 16 MB cap; any other file, or one WebKit or pdf.js cannot decode, shows the info view. ⌘G and ⇧⌘G
  (Find Next and Previous) go to the editor's search; over an editor ⇧⌘G is Find Previous, not Go to Directory. An
  overview tile runs no second watch; Files lists again when its card shows.
- **For the user:** check Open With's apps, the toast's look, and a PDF's zoom by hand.

### Track D

- **Decisions:** the page parses git's patch itself: `Git.patch` gives `Git.diff`'s text (`Git.diff` parses the same
  text), and `parsePatchFiles` feeds `@pierre/diffs`' `CodeView` (one virtualized scroll, sticky file headers, word
  marks). HerdrKit's own word marks serve only the native variant. Row 2's state (`split`, `list`) lives on
  `WebCard`, so the page's first `patch` ask gets it and a reload (a new source) keeps it.
- **Decisions:** a new source rewrites the pane's label (`<root> <hash>`); the registry hands the new arg to the
  card, which loads the page again. The pop-up lists the commits read when the card appeared: a commit made later
  shows after the card comes back.
- **Decisions:** Uncommitted follows the work tree as in the native variant: `WebCard.watch` watches the root, the
  page asks again and redraws only when the patch text changed; Viewed stays on a file whose text is the same. git's
  index refresh after `git diff` yields once more, then nothing.
- **Decisions:** `N unmodified lines` rows are not expandable (that needs each file's whole text, a new HerdrKit
  call); none at a file's end. The theme's fills go transparent over the card's fill, lines at 10 %, word marks at
  28 %, the sticky header blurs what scrolls under it. A deleted file has no Open File and no ⌘-click.
- **Decisions:** a linked open's landing (`Page.open(_:arg:at:)`, `window.card.at`) is one shot by terminal id,
  not in the label: a relaunch opens at the top. Previous / next step through the change blocks in order from the
  last one stepped to or the file picked in the list, not from the scroll position.
- **Fix (review):** a remote folder's 2 s check now also reads the changed files' text: an edit to a file already
  `M` changed neither the listing nor `git status`, so a remote Uncommitted went stale (red on the old poll, green
  on the new in a HerdrKit test; the native variant gets it with HerdrKit). A failed first ask waits for a change
  in the work tree and asks again, and a pick in the file list puts previous / next half a step before its file.
- **Decisions (parity):** a file new to the card with over 2,000 changed lines starts folded; a refresh keeps each
  file's fold, and a Viewed file whose text changed opens again. ⌘-click on a removed line opens the file at the line
  after the change; on the old side of an unchanged line, at that line. A file with no hunks (binary, mode only, a
  pure rename) shows its header alone. The ⌘-click's landing at the line is the
  File page's (`lib/editor.ts`); DiffTests checks it.
- **For the user:** check the source pop-up's width with a long commit subject, Side by Side in a half-width card,
  and the sticky header's blur over the lines in Glass light and dark.

### Track E

- **Decisions:** every plugin card is its kind's page: `Plugin.web` is a `WebCard` made with the card, its view takes
  and drops the keyboard through the registry as a browser's does, and `Plugin.dirty` is the page's. Track E wrote
  this shared commit first, with `WebCard.send`/`receive` (row 2 and the app to the page) and the `open` report (the
  page's links: no kind is a file, opened with `PluginKind.opening`); D added `at`, B the watch.
- **Decisions:** the tree starts with the root's listing and lists a folder when it opens (`Files.list`, which gives
  the ignored flag); the first letter of a filter loads every path (`Files.paths`, again after a change) under the
  folders not listed yet. The filter matches file names, as the native variant (the first 5,000): Pierre's own
  search matches whole paths and takes no matcher, so the matches are a second tree, shown in the first one's place. Git letters come from
  one `Git.status`, so a folder never opened still gets its dot. Git runs only when the root is its repository's
  root (the way in opens Files there): `Git.status` paths are the repository's, the tree's its root's.
- **Decisions:** double-click, ⌘-click or Return opens; a folder's double-click opens or closes it once. A filter
  with no matches says so.
- **Cause:** a link to a folder or a submodule is `sub/` in a listing and `sub` in `git ls-files`: adding both made
  Pierre's batch throw, and the filter never loaded. One entry per name now.
- **Decisions:** the Git section reads its changes and history at the load and after each change under the root
  (B's watch; one refresh at a time, changes meanwhile joined), also while closed: `git log -n 100` is cheap. A
  repository with no commit yet has changes and no history. Letter colors are the app's (`--needs-you`,
  `--finished`, `--error`, as the native `Look.git`); the folder dot is always the modified color (the tree does not
  know which letter is inside). ⌘F does nothing over a Files card (B's Find is for File and Markdown).
- **Measured:** the page bundle is 250 KB (Pierre's tree and Preact). The filter's paths stop at `Files.paths`' 8 MB.
- **Runs:** the Files test ran on CI only (chosen-tests runs): local UI runs failed in `newTab` while the Mac
  reported ⌃⌘ held. The first run failed at the first row: the test's label had an 8-letter iid, which is no plugin
  label (6), so the pane stayed a terminal.
- **For the user:** open Files Here in a big repository (the kernel, a monorepo): the first letter of the filter
  loads every path; check the wait, the arrow keys after it, and the memory of its web process.

### Track C

- **Decisions:** the page owns Read | Edit and the outline and reports what it shows (`markdown` report); row 2's
  `Segments`, the outline toggle and ⌘E (View ▸ Edit Mode, checked while editing) only ask for a change. A page that
  loads again (a crash, a new label argument) starts in Read and the row follows it, with no state to keep in step.
- **Decisions:** Read is markdown-it over the editor's current text, so unsaved edits show in Read too; Edit is the
  File card's shared editor (`lib/editor.ts`) with CodeMirror's Markdown language (GFM) and a decoration that hides
  each mark (`#`, emphasis, a link's brackets and address, code ticks) unless the selection touches its element.
  Fenced code fences, autolinks, link references and setext underlines stay shown. ⌘F in Read switches to Edit,
  where the search panel is.
- **Decisions (with t43-markdown, for parity):** the same ids (`pane.<id>.mode.read|edit`, `pane.<id>.outline` with
  `.isSelected`); front matter hidden in Read and skipped by the outline, text in Edit; images are not loaded, their
  alt text links to them (a relative one opens Preview); links open from Read only; a linked open with a line opens
  Edit at that line. Unlike the native variant there is no 128 KB gate: CodeMirror and markdown-it stay fast at
  megabytes; the File card's caps (16 MB view, 4 MiB remote edit) hold. Front matter (`---` on the first line to the
  next `---` line) is YAML in Edit (`yamlFrontmatter`), so it is no rule or heading there nor in the outline. Away
  from the caret a task's `[ ]` is a box; table pipes stay (CodeMirror has no table view).
- **Cause:** with `html: true` a file's `<meta http-equiv=refresh>`, a form or an SVG link navigated the card to any
  site, which then had the bridge (read and save the file). **Fix:** every web card allows only `oriel-plugin:`
  navigations (`Relay`).
- **Decisions:** the outline comes from the editor's syntax tree in both modes (headings at the top level, in lists
  and quotes); Read finds a heading by its source line (`data-line` from markdown-it's map). Read headings get
  GitHub's ids, so `#section` links scroll.
- **Runs:** the UI test on a chosen-tests CI run, green after one fix of its own (a 5-letter iid is no plugin label).
  CI's screenshots and recording show the web card's content blank while the accessibility tree has it; on this Mac
  it draws.
- **Measured:** `markdown.js` 649 KB, 231 KB gzip (lang-markdown pulls in the HTML, CSS and JavaScript languages for
  HTML blocks).
- **For the user:** open a long design page, toggle the outline, click a heading in both modes; ⌘E with the caret in a
  bold word or a link shows its marks only there; a relative link and an http link open new tabs.
