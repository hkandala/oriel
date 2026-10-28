# Default plugins: native views over web components

Research for Oriel's default pane kinds beyond Terminal, Agent and Browser: a file viewer and editor, Markdown,
diff and git history, and a file tree. Spikes ran on an Apple Silicon Mac with macOS 27.0.1, Xcode 27.1, Swift 6.4
and Node 24, in throwaway folders outside the repo. Other jobs kept the load average at 260–600, so every time is an
upper bound. Versions and licenses are from `gh api` and `npm view`.

## Recommendation

Build all four natively. Each one is an Apple view plus at most one small library. We write glue (colors, a gutter,
a patch parser, a listing), not an editor. The native views were fast enough everywhere, used far less memory than
the web for diffs and trees, and get keys, find, undo, input methods and VoiceOver from the system.

| Plugin | Native pick | Measured | Web fallback | First slice |
|---|---|---|---|---|
| File viewer and editor (`file`) | `NSTextView` on TextKit 2 + [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter) colors for the visible range; Quick Look and PDFKit for other files | 50,000-line Swift file: first colored screen 220–260 ms, 150–360 MB | CodeMirror 6 (20 ms, 89 MB web process) | read-only viewer, 15 languages, images, PDF: 6–8 days; save: 3–4 |
| Markdown | [MarkdownEngine](https://github.com/nodes-app/swift-markdown-engine) (Apache-2.0, 0.15.0): TextKit 2 live preview over the file's own text | 74 KB doc: 0.97 s; a plain TextKit 2 source view: about 20 ms at any size (used above 128 KB) | CodeMirror 6 live preview | view, edit, save: 4–5 days |
| Diff and git history (`diff`, `git-history`) | one TextKit 2 diff view from git's patch, shared with the changes drawer; SwiftUI `List` + `Canvas` for commit lanes | 6,716-line diff: 187 ms, 4.6 ms per page, 60–110 MB | `@pierre/diffs` (worst page 171 ms, 126–549 MB) | diff view 4–5 days (drawer budget), card 1–2, history 3–4 |
| File tree | `NSOutlineView`, one listing per open folder, as a Files tab in the changes drawer | 103,617 rows expanded: 382 ms, 67 MB | `@pierre/trees` beta (97k paths: 0.6 s, 402 MB) | 4–5 days |

No other default pane kind is needed: images and PDFs open inside the file viewer, Open in ‹App› (VS Code, Cursor,
Zed with their SSH URL forms) and Open in Terminal Editor are menu commands, search is a later mode of the file tree,
and ports stay in the browser's ports chip.

## Key findings

- **Every ready-made native code editor has a blocker.** STTextView: GPL-3 or a paid license, and its memory grew to
  926 MB while scrolling. CodeEditSourceEditor: 56 s and 1.5 GB for 50k lines, macOS only, "not ready for
  production". CodeEditorView: about 7 languages, 11 s for 5k lines. Runestone: iOS only. Neon's highlighter took
  5.7–13 s offscreen. About 60 lines of our own that color only the visible range beat them all.
- **Tree WYSIWYG editors rewrite Markdown.** A save with no edit of three repo docs changed 17–70 % of the lines in
  Tiptap, Plate, BlockNote, Milkdown and prosemirror-markdown, and 21 % or more with swift-markdown's formatter. Some
  edits change meaning (hard breaks, lost relative links, flattened lists, lost footnotes). Editors that edit the
  text itself (MarkdownEngine, CodeMirror) change nothing.
- **SwiftUI views per row or block do not scale.** A `LazyVStack` diff used 150–650 MB and was 6× slower per page than
  one text view. MarkdownUI, Textual and MarkdownView took 2–8 s and up to 2 GB on a 200 KB file. `Table(children:)`
  took 6.8 s for 100k rows, and `List(children:)` cannot restore open folders.
- **The git CLI, not libgit2.** A remote machine has only `git`; one code path over `Exec` serves This Mac and remote.
  SwiftGit2's last release was in 2019. Word diff in the app with `CollectionDifference`: 17 ms for the whole diff.
- **Remote data fits the relay.** Read with `cksum` plus `base64` (the relay carries lines), save over stdin with a
  checksum check and an atomic `mv`, re-read on snapshot events and a 5 s poll while a card shows. A folder listing
  (`ls -1Ap`) is 2–5 KB. The kernel's `git ls-files` (3.9 MB) needs `gzip | base64` to stay under the 4 MiB limit.
  No server helper is needed.
- **A web card is heavy.** 38 MB empty, 70–165 MB with one component; on macOS 27 every `WKWebView` gets its own
  WebContent process (six CodeMirror cards: 777 MB), and a closed card's process stays about 100 MB for 40 s or more
  (WebKit's process cache). WebKit gives every ⌘ key to the page first. `loadFileURL` runs no module scripts, so a
  custom scheme is required.
- **If web is ever needed:** CodeMirror 6, `@pierre/diffs`, `@pierre/trees` and CodeMirror live preview for
  Markdown, no framework, one esbuild bundle: 474 KB gzip. Not Monaco (1 MB gzip, 151–164 MB per card, its own scroll
  bars and menus, an empty text for VoiceOver by default, no mobile support). Not diff2html (builds every row,
  2.5–3.1 GB).
- **iOS:** TextKit 2 (`UITextView`), tree-sitter, SwiftUI `List` and `Canvas` run there. `NSOutlineView` becomes a flat
  SwiftUI list, `QLPreviewView` becomes `QLPreviewController`, MarkdownEngine has no iOS version (an iPad viewer
  first).

## What the design would change

- `diff`, `git-history` and `markdown` become built-in native kinds, declared as values like the Browser, with
  reserved ids. Then no default plugin uses the web plugin API, so the web plugin host (bridge, consent, packages,
  the 6-web-view cap) waits until a third-party plugin needs it.
- The changes drawer draws with one TextKit 2 view and gains a Files tab.
- The iOS app ships native twins, not the same web pages.
- ⌘-click on a file path in a terminal opens the file viewer.

## Open questions

1. Native built-in kinds for the defaults, and the web plugin host deferred?
2. One `file` kind that picks its view by type (code, Markdown, Quick Look), or a separate `markdown` kind? One Git
   kind, or `diff` plus `git-history`?
3. Read-only first for code; Markdown in read mode with Edit on ⌘E; ⌘S only or autosave?
4. File tree as a drawer tab (the drawer is not agreed yet) or as a pane?
5. Depend on MarkdownEngine (0.x, six months old) and help upstream? Is a GPL-3 or paid STTextView license ever
   acceptable, if multi-cursor is wanted?
6. Remote limits: 4 MiB per edit, 16 MB per preview, permanent delete, http images in remote Markdown.
7. To check: does the relay pass NUL bytes from `git … -z` unchanged?
