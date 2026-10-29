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
