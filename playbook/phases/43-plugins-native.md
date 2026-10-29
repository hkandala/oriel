# Phase 43: Default plugins with native views

Goal: the five plugins of [phase 42's spec](42-plugins-base.md#the-spec-both-variants-build-all-of-it) with Apple's
views and at most one library each, on branch `plugins-native` (from `plugins-base`). Same features as
[phase 44](44-plugins-web.md); only the look of the content may differ. Picks and measurements:
`resources/research/plugins/default-plugins.md`; layouts: the recommended mockups in
`~/Downloads/oriel-research/plugins.html`.

Tracks start when phase 42's tracks A and B are on `plugins-base`. Each track owns its kind's content files
(`Oriel/Plugins/<Kind>/`) and its tests; the plumbing and the data are phase 42's (changes there go to their owner).

## Track A: File and Preview (spec items 1, 2, 6)
1. `NSTextView` on TextKit 2 with SwiftTreeSitter colors for the visible range only (about 15 grammars as packages),
   a line-number gutter, the current line, the system find bar, undo. The jump bar's symbol from the tree-sitter
   tree. Dirty, ⌘S with the hash check, reload and the toast through phase 42's views.
2. Preview: `NSImageView` in a scroll view with zoom; PDFKit's `PDFView` (pages, zoom, page `n of m`); `AVPlayerView`
   for audio and video; the info view for the rest.

## Track B: Markdown (spec item 3)
3. [MarkdownEngine](https://github.com/nodes-app/swift-markdown-engine) (Apache-2.0, pin its version) for the live
   preview in Edit and the rendered Read mode; above 128 KB a plain TextKit 2 source view in Edit. The outline from
   `swift-markdown`'s headings (phase 41 adds the package). Links: relative paths open the right plugin, http(s) the
   browser plugin.

## Track C: Diff (spec item 4)
4. One TextKit 2 view drawing phase 42's parsed patch: the gutter, colored lines, word changes, sticky file headers
   (a layout-fragment subclass), Viewed, Side by Side as two synced text views with filler lines, the file list as a
   SwiftUI `List`, previous / next change.

## Track D: Files (spec item 5)
5. `NSOutlineView` with one listing per opened folder, git letters, ignored files dimmed, the filter, collapse all;
   the `Git` section at the bottom: Changes as rows, History as a SwiftUI `List` with a `Canvas` per row for the
   lanes.

## Findings
