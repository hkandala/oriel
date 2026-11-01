# Phase 49: Fourteenth feedback: full chat turns, File Explorer and Git polish, statuses, tab pills

Goal: the fixes from the user's fourteenth round. The chat shows every agent message with collapsed tool calls that
load only when opened. File Explorer gets a path bar, lazy folders, icons, hidden files off by default and keys
back. Git gets staging, a live view of pending changes, better headers and empty states. The sidebar's agent
states follow t3code. Tab pills animate on open and close as in Rex. The palette groups its commands.

Design: [Chat view](../../docs/content/docs/ui/chat-view.mdx), [Plugins](../../docs/content/docs/plugins/index.mdx),
[Sidebar](../../docs/content/docs/ui/sidebar.mdx), [Window](../../docs/content/docs/ui/window.mdx). The user's
words are quoted; the decisions under them are the orchestrator's. Where this file and a design page disagree,
this file wins (each track updates the pages it changes; the docs pass checks them).

Tracks push straight to main (the user's word: "you can push directly to main"), each change after its own review
and green checks on its exact head (`make lint build test`, a chosen-tests CI run of the classes it touches).

## Track A: the chat (items 1–2)

Files: `Oriel/Chat/**`, the chat's tests.

1. **Every agent message, tool calls folded.** "chat loads much better now, one improvement, i think right now we
   show only last assistant message and do not show any intermediate messages, let's change that to show all
   assistant messages, and let's actually drop the dropdown to select detail level replies only etc. so how it
   should work is we show all assistant messages and tool calls in between are collapsed with summary and arrow to
   expand like how we show in activity view right now and lazy load the tool calls when its expanded. so by
   default only assistant messages and tool call summaries are shown and tool calls can be expanded, the lazy load
   of tool calls is important to prevent load on chat view for large transcript, coz including all tool calls by
   default in chat view even if its collapsed will add load to the chat view and makes it laggy".
   - The `Replies only ⌄` pill and its levels go, with their setting and code.
   - A turn shows each agent text message as its bubble, in order. Each run of tool calls between two messages is
     one summary row ("Ran 3 commands, read 2 files ›", the activity view's words and chevron).
   - A summary row holds only its counts. Its tool rows are made (parsed and laid out) only when it is opened,
     and dropped again when it closes. Measure the first layout and the scroll p95 on the 115 MB transcript
     before and after; they must not get worse than today's replies-only numbers by more than 10%.
2. **Show Earlier.** "show earlier button is overlapping on the message, let's make it such that there is space
   between last message and show earlier and also let's show a loader when show earlier is clicked and things are
   loading". The button sits in its own row with the chat's row gap above and below. While the earlier rows load
   it shows a small spinner in place of its words.

## Track B: File Explorer (items 3–15)

Files: `plugins/explorer/**`, its manifest, the header code it needs (`Oriel/Plugins/Header*.swift`), its tests.
Owner of the shared syntax colors (item 11) and the sidebar slide (item 14) that Git also uses.

3. **Folder color.** "can we change the colors of folders in file explorer plugin, let's make it similar to macos
   folder icon blue color". Folder icons in the tree take the Finder folder blue (light and dark).
4. **Double-click a folder.** "double clicking on a folder should make it root".
5. **Path bar.** "the root selection view is not good, can we show like a path address or something where user can
   type in the path or remove the path to go back etc so they can navigate easier instead of dropdown, when not
   highlighted it should show some short view of path instead of full absolute path like how browser address bar
   currently does yk, also lets add at the top .. thing and double clicking on that should take to parent folder
   and make it root". The root control becomes a field like the browser's address bar: at rest it shows the short
   path (`~/code/oriel`, the last parts when long); clicked, the full path, editable, with Return to go and Escape
   to cancel; a path that is not a folder shakes and stays. The tree's first row is `..`; double-click makes the
   parent the root (at `/` it is not shown).
6. **⌘F.** "clicking cmd+f in file explorer should activate filter input".
7. **Gap under the header.** "let's add some padding between first folder and the header".
8. **Hidden files.** "by default hide the hidden folders and have a option on the top right beside the collapse all
   button to toggle between showing and hiding hidden files with default as hidden". A header toggle (eye icon)
   beside Collapse All; the choice persists in the card's state.
9. **Speed.** "file explorer still takes good amount of time to load certain directory, is it possible to cache the
   data or may be optimise it better, may be we can load nested folders info dynamically if that's the reason
   loading is taking time, from what i see pretty much entire folder tree is loaded, we can optimise with lazy
   loading any nested folders". Load one folder level at a time: a folder's children are listed when it opens.
   Git status for the tree stays one call. Measure the tree's open time on a big repository (this repo, and a
   folder with node_modules) before and after.
10. **File icons.** "also i don't see file icons anymore now, before i remember seeing icons based on file types,
    can we bring that back". Find where they were lost (phase 47's move) and bring back the per-type icons.
11. **Syntax colors.** "for files and diff syntax coloring, what coloring are we using? can we use default pierre
    diffs shiki style or something? let's go with whatever syntax coloring it provides by default, regular file view
    and diff view should have same syntax coloring btw". The diff's colors are `@pierre/diffs`' default Shiki themes
    (light and dark). The File view's CodeMirror takes the same token colors. Write which themes in the Findings.
12. **Markdown edit keeps its look.** "in markdown edit mode, i understand on selecting certain line we show its
    syntax, but for other lines can't we keep regular markdown rendering? like when i go to edit view from read
    view, everything should look same other than whatever active line i am if that makes sense. right now i see all
    markdown styling is lost and for active line i see additional syntax stuff, btw i notice this more with bullets
    and lists". Edit mode is a live preview: every line except the one with the caret looks as in read mode
    (headings, bold, links, code, bullets and numbers, task boxes, quotes, tables); the caret's line shows its
    Markdown marks. Switching modes moves nothing on screen.
13. **Open With.** "open with button in file previews should show the system default app for that file type first,
    with other apps in dropdown, verify if that's the case or not". The button opens in the default app
    (`NSWorkspace.urlForApplication(toOpen:)`), shows its icon and name; the menu lists the others. Write in the
    Findings what it did before.
14. **Sidebar slide.** "in markdown sidebar, can we have slide in and out animations?". The Markdown outline
    sidebar slides in and out (about 0.25 s, the system ease). Git's sidebar uses the same code (item 26).
15. **Arrow keys.** "another one in file explorer, as soon as file explorer is opened, with arrow keys i should be
    able to navigate across tree, with border showing on highlighted one, i remember it used to be shown before now
    i can't move around file tree using arrow keys". The tree has the keyboard when the card opens or is clicked;
    ↑↓ move, → opens, ← closes or goes to the parent, Return opens the file, and the focused row shows its ring.

## Track C: Git (items 16–28)

Files: `plugins/git/**`, its manifest, its tests (header changes go through Track B's header owner if they touch
Swift; coordinate by message).

16. **More commits.** "git commits should have show more button to load more commits".
17. **Space between sections.** "let's have some separation between history and current changes section".
18. **No changes.** "also when no changes are there, let's just show no changes, right now it shows like Changes and
    No changes in the next line" and "actually don't even show message input and commit when no changes, we can
    just show like some placeholder with some icon or something and says no changes or something similar". With no
    changes the section is one placeholder: an icon and "No changes". No header, no message box, no Commit.
19. **Fetch, Pull, Push.** "for fetch pull and push, along with icons let's include text and make them like
    buttons". Bordered buttons with icon and word.
20. **Staging.** "we should have option to stage unstage etc and then commit". Staged and Unstaged groups; each row
    stages or unstages on a hover button, each group has Stage All / Unstage All; Commit commits the staged files
    (or all when none are staged, as today, saying so on the button).
21. **Branch icon.** "can we change the git branch icon in general, i don't like the current icon we have its used
    for both plugin icon and for the branch selection, use the one similar to what we use for branches in pi-footer
    branch icon". pi-footer uses Material Design Icons' `source-branch` (U+F062C). Use that shape (an SVG of
    `mdi-source-branch`) for Git's plugin icon and its branch control.
22. **Diff file headers.** "diff view file headers are not very good, can we improve it and make it fit to our ui
    design better". Match the card headers: the file icon, the name, the folder dimmed, +/− counts in the system
    green and red, the glass row height and corner radius of our design. Show a before/after picture in the
    Findings.
23. **Word wrap.** "can we also have word wrap toggle beside unified and side by side". Persists in state.
24. **Commit page.** "when a certain commit is opened, let's show commit message in its title, also better to show
    commit data and time, description and other metadata may be". The card's title is the commit's subject; the
    top of the diff shows the subject, the body, author, date and time (relative and absolute), the hash (copy on
    click) and the parents.
25. **Live pending changes.** "we should have a way to see current diff of pending changes in working tree which
    reloads automatically, basically with that view open when agent is running and making changes i should see
    live view of what changes are being done if that makes sense". A "Working Tree" place shows every uncommitted
    file's diff, one under another. It reloads while in view: poll `git status` cheaply (every 2 s, only while the
    card shows), and redraw only the files whose content changed, keeping the scroll position.
26. **Sidebar slide.** "let's have similar slide in and out animations for sidebar". Same code as item 14.
27. **Not a repository.** "for git plugin when you open in folder which is not git repo it throws fatal error,
    let's show proper message its not git repo instead of throwing fatal error". A clear empty state: an icon,
    "Not a Git repository", the folder's short path, and an Initialize Repository button (runs `git init` after a
    click).
28. **Header buttons as buttons.** Covered by 19; the controls stay in the manifest header.

## Track D: the window and the app (items 29–33)

Files: `Oriel/Views/TabBar.swift`, the chooser, the palette, `Oriel/Plugins/PluginsPanel*` and the herdr side of
plugin panes, their tests.

29. **Chooser wraps.** "in the new pane can we cycle the selection like if i am at terminal and press up arrow i
    should be at Git". ↑ on the first row goes to the last, ↓ on the last to the first.
30. **Show a plugin in New Pane.** "for new plugins user should have option to choose if they want it to be shown in
    new pane or not by default". The Plugins panel gets a "Show in New Pane" switch per plugin, and the trust prompt
    of a new plugin has the same checkbox, on by default when the plugin declares a chooser entry. Stored in
    `settings.json`.
31. **Placeholders always there.** "when i open the herdr in regular terminal for these sessions with plugin panes,
    i should see placeholder all the time, for some panes i see, and for some i don't. we should make sure to show
    the placeholder all the time, if that process is quit or something let's rerun and show it again, i think this
    would especially if herdr session is stopped and restarted ig". Every browser and plugin pane runs the
    placeholder. On each snapshot, a browser or plugin pane whose foreground is not the placeholder (a fresh shell
    after a herdr restart, an ended process) gets it again (`pane run`, once per pane per process; never into a pane
    whose foreground is another program). Find why some panes lack it today.
32. **Palette groups.** "now that we have too many commands in cmd+k, can we group them better based on their
    category or type". Sections with headers (for example: Tabs, Panes, Sessions, View, Plugins, Go To, Help;
    choose the set from the actual commands). Typing a query shows the best matches first across groups, each with
    its group's name dimmed.
33. **Tab pills on open and close.** "check the above scrawl, check the original video instead of snapshots, i
    showed animation of tabs for cmd+t and cmd+w like opening new tab and closing tab, right now we don't have any
    animations with tab pills on create and close, let's try to inspire from this and include it in ours". The
    recording (`~/Library/Application Support/scrawl/captures/scrawl-1793524714590-1c27.scrawl/recording.mp4`,
    0:12–0:27; a strip of frames at `/tmp/sc49/tabs1.png`) shows Rex: on ⌘T the selected pill glides from the old
    tab to the new slot at the end while the new tab's pill grows in; on ⌘W the tab's pill shrinks away, the tabs
    after it slide left, and the selection glides to its neighbor. About 0.2 s, a spring without bounce. Only the
    tab bar animates; the page still swaps at once (phase 48). Study the video frame by frame before building.

## Track E: agent states (item 34)

Files: `Oriel/Views/Sidebar*.swift`, the state capsule in the card header, the agents view, their tests.

34. **States as in t3code.** "i don't see any changes to agent statuses changes similar to t3code, you mentioned
    you made changes earlier, can we fix that, let's check t3code and inspire from it on how it shows agent
    statuses on sidebar etc and improve it". Read t3code's source (github.com/pingdotgg/t3code: the sidebar's thread
    rows and their status) and record in the Findings how it shows working, waiting for input, done and error (shape,
    color, motion, words, where). Then make Oriel's sidebar rows, the card header and the agents view follow it.
    Show the user a picture of the result before pushing.

## Findings

### Track E

- **t3code (b50d8a1b, `SidebarThreadRow.tsx`, `Sidebar.logic.ts`).** A thread row's first line ends in a status slot:
  a 16 px lucide icon and the word, 12 px medium, in the status color, no fill. Working: `circle-dashed`, info blue,
  with its time counting each second ("Working 42s", "3m", "1h 5m"). Waiting for input: `message-circle-question`,
  indigo, "Input"; approval: `shield-question`, amber, "Approval". Done (a finish not seen): `circle-check`, emerald,
  "Done". Error: `circle-alert`, red, "Failed" (amber "Limited" for a usage limit). A settled thread shows no status,
  only its age ("5m"). No motion in the sidebar; only the compact pill (the palette) pulses its dot (opacity 1 → 0.5,
  2 s, stepped). Rows that need nothing recede (normal weight, 75 % text, working rows at 0.7 opacity); rows that
  call for the user stay medium and full strength. The chat header shows no status.
- **Fix.** One `StateLabel` (symbol, word, Working's time) replaces the 6 pt dot of the card header, the capsules of
  the Agents view, popover, hover card and overview, and the workspace row's leading state slot: the label now ends
  the row's first line, as t3code's status slot. Idle shows nothing (the Agents view shows the age). Needs you and
  Done rows have their name in medium weight. The tab bar keeps Rex's working dots and badges (phase 33).
- **Decisions.** herdr has one "blocked" for both input and approval, so Oriel keeps its word "Needs you" and its
  amber, with t3code's question bubble. herdr reports no error, so "Error" stays the chat card's own. The symbol
  does not move, as in t3code's sidebar: the counting time shows the work. The card header shows no time (its row is
  full). A workspace's time is the longest of its tabs' front agents'.
- **Cost.** Each working label ticks once a second for its first minute, then once a minute, all on the same
  wall-clock second, so a hundred working agents make one update a second at most, not a hundred.
- **Pictures.** Before and after, the same four states: `/tmp/oriel-shots/t49e/before-sidebar-crop.png` →
  `after-sidebar-crop.png`, `before-agents-crop.png` → `after-agents-crop.png`.
- **For the user.** The time counts from when this app saw the agent start working: after a relaunch, or on
  another Mac, an agent that has worked for 20 minutes starts at 0s.
### Track D

- **Decisions, palette (32):** the groups are `Command.Group`, the Keyboard Shortcuts panel's: Tabs, Workspaces,
  Sessions, Panes, View, Edit, plus Plugins (Plugins…, Reload Plugins, a plugin card's Reload Plugin, Web Inspector,
  Show Log). On an empty field each group's places (the tabs, workspaces, sessions) come first in it, then its
  commands, so there is no Commands header and no header twice. A few keyless commands got their group (Close Other
  Tabs, Rename Tab, Rename Workspace, Detach Pane, Copy, Paste, Save under Edit). Typed rows keep their order and show
  the group dimmed after the title; it is the row's accessibility value, not part of its label. The Shortcuts panel
  shows Plugins only over a plugin card. Pictures: `/tmp/oriel-shots/t49d/palette-{root,typed}-{before,after}.png`.
- **Decisions, chooser (29):** ↑ and ↓ wrap, also when held.
- **Decisions, Show in New Pane (30):** `settings.json` keeps the ids the chooser leaves out (`hideInNewPane`), so a
  plugin with a chooser row is shown until the user turns it off. The panel's switch sits on each such row; the
  install dialog has it as the NSAlert's checkbox (`suppressionButton`), the card's trust prompt as a checkbox that
  writes at once. ⌘K's Open ‹chooser› Here stays. Picture: `/tmp/oriel-shots/t49d/plugins-panel-after.png`.
- **Cause, placeholders (31):** after a cold restart herdr brings each pane back as a login shell under its label
  (spiked on 0.9.5: `-zsh`, a new terminal id); a pane an agent labels with the oriel-panes skill keeps its shell
  unless the agent runs the optional `placeholder.sh`. When the placeholder process ends, herdr closes the pane, so
  that case needs nothing. **Fix:** each `pane.process_info` answer for a browser or plugin pane with only its shell
  in front types ` exec <envelope of exec + placeholder argv>` and Return, once per shell pid; a label change asks
  again, and a labeled pane running another program gets one more look 5 s later (a slow startup).
- **For the user:** the pi-hkandala `oriel-panes` skill's optional `pane run placeholder.sh` step now races with the
  app's own (harmless: the second line goes into the placeholder's `cat`); drop the step there.
- **Decisions, tab pills (33):** read from the recording at 60 fps: on ⌘T Rex's marker slides about 180 pt in
  0.07–0.15 s, ease-out, no bounce, while the new tab's content shows in its slot; on ⌘W the closed tab's content goes
  at once and the marker glides to the neighbor. Built as a custom `Transaction.tabMotion` that Page.newTab and
  Page.close set around their synchronous stand-in, hide and selection; only the tab bar turns it into
  `.smooth(duration: 0.2)` (the page, the cards and the sidebar never animate, which FlickerTests' new ⇧⌘W step
  checks with `-recordFrames`). A new tab scales and fades in, a closed one out; the marker glides. herdr's tab keeps
  its stand-in's view (`Ahead.born`), so its growth is not cut short when the snapshot lands. No motion when the bar
  changes workspace (a new tab in another workspace, a workspace's last tab closed), for a close that asks first, or
  with Reduce Motion. Pictures (CI, `-forceMotion`, frames as recorded): `/tmp/oriel-shots/t49d/tab-pills-after-strip.png`
  and `tab-pills-before-strip.png` (the old bar: every change in one frame).
- **For the user:** when the tabs overflow the bar, a new tab's scroll into view lands just after the glide (one
  small step at its end); check ⌘T and ⌘W by hand with Reduce Motion off.

### Track B

- **Cause, item 9 (speed).** The tree already listed one folder at a time. Each listing also ran
  `git status --ignored -- .`, which walks the whole repository (ignored folders too) to mark the ignored names,
  plus a `git rev-parse`. **Fix:** a listing asks `git check-ignore` about its own names only, in the same shell
  call; git's letters stay one `git status` for the tree. Measured with the listing's exact commands (median of 7, a
  load of about 250): this repository's root 2374 → 135 ms, `web/` 354 → 105 ms, `web/node_modules` 264 → 162 ms.
- **Cause, item 10 (icons).** Not phase 47's move: phase 46's home (`db3bb45f`) set `@pierre/trees`' `minimal` icon
  set and drew one `doc` glyph for every file. **Fix:** the default `complete` set (per-type icons in their colors);
  folders keep their own glyph, now in the Finder's folder blue (sampled from `NSWorkspace`'s folder icon: `#76D0F6`
  to `#52B9E8`, the same in light and dark).
- **Decisions, item 5.** The root is a `field` with `"style": "path"` in the manifest, drawn natively like the
  browser's address. Return sends the typed path, tidied (`..`, `.`, `//`; `~` expanded on This Mac, a remote
  machine takes only absolute paths); the page checks it is a folder
  (`files.info`) and moves, else `controls.set("root", { refused: true })` shakes the field. Choose Folder… stays, as
  the folder icon before the path. `..` is a row above the tree (not a tree row), so it never moves with the
  keys; `controls.set(id, { focus: true })` gives ⌘F's filter the keyboard.
- **Decisions, item 8.** Hidden files are names that start with `.`; the eye (`hidden-files`) is a header toggle, so
  its value stays with the card's controls. **Item 15:** the tree takes the keyboard on the page's focus (when the card
  opens or gets the keyboard); the ring was there but drawn 0 px wide, now 1.5 px in the accent.
- **Item 11.** `@pierre/diffs` already used its defaults, Pierre Light and Pierre Dark (`@pierre/theme`); File's
  CodeMirror now maps each tag to the same TextMate scope's color (keywords `#D32A61`/`#FF678D`, strings
  `#199F43`/`#5ECC71`, functions `#693ACF`/`#9D6AFB`, types `#A631BE`/`#D568EA`, variables `#D47628`/`#FFA359`, …).
  CodeMirror has one tag for keys, so JSON keys and CSS properties take the variables' orange, where the diff has
  `#D5512F`/`#FF855E` and `#08C0EF`.
- **Item 13.** Open With already opened the default app first, with the others in its menu, but showed only the
  app's icon: it now shows the icon and the app's name.
- **Decisions, item 12.** Read and Edit are one CodeMirror view (a live preview), so a switch moves nothing but the
  caret's line: Read is the view not editable with every line drawn, Edit shows the marks of the caret's lines.
  markdown-it draws only tables and HTML blocks (block widgets, the source while the caret is in one). Front matter
  shows in Read too (dim monospace, as Edit). Known limits of the live preview against markdown-it's page: reference
  links (`[text][ref]`) are no links and their definitions stay shown; inline HTML and entities show as written; a
  setext heading keeps its underline; a list item's continuation lines do not hang; `1. 1. 1.` shows as written; a
  second heading of the same name has no `-1` anchor.
- **Runs.** Chosen-tests CI runs, green on the pushed heads: 41297000504 (89fb18c9: FilesTests, FileTests, HeaderTests,
  MarkdownTests), 41298939441 (fa7d058c: MarkdownTests, FilesTests, the file card). CI's screenshots draw no web
  content, so the pictures of the pages come from the built plugin in headless Chrome with a stand-in API, before
  (main at 7603a9c4) and after: `/tmp/oriel-shots/49b/before-harness-{read,edit,tree}.png`,
  `after-harness-{read,edit,dark,tree,treed}.png`; row 2 from CI: `before-file-explorer-home.png`,
  `after-file-explorer-home.png`.
- **For the user.** Scroll the tree with the wheel while another pane has the keyboard, then click a row: the click
  opens that row (the tree no longer jumps to its old row first). In Markdown, select text in Read and copy it; switch
  Read ↔ Edit (⌘E) on a long file and see that only the caret's line changes. Type a wrong path in the root field.

### Track C

- **Decisions (home).** No changes is one placeholder (`checkmark.circle`, "No changes"): no lists, no message, no
  Commit. Stage All and Unstage All are words, not icons: staging was there but hidden, which is why the user asked
  for it. With none staged the button reads Commit All and runs `git add -A`, then `git commit` (a failed commit
  leaves the files staged, which the home shows). Show More reads `git log -n 1000`, then 1500: the graph's lanes need
  every row before, so it asks for the whole longer list again.
- **Decisions (icons, buttons).** mdi `source-branch` is an app symbolset (`source.branch`, Regular-M from the 24 pt
  path), so it takes font sizes and weights as SF Symbols do. `Image(symbol:)` and `NSImage.symbol` take the app's
  own symbol of that name, else the SF Symbol: the plugin icon, the branch menu, the chooser, the palette, the trust prompt, the
  miniature and the sidebar's branch use it. Fetch, Pull and Push are the system's small bordered buttons
  (`"style": "bordered"` on a header button).
- **Not a repository.** The home asks `git.root` only after `git.changes` fails: null shows "Not a Git repository",
  the short path and Initialize Repository (`git init -q`, a new `git.init` call); another failure still shows git's
  message.
- **Cause (item 25).** The Uncommitted diff did follow the work tree, but only for new files: CodeView keeps a record
  whose `version` did not change, and the items had none, so a file already shown kept its old text while the list's
  counts moved (`/tmp/oriel-shots/live-before-crop-2.png`). **Fix:** each item's version goes up when its text or fold
  changes, and an unchanged file keeps its old `fileDiff` object, so only changed files draw and the scroll stays
  (`/tmp/oriel-shots/live-crop-2.png`).
- **Decisions (item 25).** No new 2 s `git status` poll: `files.watch` already calls back only while the card shows,
  with FSEvents on This Mac and the 2 s check on a remote machine. The place is named Working Tree (title and label
  word); a bordered Working Tree button on the home's row 2 opens it, disabled when git cannot read.
- **Decisions (items 22-24).** The file header is pierre's `renderCustomHeader`: a 30 pt row in the home's row style
  on the 40 pt opaque sticky band (`diffHeaderHeight: 40`). The commit's subject is `document.title`, which the app
  shows as the card's and the tab's title (`WebCard.title`): no new API. A commit's facts come from a new
  `git.show` (`%s` as the history's, `%b`). Word Wrap is a header toggle; Side by Side always wraps, so it is
  disabled there.
- **Cause (Word Wrap).** CodeView kept the options object it was made with, and the page changed that same object
  before each `setOptions`, so CodeView saw no change and drew nothing new (a toggle on, lines unwrapped). It gets a
  copy now. A plain probe page with the same options wrapped; only an on-screen web view runs `requestAnimationFrame`.
- **Narrow cards.** On CI's 1x screen a half-width card cut "Fetch" to "F…": the row's bordered buttons drop their
  words together when the row has no room for all of them (one `ViewThatFits` over the row). A commit card's
  VoiceOver name is its subject, as its title.
- **Item 26.** The diff's file list is Track B's shared `oriel-sidebar` (card.css): `data-closed` slides it out in
  0.25 s, and Previous / Next's place is kept after the slide (`transitionend`).
- **For the user.** Classic and light: `/tmp/oriel-shots/t49c-classic-light.png`. The file headers use `doc` for
  every file, as the home's rows: File Explorer's per-type icons live in its own bundle.
- **Pictures.** Home: before `/tmp/oriel-shots/t49c-home-before.png`, after `/tmp/oriel-shots/t49c-home-after1.png`.
  Diff, commit page, Working Tree: before the bottom right of the first, after `/tmp/oriel-shots/t49c-diff-after2.png`.

### Track A

- **Decisions (item 1).** One view: the user's message, then every reply, todo list and note in order; each run of
  tool calls between two messages is one closed line of its counts with a chevron, its thinking among its steps;
  "Worked ‹time›" under a finished turn with tool calls (kept from Replies only). Thinking with no tool call in its run
  has no row. A run's line holds only its range in the history's entries: its counts are worked out for the 40 rows
  shown, its rows are made from the history when it opens and dropped when it closes. The levels, their pill, the
  `chatLevel` setting and `ChatLevel` are gone. "Parsed" in the brief read as the run's rows: the transcript parsers
  still read each call's input and output whole (the counts need the calls, and they run off the main actor).
- **Measured** on this Mac's 117 MB pi session (4,474 entries), Release builds of main and the branch with a
  temporary display-link probe, alternating. `rows()`: main 3.25 ms (Replies only, 1,030 rows), first try 4.77 ms
  (2,132 rows, counts for every run), now 3.04 ms. The first layout (the worst frame in the second after the rows
  show) and a scroll of 240 frames up and back (20 pt a frame), medians of 6 runs each: main 126 ms; the branch with
  the block of 40 rows 141 ms (+12 %: more of the 40 rows are long replies); with 34 rows 120 ms against main's 122 ms
  in the same hour. **Decision:** the block is 34 rows. Scroll p95 10.0 ms in every run on both (the display's
  frame), p99 10–20 ms on both. The Mac's load was 30–300 during the runs, so single frames move by ±20 ms.
- **Cause (found on CI, a78a8705): the Scroll to Bottom button never showed.** SwiftUI runs a `ScrollViewReader`'s
  content again only when what its closure captures changes; `@State` read only inside it is no dependency of the
  body (file logs in a Release build: the body ran with `atBottom` false, the overlay closure did not). Main got away
  with it because its closure captured a value that changed each body. **Fix:** the state and environment values the
  content draws with (`atBottom`, `held`, `earlier`, `width`, the error color) are read into `let`s before the
  closure. A lesson.
- **Cause, the reviewer's blocker: Show Earlier jumped.** With the button a row of its own, holding the place by the row
  at the top put that row at the very top, 54 pt up, hiding the spinner. Tried and dropped: the bottom anchor for size
  changes (rows pushed 2,250 pt down: it did not hold) and pinning by row id (54 pt off, not every time). **Fix:** the
  scroll position is a `ScrollPosition`; the click pins the current offset, and when the rows come the offset grows
  by the content's height change. The UI test checks the gap under the button from one snapshot and that the top row
  stays within 2 pt; it failed on the 54 pt bug and passes. **Cause, the split test then failed on CI 3 of 4 runs**
  (it passed here): the `ScrollPosition` binding named the row at the top only as a scroll began on CI (a diagnostic
  run's event log: one name, then none while 150 rows went by), so a split brought back a row near the bottom. The row
  at the top now comes from `onScrollTargetVisibilityChange` (the first row with any part in view); the position is
  only kept for the offset.
- **Decisions (item 2).** Show Earlier is the stack's first row, centered, with the messages' top padding above and the
  10 pt row gap under it. A click swaps its words for a small spinner (same capsule size) and loads the rows on the run
  loop turn after the commit that draws the spinner (a one-shot observer after Core Animation's commit, then a wake-up;
  not `afterCommit`, which also fires on a click's tracking loop exit, before the commit).
- **Pictures.** Before/after on the 117 MB session, scrolled up mid-chat (`sips -Z 1200` of the window):
  `/tmp/oriel-shots/t49a-before-5-up.png` (Replies only: one reply per turn) and
  `/tmp/oriel-shots/t49a-after-5-up.png` (every message, runs folded as "Ran 2 commands ›").
- **For the user.** Open a long chat: every reply shows, and each run of tool calls is one closed line; open one and
  close it. Scroll up and click Show Earlier: the spinner shows in the button, then the rows come above without moving
  what is in view. Scroll up a little: the round Scroll to Bottom button shows. Not checked by hand: that the spinner
  draws before the rows lay out in a build with no accessibility client (the tests always run with one).

### Final review fixes

- **Docs pass.** The pages matched the tracks' work except: the tab marker's glide (D42, platform), D94's Commit All
  and Initialize Repository, D95's 34 rows, "live" overview tiles, a cover picture that is gone, the kept terminals'
  20 and 10 (now 25 and 12), the hold's copy, the Git header and `main.ts` sketch in building.mdx, `check-ignore` and
  `git show` in the herdr calls, a swipe preview in Future work, and which labels show Working's time.
- **Fix (Git).** A live Working Tree reload reset Previous and Next to the first change; a file-list slide ran its
  keep three times (two frames and one `transitionend` per property); a rename kept a stale "from …" header (the
  header cache now follows the file diff object). Show More disables itself; a long word wraps in a commit body.
- **Fix (File Explorer).** Read was not read only (a drag or a drop edited the file); a fence not closed yet hid its
  last line; Show in File Explorer on a dotfile did nothing with hidden files off (it turns the eye on); a relative
  path in the path bar made a relative root (it now goes from the root: `src`, `..`; an empty Return is the root);
  an Edit click on a table's empty link reloaded the page.
- **Fix (app).** Menu items, header toggles, the path field and the sidebar branch draw `source.branch` (they used
  `Image(systemName:)`). The placeholder starts with ⌃U, so a line half typed in herdr's TUI does not run in its place
  (spiked on zsh). A failed `settings.json` write from Show in New Pane shows in the Plugins panel.
- **Tests.** PluginTests waits for the card's shell title, not `sleep 2`; FollowTests' `pgrep` loop fails after 20 s;
  FilesTests waits for the tree's keyboard before the arrows; GitTests clicks row 2's Working Tree.
- **Runs.** Chosen tests on ff27bf22, green on the first try: 41307651798 (FilesTests, MarkdownTests, FileTests) and
  41307657905 (GitTests, PluginTests, HeaderTests).
- **Cause (red checks since phase 47).** Phase 47 took HerdrKit from 122 to 140 tests, many of them spawning git,
  npm, esbuild and sh, all started at once beside the rest. On CI's 3 cores a client's first reads then took over
  3 s, and every wall-clock bound flaked: HerdrClientTests' pacing (a first read under 100 ms, 3–6 spaced reads a
  second, a write's read within 120 ms) on every push, the 8 MB line's 6 s now and then. **Fix:** HerdrClient takes
  its spaced read's wait as a closure; the pacing tests hold it in a gate and count reads (no wait before an event's
  read, one read while the wait holds, its deadline the read's start plus the spacing, a write's read with the gate
  shut); `eventually`'s bound is 20 s (a failure's limit only); the line split is `LineBuffer`, timed against a ten
  times shorter line (it fails with the old scan put back). A lint rule (`wall_clock_bounds`) rejects a time bound
  in HerdrKit's tests. 83912e9a carries the pacing fix under a wrong subject (an amend after a failed hook).
- **Decisions (nits left).** The page's view id stays herdr's tab id (keying it by `Ahead.born` keeps placed and held
  state across the stand-in's swap: a layout motion risk for no visible gain). `fitHidden` keeps its copy of the card's
  terminal room (PaneCard lays out with padding, not a function), and fits only the selected workspace. A working
  workspace row keeps its hidden label copy (it measures the growing time; both tick in the same update). Show
  Earlier's offset is not guarded against a reply growing in the same run loop turn (a one-turn window). Git's 500
  stays in Git.log and PluginCalls; `labeled(words:icon:)` keeps two flags (three states); `overflow()` keeps setting
  Word Wrap's enabled state (it also runs at load).
