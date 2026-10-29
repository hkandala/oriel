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
  has the app's colors; `color-scheme` follows the look.
- **Decisions:** no shared process pool. `WKProcessPool` is deprecated and does nothing: three web views on one pool
  made three WebContent processes. Every web card is its own process.
- **Decisions:** the bridge has the `read` ask and the `dirty` report, the two the test page uses. `read` is `cat`
  over `Exec` (it trims the text, so nothing may save through it) until phase 42's file data lands. Listings,
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
- **For the user:** nothing to try by hand yet: the test card shows only for a pane labeled `oriel:webtest#<iid>
  <path>`, and phase 42's integration replaces it with the five kinds.
