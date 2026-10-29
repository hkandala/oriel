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

### Track D

- **Decisions:** which kind opens a file is `PluginKind.opening(_:)`, by the name alone (a remote file is not read
  first): `.md .markdown .mdx` → markdown; `.ts .mts .cts` and names the system does not know (`.rs`, `Makefile`,
  `.gitignore`) and `.plist` (XML in a repository) → file; image, PDF, audio and video types → preview; other text types
  → file; other known types (`.zip`, fonts) → preview. The file kind shows bytes that are not UTF-8 as the preview's
  info view.
- **Decisions:** the tree's state (the outline view, open folders, listings, filter, git data) is a `FileTree` kept on
  the `Plugin`, so a float or a move keeps the open folders and the scroll; the card hosts its scroll view in a
  `TerminalHost.Host` that adopts it, so an overview tile borrows it and the card takes it back. Folders list when they
  open; on each change the watch sees (the root's, FSEvents or the remote 2 s poll) the root and every open folder list
  again, and git's status and branch read again (the section's count); the history only while the section is open. A
  value is written only when it changed: a build changes files every second.
- **Decisions:** a double-click on a folder opens or closes it; a double-click or ⌘-click on a file opens it. The filter
  matches file names (not paths), case-insensitively, and shows the first 5,000 matches with their folders, all open; it
  reads every path once per change on disk, when a filter starts. Clearing it gives back the folders that were open.
  Changes and History open the diff of the git root (`<repo> uncommitted` at the file through `Page.open(_:arg:at:)`, or
  `<repo> <hash>`).
- **Decisions:** colors: git letters use the agent-state tokens (`Look.git`: M amber, A R U green, D C red), a folder
  with a change inside shows a 6 pt dot in its letter's color; the lanes cycle blue, amber, green, red (no purple
  token). The Git section opens into a `VSplitView` (the user drags the split); Changes and History are header rows in
  one plain `List`, so the lanes touch from row to row.
- **For the user:** check a repo with merges (lanes), the split's first position (half and half), Finder icons at 16 pt
  (generic for names the system does not know), and a Files card on a remote machine.

### Track C

- **Decisions:** one TextKit 2 `NSTextView` per column, a paragraph per row (file header, unmodified-lines row, hunk,
  line, filler) of a fixed height, so every row's top comes from the rows (TextKit 2 makes no fragment for a last
  empty paragraph); no wrapping, so Side by Side's two views keep their rows level and scroll together. The text is
  laid out whole (its width), so a file over 2,000 changed lines starts folded. Backgrounds, the old/new gutter and
  `+`/`−` are drawn in `drawBackground` from those tops (no layout-fragment subclass); word marks are background
  attributes. Colors are the Look's `finished`/`error`/`working`, as Files' git letters.
- **Decisions:** the file headers are SwiftUI views over the text, placed at their rows on each scroll; the top file's
  stays pinned until the next pushes it (sticky). Viewed folds the file and is kept with the file's patch: a file that
  changes since is not viewed any more. Uncommitted runs the diff again on each `Files.watch` yield of the root while
  the card shows (git's index refresh writes once, then it is quiet); the text changes only when the patch does, and a
  refresh or the layout toggle keeps the top file where it was. On a remote machine the root's 2 s check sees only
  `ls` and `git status`, so an edit to a file already changed shows on the next status change (`Files.poll`, phase
  42 track B's).
- **Decisions:** the source pop-up rewrites the pane's label (`<root> <hash>`), so the title, tab and a relaunch follow
  it. Previous / Next go from run to run of changed lines across files; "N unmodified lines" has no expand (it needs
  whole files). Defaults: Unified, file list open (agreed with t44-diff, as the row-2 ids).
- **Decisions:** `Plugin.place` and `Page.open(_:arg:at:)` carry a linked open's landing (a file's line for ⌘-click, a
  diff's file for Files' Changes), kept by terminal id until the card is made. The File and Markdown content (tracks
  A and B) read the line; DiffTests checks the tab and its file, not the line; Files' tests check the diff's landing.
- **Cause:** NSTextView (TextKit 2) moved the text left by its paragraph indent and kept the first column as narrow as
  its scroll view; the gutter is now the container inset with no line padding, and the view's size is set from the
  laid-out width.
- **For the user:** a big change set (thousands of lines) opens in about 0.2 s; scroll, the pinned header, Viewed on a
  long file, Side by Side on a narrow card, and ⌘-click on a removed line (opens the file at the line after it).

### Track A

- **Decisions:** the grammars sit in a local package, `Packages/Grammars` (one product in the Xcode project, not 19
  package references), pinned to exact tags. CSS, JavaScript, Python and YAML use an older tag: the newer manifests
  look for `src/scanner.c` from the build's folder, not the package's, and drop the scanner. Kotlin is fwcd's grammar
  (the tree-sitter-grammars tag has no queries). TypeScript and C++ queries are added to the JavaScript and C ones.
- **Decisions:** colors are TextKit 2 rendering attributes set in `renderingAttributesValidator`: TextKit asks per
  paragraph as it lays one out, so only the lines on screen run a query; edits update the tree in place. A capture's
  color comes from its role, as Xcode's theme, in AppKit's system colors (light and dark, no Look token). No colors
  over 4 MB, where a parse takes about a second. Lines wrap and go on at their own indent (`NSTextParagraph` from the
  content storage's delegate); the current line is the caret's whole paragraph.
- **Decisions:** `FileText` (Oriel/Plugins/) is the file and markdown cards' one load, save and reload: bytes with a
  NUL or not UTF-8 show the preview's info view; a change on disk reloads a clean text, and a dirty one gets
  “‹name› changed on disk.” [Reload] [Keep Mine]; a save that finds the disk changed gets “‹name› changed on disk
  since you opened it.” [Overwrite] [Reload]. The safe choice is the main button (phase 42's Toast). Keep Mine takes
  the disk's hash: the next ⌘S writes over that version but still stops on a later change.
- **Decisions:** ⌘S (File ▸ Save), ⌘F, ⌘G and ⇧⌘G on a card with a file text: `CommandList.plugin` and
  `CommandList.find`. Find sends `performTextFinderAction:` down the responder chain, so the system find bar opens on
  whichever text view has the keyboard (markdown's too). Save's ⌘S and Find Previous's ⇧⌘G exist only on such a card
  (elsewhere ⇧⌘G stays Go to Directory): a disabled item would keep the key from a terminal. The terminal's find
  stays as it was.
- **Decisions:** PluginCard clips and pads every kind's content once (6 pt, as the browser's page). A content that is
  no text view takes the keyboard through `takesKeyboard` (a click, AppKit views too, and `wantsKeyboard`); the file
  card's text view claims it itself. A click on a PDF, a player or an image gives that AppKit view the keyboard (its
  arrows and Space; the image's arrows scroll it when zoomed) and claims it for the card, so ⌘W closes the card.
- **Decisions:** the jump bar's symbol is the innermost declaration around the caret from the tree (a node type that
  ends in declaration, definition, item, spec or specifier, and its `name` field, C declarator or first identifier),
  not `tags.scm`, which 7 of the grammars lack.
- **Decisions:** the preview reads every file through `Files.read` on both machines (one 16 MB cap, reloads compared by
  hash). Audio and video on This Mac play from the file; a remote one from a copy in the temporary folder. Image zoom
  is the scroll view's magnification; Fit fits, Actual Size is 100 %.
- **For the user:** check the colors of a few languages, a long wrapped line, ⌘F and ⌘G, ⌘Z after an edit, a reload
  while you type, a PDF's page count while you scroll, and Read Only on a remote file over 4 MiB.
