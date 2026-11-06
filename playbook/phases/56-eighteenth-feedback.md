# Phase 56: Eighteenth feedback: instant switches, a File Explorer status bar, two Markdown modes, one way to open links

Goal: the fixes from the user's eighteenth round:

- Tab and workspace switches never wait for a card's content, and cards keep their state.
- The palette gets a matching search field and Open File, Open Working Tree and Open Commit.
- New Pane shows its folder at once.
- The browser loads pages on a remote machine again.
- File Explorer gets a proper status bar and its fixes.
- Markdown gets two modes.
- Links open the same way everywhere.
- Git's diff gets a filter and hunk jumps.
- A new tab opens beside the current one, with no flicker.
- A check of the notifications plan against the code.

The user's words are quoted; the decisions under them are the orchestrator's. Screenshots in `.build/fb56/` (not
committed):

| File | Shows |
|---|---|
| `3.58.32.png` | the rename field's border clipped on the sides |
| `3.59.59.png`, `4.00.04.png` | after a click on the Git icon, icons turn into grey squares (the footer, the filter's close button) |
| `4.09.26.png` | a sticky folder over another folder's name |
| `4.12.02.png` | whitish selected text in a file card |

Tracks run in parallel and push straight to main after review and green chosen tests. The phase ends with two full
runs and on-demand on the final head.

## Track A: switches never wait for a card (item 1)

1. "like similar to the issue where when chat is open activating that tab or going to that workspace used to be
   significantly slower, now i see that issue when a markdown file opened in file explorer as well. i think this delay
   happens whenever there is something heavy? i think we should make the tab switches and workspace switches
   independent of the pane content, we can show a loader if we want in the pane but switching to the tabs or
   workspaces should be instant, also the previous fix we did for chat kinda refreshes the entire chat window losing
   its scroll posiition and loaded chat messages from show earlier, is there a way to preserve these pane contents
   separately without losing, basically something like independent processes".
   - Measure first: a tab and a workspace switch with a chat view, a big Markdown file in File Explorer and a Git
     diff, with signposts. Find what blocks the switch (a body that rebuilds, a web view that reattaches, a layout).
   - The switch draws the tab strip, the sidebar and the card frames in the same frame; a card's content may show a
     quiet placeholder until it is ready.
   - Cards keep their state across switches: the chat keeps its scroll place and the rows loaded by Show Earlier;
     web cards keep their page. Kept cards are already alive (25 + 25, D46); find why they rebuild and stop it.
   - A test: a switch to a tab with each heavy card finishes in one frame budget; the chat keeps its scroll offset
     and loaded rows.

## Track B: the palette (items 2, 14, 19)

2. "in cmd+k search input is fully round with actual cmd+k border radius less round, basically search input border
   radius and cmd+k pane border radius are different making them look weird, let's make the search input as well same
   border radius as outer cmd+k one, so it looks aesthetic, and make the grey of search box little more evident,
   right now it mostly merged with rest of window and is not evident".
   - The field's corner radius is the panel's radius minus the inset (concentric), and its fill is a step stronger,
     in dark and light, Glass and Classic.
14. "if i have a file path be it any source code, markdown, image or video etc,i should be able to quickly paste in
    path and open that file, like in cmd+k we can have open file here, which asks for path and i can paste the path
    and it opens that file in respective preview one using file explorer plugin, not sure how we can achieve this with
    our plugin architecture, let me know if there are any alternative ways to achieve this, essentially i have a file
    path, i want to open that quickly somehow in some pane".
    - Palette ▸ **Open File…**: a sub-page with a path field (`~` and relative paths from the active pane's folder),
      it opens the file with its default plugin, as `ovvi open <path>` does today (the same code path). Return opens
      in a new tab beside, ⌥Return to the side.
    - Pasting a path into the palette's main field offers "Open ‹path›" as the first row when it exists on the
      machine.
19. "also similar to open file here, we should also have open working tree here to directly open working tree diff
    view and also be able to open a commit given a commit id".
    - Palette ▸ **Open Working Tree** (the active pane's repo) and **Open Commit…** (a field for a sha or ref),
      both opening the Git plugin at that view. Add the plugin arguments Git needs if it lacks them.

### Findings (Track B)

- **Fix (item 2).** The palette's field (the one at `.controlSize(.large)`) has the panel's radius, 14 pt (both
  continuous). A concentric 4 pt, the panel's 14 less its 10 pt inset, looked square to the user. Measured at 1x
  on CI, the panel's corner leaves its straight edges about 12 pt from the corner. The other fields stay capsules.
- **Cause (item 2's grey).** On the glass panel a hierarchical fill (`.primary.opacity`) is vibrant: 7 % showed 3
  steps over the panel, and 10 % only 4. The field now takes a flat Look color, `paletteField`.
- **Fix (items 14, 19).** Open File…, Open Working Tree and Open Commit… resolve through `ovvi open`'s own code
  (`AgentCall.opening`), then open with `Page.open` as the plugins' links do: a new tab, ⌥ (Return or click) to the
  side. A path is checked and `~` expanded by one `sh` call on the page's machine, so it works on a remote machine.
- **Decisions.** A filter starting with `/`, `~`, `./` or `../` is checked as a path, 150 ms after the last key;
  when it exists, **Open ‹path›** is the first row. Open Commit takes a hash or a ref: the app resolves it with
  `git rev-parse --verify` (`Git.commit`) and the label holds the whole hash, so `ovvi open git . main` works too
  and a mistyped hash is a notice. A path or commit that names nothing closes the palette with a warning notice.
- **Cause (review).** "open file" lit Open File Explorer Here: both titles start with the filter, and the tie went
  to the earlier row. A title that is the whole filter now wins the tie.
- **For the user.** Return opens in a new tab at the end until Track J makes new tabs open beside.

### Runs (Track B)

- **Runs.** The first chosen-tests run of the new test failed on a tab it never selected (a test bug); the
  review's ranking blocker would have failed it too. Green on 14670eb2 (plus a throwaway picture test): run
  42144998994, Executed 4 tests (the new one, two palette tests for the ranking, the pictures).
- **Runs (radius).** 42147208640 on 77e4114a plus the picture test, Executed 2 tests, green; at 1x the field's
  corner leaves its edges 12 pt from the corner, as the panel's does.

## Track C: New Pane's folder (item 3)

3. "on the new pane thing, showing the path, it takes a brief second before its shown and that filckers the new
   pane, it should be shown immediately, not sure why it takes time, does it wait for underlying terminal to be
   ready? we should have that path populated automatically without waiting for terminal to be ready, from what i know
   the behavior is it takes the path from the last tab or pane or something like that, see what's the exact behavior
   of original herdr on what path to load for new terminal panes, and let's infer the paths from that logic, instead
   fo waiting for terminal to load or soemthing, and keep everything greyed out, right now path is white in color, it
   should be all grey in color same as opens in text, only when clicked on it or tabbed on it, it should be activated
   as input and white in color".
   - Read herdr's source for the folder a new pane, split and tab start in; compute the same folder from the
     snapshot Ovvi already has, with no wait. The New Pane card shows it in its first frame.
   - The folder is grey like "Opens in" until clicked or tabbed into; then it is a white field.

### Findings (Track C)

- **Cause.** The folder line read only the pane's folder from a snapshot. A new tab's or split's stand-in has no
  pane until herdr answers and a snapshot comes, so the line came in a moment after the list. It did not wait for
  the terminal: it waited for herdr's pane.
- **herdr's rule** (v0.9.5, `src/app/creation.rs` `resolve_new_terminal_cwd`, with `launch_cwd_for_terminal`):
  with the default `new_cwd = "follow"`, a new terminal starts in the folder of the pane it comes from (its
  foreground process's folder, else its reported folder), else `$HOME`. `pane.split` (`src/app/api/panes.rs`
  `handle_pane_split`) follows the split pane. `tab.create` (`src/app/api/tabs.rs` `handle_tab_create`) follows the
  workspace's focused pane, but Ovvi passes the keyboard card's folder itself, so that is the one.
- **Fix.** The chooser carries that folder from its creation (`Chooser.cwd`): the split pane's (an earlier
  stand-in's chooser's for a quick ⌘D ⌘D), the keyboard card's for ⌘T, then herdr's answer's. The line shows the
  pane's own folder once a snapshot has it. The path is tertiary like "Opens in"; only the field is primary.
- **Decisions.** herdr's `new_cwd` setting (home, current, a path) is not read: it is the default `follow` on the
  user's machine, and Ovvi already overrides it for new tabs. A ⌘T in a workspace with no keyboard card passes `~`;
  its line comes with herdr's answer, as before.
- **Test.** The e2e helper gets `pause` and `resume` (SIGSTOP and SIGCONT of the throwaway session's server), so
  a test can see a stand-in before herdr answers.

### Runs (Track C)

- Chosen tests (the new test, both folder-line tests, the chooser's tab and split tests, the two quick new-tab
  latency tests): 42148700511 on the first commit, 42149551623 on the reviewed head, 7 of 7 green each. Local UI
  runs were not possible (the GUI lock was busy, then Automation Mode was off), so no red run on the old code. The
  test cannot pass on it: the old line never shows on a stand-in, and the test pauses herdr until it checks.

## Track D: the remote browser (item 4)

4. "so after the update to browser where we can flip between server and this mac, i can't laod any page in browser
   in devmv-aai, it used to load fine before, it this some regression? it works fine when i toggle it to this mac
   though".
   - Find the regression (bisect the browser commits since phase 52) and fix the cause; read only on the user's
     devvm; test with a throwaway session on a remote machine as the remote browser tests do.

## Track E: File Explorer's tree (items 5, 6, 8, 9, 10, then 7 and 20)

5. "rename border is getting clipped on the sides" (`3.58.32.png`).
6. "after i click git icon, it becomes like this greyed out, weirdly after clicking git icon cmd+f close icon also
   grays out" (`3.59.59.png`, `4.00.04.png`): icons turn into grey squares. Find why the glyphs stop drawing.
8. "right clicking on any folder should show rename option as well, as we support that now".
9. "also cmd + arrows work fine as long as we go to file editor view, i think there cmd arrows are used to move
   cursors and that overrides ig, let's figure out better shortcut for it so it works even in file previews, let's
   use that same shortcut for history navigation in both file tree and git, make sure that new shortcut works in any
   view".
   - Back and Forward become ⌘[ and ⌘] (Finder, Safari and Xcode use them; Ovvi has no plain ⌘[ ⌘]). They work in
     every view of File Explorer and Git, including an editor, where they replace CodeMirror's indent keys. Keep
     ⌘← ⌘→ where no text field has the keyboard.
10. "the sticky folders gets grey background, let's not show any grey background to it, also when there is another
    folder behind it, they are overlapping, we should fix that, for files it deosnt' overlap, only for folders it
    overlaps" (`4.09.26.png`).
7. and 20. The status bar, after the user picks a mockup from Track G: "can we improve the overall footer for git
   better, it looks bad, and not fitting to the view, use branch icon and then show branch name, then show line
   chanegs + and - and then pull and push things, also make those pull and push as buttons, show them only when there
   is something to pull, or something to push, and show fetch icon button all the time to fetch, and at the right edge
   show a button like open git or something like that which opens the git plugin" and "also in the file explorer,
   make the footer as proper status bar instead of just for git, we can show some useful info related to that
   folder, give me some ui mockups for the footer including git and with no git etc, and i can confirm which on to go
   with".

### Findings (Track E)

- **Cause, item 6.** The app sets the page root's inline style to its colors with each theme (`WebCardContent`'s
  `onChange(initial: true)` runs again whenever the card's view comes back, as after Open in Git's new tab). File
  Explorer kept its SF Symbol masks (`--sf-*`) in that same inline style, so they went and every mask drew a full
  grey square. **Fix:** the masks live in a style sheet of their own; the API's `Theme` says to do so. No test: it
  would read mask pixels, and CI's screenshots draw no web content.
- **Cause, item 5.** The rename field fills the row's name section, which clips what goes past it: the outline
  outside the box lost its sides. **Fix:** the outline sits inside the box.
- **Cause, item 10.** The tree's rows are transparent (the card shows through), and the band under the sticky
  folders used `--card`, a measured stand-in for Glass's translucent card fill that was 18 steps off on the user's
  screen (`#34` on `#22`); no stand-in matches every wallpaper. A nested sticky folder that the next folder pushes up
  slides under its parent's transparent row: both names drew. **Fix:** no band at all. What scrolls under the stack
  is clipped away (the list above the stack's bottom, a pushed folder above its parent's bottom), after each scroll
  and each draw of the tree, in the same frame.
- **Item 8.** A row's menu adds Rename (not on `..`), the same rename as Return.
- **Decisions, item 9.** ⌘[ and ⌘] already go Back and Forward in every view, the editor too (the web view's key
  equivalent runs before CodeMirror's indent keys, for every plugin card), and the Back and Forward tooltips name
  them. FilesTests pins ⌘[ in the editor; no code change. Only a row 2 field (the root) leaves it to Select Pane.
- **Items 7 and 20: the user's pick, C without the empty states.** The bar shows in every folder: the machine on a
  remote one, the root's folders, files and hidden names, and in a repository the branch, +/− lines, Pull and Push only
  when there is something to pull or push, Fetch, and Git at the right edge (Track H's open rule). Outside a
  repository the right side is empty; a clean one shows no counts. **Decisions:** the lines come from
  `git --no-optional-locks diff-index --numstat HEAD` (porcelain `git diff` rewrites the index and takes
  `index.lock` under an agent's `git add`), so untracked files count once added. The mockup's free disk space is left
  out (no API has it). Git's own symbols for Fetch, Pull and Push. A branch with no upstream shows no Push: Git's
  Push publishes it.

### Runs (Track E)

- The changed Finder test and the two other tree tests, chosen on CI at the first commit: 3 executed, green
  (42142849197).
- With the status bar and the clipped sticky folders, the two Finder tests and two other tree tests: 4 executed,
  green (42145865419).
- After the second review's fixes (diff-index, the narrow bar, Fetch and Pull in the test): the two Finder tests, 2
  executed, green (42149764616).
- **For the user:** the sticky folders' clip is checked in still frames only; local UI runs stopped when Automation
  Mode began to ask for a password. Scroll fast through a deep tree with nested folders open: a row must never show
  through a sticky folder.

## Track F: file cards (items 11, 13, 15, then 12)

11. and 13. "selected text color is whitish and making the text not readable fix that, make sure it looks good in
    both dark and light mode" (`4.12.02.png`) and "simlar selection color problem is there with markdown as well".
15. "in file preview, we should have word wrap option simlar to word wrap button in git diff".
12. After the user picks from Track G: "in markdown, for the mode selection, i think we should basically simplify to
    two options, one for wyswig and one for source, so in source / preview, we can collapse the preview anyway now, so
    no need source only, in wyswig mode, we should have some kind read lock or something to disable edits and when
    unlocked inline edits works, give me some options on how we can simplify the options to just two, with like sub
    options etc, having 4 options is just confusing, also the icon dropdown should be greyed out like the file
    explorer button".

### Findings (Track F)

- **Cause (11, 13):** the editor's selection rule was less specific than CodeMirror's base rule for a focused
  editor (`&light.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground`, a pale lilac). The editor
  never says it is dark, so the light rule drew in dark too, under light text. File and Markdown share the editor.
- **Fix:** the same selector, so the accent at 35 % wins in both looks and in every Markdown mode; Side by Side's
  page (no drawn selection) gets the same rule for WebKit's own.
- **Decisions (15):** Word Wrap is a row 2 toggle in File only (Markdown's Read is prose; Source wraps as before). It
  starts on, as File always wrapped (cards are narrow), and the card keeps its choice for every file it shows. No
  setting: Git's has one, add one here when a user wants unwrapped files by default.
- **Runs:** the File test red on the old code (no Word Wrap button, 42142561012) and green with it
  (42143799483, 2 tests). CI's recordings draw no web content, so the pictures are local.
- **Decisions (12, the user's pick: option A):** row 2 has two icon segments (Rich Text, Source; the one not picked
  gray) and a lock that always shows (gray `lock.fill`, the accent `lock.open` while the page edits). Locked, neither
  mode edits; ticks still save. Source is the old Side by Side with the page folded at first; the divider's chevron
  shows it. ⌘E is Lock Editing. Find works locked, without Replace; a landing at a line keeps the lock. Settings:
  Markdown opens in Rich Text or Source, and Lock Markdown for reading (on). Segments got an optional symbol.
- **Migration:** a card's kept mode maps (Read → Rich Text locked, Live Edit → unlocked, Source → Source folded, Side
  by Side → Source shown). The setting keeps Source; its Read, Live Edit and Side by Side read as the default.
- **Runs (12):** Markdown and Git tests green (42147118938, 2 tests).

## Track G: mockups (items 7, 20, 12)

- HTML mockups in `~/Downloads/ovvi-research/phase56-mockups.html`, drawn from real screenshots of the current
  cards: 3–4 File Explorer status bars (in a repo with changes, ahead and behind, clean, not a repo, a remote
  machine) and 2–3 ways to make Markdown two modes with a read lock. The user picks; Tracks E and F build the pick.

Findings:

- Written: status bars A (one quiet line, recommended), B (capsules), C (folder first, then Git), D (icons only);
  Markdown A (segments and a mode button), B (one grey menu with sub-options), C (a lock button and a grey mode
  menu, recommended). Built by `~/Downloads/ovvi-research/phase56-src/build.py` on screenshots of `156a850b`.
- A plugin label's iid is exactly 6 `[a-z0-9]`: a 5-letter iid shows a plain terminal titled with the label.
- A launch with `open -n` can lose the 3 s login-shell lookup and show "herdr is not installed"; launch again.
- The window's height is the user's saved frame and changed between launches (1005 and 1084 pt): take every shot of
  one report in one hold, or measure each.
- No Side by Side shot: the GUI lock went to the user first. Source's row 2 is drawn on the Read shots.

Runs: none (no app code).

## Track H: one way to open links (item 16)

16. "in markdown, when there are links, clicking on it doesn't open by default clicking on it should open in new
    tab, and right clicking on it should have open in new tab and open to the side similar to what we show in file
    explorer, we should have open to the side option in browser as well for links, in markdown, even if its another
    markdown link, it should have option to open in new tab, open to the side, and open, basically if its markdown
    link clicking on it should open in the same pane, cmd+click opens in new tab, and option+click opens to the side,
    but if its webpage link, by default it opens in new tab, and option+tab opens to the side, and cmd+tab does the
    same as opens in new tab, in browser we should have option+click option as well, let's basically try to make
    things consistent on how we open etc, analyse all current state and updat things accordingly, same with open file
    option in diff view as well".
    - Write down today's behavior everywhere a link or a file opens (Markdown, file cards, File Explorer, Git's diff
      and file headers, the browser, the chat view), then one rule:
      - a file link: click opens in the same card, ⌘-click a new tab beside, ⌥-click to the side;
      - a web link: click and ⌘-click open a new browser tab beside, ⌥-click to the side;
      - the context menu offers Open, Open in New Tab and Open to the Side.
    - The rule goes in the design docs once, and every place follows it.

### Findings (Track H)

- **Before.** Where a link or a file opened, before this track:

  | Where | Target | Click | ⌘-click | ⌥-click | Right click |
  |---|---|---|---|---|---|
  | File Explorer's tree | a file or folder | selects (double-click: the card) | new tab, behind | side, behind | Open (as Root), New Tab, Side |
  | Markdown, Read and Side by Side's page | a relative link | the card | new tab, behind | side, behind | WebKit's menu (its New Window did nothing) |
  | Markdown, Read and Side by Side's page | a web link | new tab, behind: nothing showed when the tab was out of view | new tab, behind | side, behind | WebKit's menu |
  | Markdown, Live Edit | any link | the caret, no open | a second caret | the caret | WebKit's menu |
  | Git home: a change, Working Tree | a diff | the card | new tab, behind | side, behind | Open, New Tab, Side |
  | Git home: a commit | a diff | selects (double-click: the card) | new tab, behind | side, behind | Open, New Tab, Side |
  | Git commit page: a parent | a diff | the card | new tab, behind | side, behind | none |
  | Git diff: Open File | the file | new tab, selected | new tab, behind | side, behind | none |
  | Git diff: a line | the file at the line | nothing | new tab, behind | side, behind | none |
  | Browser page | a link | the card | new tab, behind | nothing (WebKit's download, which the app drops) | Open Link, Open Link in New Tab |
  | Chat reply | a web link | the Mac's default browser | the same | the same | the text's menu |
  | Terminal | a web link | the program | the Mac's default browser | the program | the terminal's menu |

- **Rule.** Click: in the card when it shows that kind of place, else a new tab, selected. ⌘-click: a new tab
  behind. ⌥-click: to the side, behind. Right click: Open, Open in New Tab, Open to the Side. Written once in
  `ui/window#opening-links-and-files`; the other pages link to it.
- **Fix.** `Page.open` already turned a "card" open of a place the card cannot show into a selected new tab, so
  Markdown passes the click's `how` for web links too (the cause of "doesn't open": a click opened a tab behind, at
  the far end). Live Edit follows a link drawn as one (off the caret's lines) on a click, as Obsidian does; on the
  caret's line it edits. Markdown links, Git's Open File and Parent get the app's menu. The browser takes ⌥-click and
  adds Open Link to the Side (through `newPane`'s split, as plugin opens do). Chat links open a browser pane.
- **Decisions.** A click that opens a new tab selects it; ⌘-click stays behind, as in Safari. Markdown's link menu
  keeps WebKit's Copy Link. The terminal stays as it is (⌘-click, default browser): the program owns every other
  click, and ⌥-click moves the shell's cursor. A chat link has no menu: SwiftUI's text has no link menu. A
  diff line is not a link: ⌘- and ⌥-click only.

## Track I: Git's diff (items 17, 18)

17. "we should have similar cmd+f filter in diff view as well".
18. "we should also have keybinding ] and [ to jump files in diff view basically pressing ] should jump to next file
    and pressing [ should jump to previous file, it will be actually better if it can jump based on hunks instead of
    files, but check how feasible it is to do the hunk jumps correctly, if not fallback to file jump".

### Findings (Track I)

- **Decisions: ] and [ step through changes, not files.** Next and Previous Change already stepped through each run of
  changed lines, correctly, into files not drawn yet (pierre's `getLinePosition` estimates lines it has not drawn) and
  folded ones. ] and [ are their keys. git's own `@@` hunks were not taken as the unit: one hunk holds every change
  within six lines of the next, so it can hold several changes and be taller than the view, and a jump would skip
  them. A run of changed lines is what editors call a hunk (VS Code's Next Change, vim-gitgutter's `]c`).
- **Cause (a step ignored the user's scroll):** a step went from the last change stepped to, so after a scroll back to
  the top ] jumped past everything in view. **Fix:** once a scroll (a wheel or a press on the scroll bar) takes the
  change last stepped to out of view, or the filter changes, a step goes from the top of the view: ] to the first
  change at or below it, [ to the last above. ⌘G and ⇧⌘G, which come with ⌘F, step too.
- **Decisions: the filter.** ⌘F opens a find bar like the tree's (field, count, close) that filters the files by
  path, case blind, in the scroll and the file list; steps skip the hidden files. It floats under the sticky header,
  not over it, so Viewed and Open File stay in reach. Return gives the keyboard back to the diff and keeps the filter.
  ⌘F is enabled in a diff only (`Plugin.handles`): the Git home has nothing to filter.
- **Decisions:** the bar's CSS is Git's own (13 lines in `diff.css`), not File Explorer's `find.css`: plugins are
  separate packages, and a shared one belongs in `card.css` under an `ovvi-` name, which renames the tree's.
- **For the user:** the bar floats over the top lines of the diff, as the editor's and the tree's do, so a short
  file's first line can sit under it.

### Runs (Track I)

- CI 42142284507 (a temporary tag): the steps passed; the ⌘F check failed, because `name=search` made the field a
  search field in accessibility. CI 42150477008 on 545615a6: the new test, the Git card test and the Git home test,
  3 passed. XCUITest's screenshots on CI draw no web content, so the pictures come from the app launched by hand.

## Track J: new tabs beside (item 21)

21. "let's say i have so many tabs where not all tabs are in view, and when we open a new tab now that opens at the
    end, actually can we revert this to previous behavior, pressing cmd+click or open in new tab from any tab should
    open the tab beside the current tab, instead of moving it at the end. only thing is we should make sure there is
    no flicker in the tab movement, previously we reverted that coz by default tab goes to the end and it flickers and
    then shows in correct position, we should show it directly in its correct position withou flicker".
    - The new tab shows in its final place in its first frame (an optimistic tab placed beside, as instant tabs do),
      and the strip scrolls to it.

### Findings (Track J)

- **Cause:** herdr makes a tab last and has no insert index on create. Phase 52 had made the tab, then moved it
  (`tab.move`): a snapshot between showed it at the end, then it jumped. Phase 52 dropped the move, so every new tab
  stayed at the end.
- **Fix:** the move is back, and `Ahead.beside` places the tab before herdr has moved it. Before the create, the app
  notes the workspace's tabs. The first other tab of that workspace in a snapshot (or herdr's answer, if it comes
  first) shows right after the card's tab. It stays there until herdr's order matches. At the latest, herdr's order
  shows from the third snapshot after the move's answer, so a move that herdr put somewhere else never pins the tab.
  No stand-in: a stand-in's "New Tab" label and empty card would change under the user. The tab shows as soon as
  herdr has it, already in place.
- **Decisions:** ⌘-click, Open in New Tab, Git's Open File, a link's new tab (⌘-click, `target=_blank`, Open Link in
  New Tab) and `ovvi open --tab` open right after the card's tab. ⌘T, `+` and a pane dropped on `+` stay at the end,
  as in Safari: the user named the first group, and `+` sits at the end of the bar. Several quick opens from one tab
  stack newest first, right after it, as herdr's moves put them. The strip scrolls only to a selected new tab. A
  background tab sits next to the selected one, so it is nearly always in view already.
- **Known race** (`ponytail:` in `Beside.swift`): a ⌘T pressed while a linked open's write runs can take the linked
  tab for its stand-in. It is rare, and it existed before.
- **Runs:** chosen-tests CI run 42149608850 on ca11acd9 executed 7 tests, all green: Files, Git, the browser's links,
  Markdown's links, `ovvi open --tab`, and each open showing its own page. The agent-start test skipped, as it does
  without `claude`.
- **For the user:** ⌘-click three or four files fast in a File Explorer tree, in a tab in the middle of many tabs,
  on This Mac and on devvm. Each new tab must show right after the tree's tab, with no jump from the end.
  XCUITest checks the place, not a one-snapshot jump.

## Track K: notifications check (item 22)

22. "it also looks like we already implemented notifications as well right? check the research report we had earlier
    and then see if its fully implemetned or anything left, ignore the apple signing stuff etc for now though".
    - A report only: each part of `~/Downloads/ovvi-research/notifications-plan.html` against the code, built, part
      built or not built, with what is left and its cost.

### Findings (Track K)

- The plan is not built. Main has what the plan calls "today" (phases 15 and 50): generic needs-you and finished
  banners, `ovvi notify` (one per pane every 10 s), three switches (now in Settings ▸ Agents, phase 55), the Dock
  badge and menu. No commit since the plan touched the notification code beyond the rename.
- Of 57 parts: 16 built, 10 part built, 28 not built, 5 blocked (herdr-core status, Sparkle), 3 left out (signing).
- All 8 plan phases remain, 43 agent hours: about 35 can start now (phase 3's Settings window and phase 5's chat
  channels exist), 8 wait for herdr-core (phase 4) and Sparkle (the update kind). Optional 10 h unchanged.
- Report: `~/Downloads/ovvi-research/notifications-status.html`.

### Runs (Track K)

- None: a report, no code.

## Track L: the Agents view's Done, Idle and order (item 23)

23. "oh and finally one more thing on the agent sidebar thing, couple of things: this done and idle separation is bit
    weird i feel, what's the actual purpose or difference between done and idle? like why does herdr maintain those
    both, and how we can handle those better, coz now i know done moves to idle after we view it and then unfocus it,
    but it still the experience is weird, how does t3code does it? give me few options on how we can do it, give me a
    html report, and i also feel within a group we should sort the agents based on recently updated first, now they
    jump to different positions, check all of this, and give me good ux experience for agents view overall".
    - A report only: why herdr has both, how T3 Code and others do it, 3–4 options for the states and the order with
      mockups from real screenshots, and a recommendation.

### Findings (Track L)

- herdr's `done` is `idle` plus "not seen" (`pane_agent_status`, `src/app/api_helpers.rs`): an unread flag, not a
  state. herdr's own Priority sort puts the newest `state_change_seq` first inside each status.
- Rows jump because a change of state moves a row to another group, where it lands in workspace order, with no motion;
  and a click on one agent moves the one you leave from Done to Idle in the same frame.
- T3 Code has no Done group: a green Done mark on an unread thread, cleared by the visit; rows move 2 s late and slide.
  No app read (Superset, Vibe Kanban, cmux, Conductor, Codex, Claude Code, Cursor) has Done beside Idle.
- Recommended: Done folds into Idle as the check box on the row (it goes when you leave; the row stays); newest
  `state_change_seq` first in each group; no move while the pointer is over the list, then a 0.2 s slide; 1 s settle.
  About 6 agent hours, no herdr change.
- Report: `~/Downloads/ovvi-research/agents-view-ux.html`.

### Runs (Track L)

- None: a report, no code.

## Track M: Fetch, Pull and Push in a workspace's menu (item 24)

24. "also one more thing in the workspace sidebar as well we show the git status right, can we have an option where
    when we right click we see fetch, pull, push options there, only for theworkspaces with git repos identified, and
    have a separator for these options".
    - A row with a git line gets Fetch, Pull and Push between separators in its context menu, run on the session's
      machine in the folder of the git line, with a notice while git runs, git's message on failure, and the git line
      read again after.

### Findings (Track M)

- **Decisions:** the Git card's commands, shared (`Git.Sync`): `fetch --all`, `pull`, and `push` with
  `push.autoSetupRemote`, through `Git.run` (no password prompt, git's stderr is the error). The section sits before
  Close Workspace; the workspace menu shows only in the sidebar, so nothing else changed.
- **Decisions:** Pull and Push stay enabled at zero behind or ahead: the counts are from the last fetch (Pull fetches
  first), and a branch with no upstream shows zero ahead yet Push publishes it.
- **Decisions:** while git runs, an information notice ("Pulling ‹workspace›…"); on success it goes, and the git line
  shows the result; on failure git's words in the error notice. The items are disabled with the rest of the menu while
  the session is stopped.
- **Fix (review):** git puts its `hint:` lines before its error, and the notice shows two lines: it drops the hints and
  shows the last two lines. The 10 s refresh skips the workspace while a sync runs.
- **For the user:** right-click a repository's row: Fetch, Pull, Push; a row outside a repository has none.

### Runs (Track M)

- Chosen-tests runs of `testWorkspaceRowsShowGitWorktreesAndSync`: green at 581b7e6a (dark, 43 s), and green after the
  review's fixes with a throwaway light relaunch (27 s). Each step fails without the feature: no Fetch item, no
  behind 2 without a fetch, no notice without Push, no 0/0 without Pull.

### Findings (Track D)

- **Cause.** The browser code was not the cause. Every Ovvi used the same ControlMaster socket for a target
  (`~/Library/Caches/ovvi/<h8>`). Two UI tests relaunch with `-defaultSession` and no `-session` or `-machines`,
  so their app read the user's machines and connected to devvm-aai. Its start removed the user's app's socket, and
  its quit ended the master on that path. The user's app still had its master's pid and its connected relay, so
  terminals worked. But every later `ssh -O` failed, so the browser proxy's `-O forward -D` never came, and no page
  loaded through the machine. This Mac's network needs no ssh, so it worked. Seen on the user's Mac twice: a
  master alive with its socket gone, after a test app (pid 73907) connected to devvm at 13:33:53. The tests and the
  forward are older than the network switch: the switch only made the user try remote pages while local UI runs
  were frequent.
- **Fix.** The socket's name carries the app's pid (`<h8>-<pid>`), so no other app removes or ends this app's
  masters. The two relaunches and the helper's `open-url` pass `-machines []`. A lint rule (`isolated_launches`)
  rejects a test launch without `-session` or `-machines`; it fails on the old tests.
- **Decisions.** No self-recovery when the socket goes: with a socket per app, only this app removes it.
- **Runs.** Green: 42141419673 (5 chosen tests: the remote browser test, two remote connection tests, both
  relaunch tests).
- **For the user.** Install a build with this fix (`make app`): the running app is an old build, and any test
  run until then can break it again. Then, in a devvm-aai browser card through the machine, open a page and a
  `localhost` port. Both load.

## Track O: Settings ▸ Privacy and the sidebar icons

The user's words: "so couple of things i notced with settings window:
- the privacy section, if i clear all enabled links and switch to anotehr section, i see privacy section gets removed
  completely from the sidebar, that should be shown all the time, even if nothing is approved or anything, we should
  also have an option there to add items to allowlist or remove them
- and the icons thing man, i am still not fully satisfied, so i think grey is fine, but the actual icon white is less
  or the icon is too small or something, i feel the icon is not clearly visible at all, may be use brighter white or
  slightly increase the inner icon size a bit and show me, also show me an option with colorful icons following color
  standards similar to macos settings, give me snapshots of different options, so i can finalise one"

- Privacy always shows; each machine's section has an empty state, a field and Add (an address becomes its origin,
  as a page that is opened is approved), Remove per site and Clear All. Tested by
  `testSettingsPrivacyAddsAndRemovesAWebsite`.
- Icons: options first, in one picture, nothing applied until the user picks. The user picked c: the grey tile as
  today, a pure white symbol at 14 pt semibold.

### Findings (Track O)

- **Cause.** The sidebar listed Privacy only while a machine had an approved website (or while it was the page in
  view), so Clear All and a page switch took it away. **Fix:** every page always shows; the filter and
  `PrivacyPage.hasItems` are gone, and the browser's page always links to Privacy.
- **Decisions.** A typed site with no scheme is `https` (`http` for a loopback name): the address bar's own default
  (`http`) would approve an origin that an `https` page never matches. The field adds the origin, not the path, the
  newest 200 as the browser keeps them, in lowercase (`Browser.origin`), as WebKit gives a page's address. An emptied
  list leaves no key. The test uses a machine id of its own run: the approvals are the user's defaults.

### Runs (Track O)

- Chosen-tests runs of `testSettingsPagesSearchAndLook` and `testSettingsPrivacyAddsAndRemovesAWebsite`: 42147502248
  on a014ba2d and 42149135235 on a7254f12 (after the review's fixes), both "Executed 2 tests, with 0 failures". The
  sidebar from the second run's pictures: `/tmp/ovvi-shots/settings-polish/icons/ci-{dark,light}-sidebar.png`.
  `make test`'s HerdrKit timing tests failed locally at a load of 370 (untouched here; CI's checks run them).
- **Icons.** Five options rendered with ImageRenderer from a copy of `SettingsIcon` and the row layout (no window):
  `/tmp/ovvi-shots/settings-polish/icons/options-2.png`. System Settings' glyphs fill 70–80 % of its 20 pt tiles
  (measured); the 11 pt glyph filled about 55 %. **Fix:** 14 pt semibold in pure white, about 70 %, in the sidebar and
  the search results.

## Track P: the active border on a card alone

The user's words: "one more thing, i remember we added a border to the active pane and said that we won't add any
border if only one pane is there, let's change that, even if one pane is there let's show the active border on it".

- The keyboard card always has phase 53's 1 pt border: also with one card in the tab, and on a zoomed card.
- A floating window's card has it too; the overview has none.

Then: "let's also increase default sidebar width a bit, right now sidebar is bit too narrow especially when agents view
is enabeld. don't increase it too much" and "let's make it 300".

- A new window's sidebar is 300 pt (was 240); a window keeps the width it has (scene storage), the range stays
  227–480 pt.

### Findings (Track P)

- **Fix.** The border's condition is the lit card alone: the count of shown cards and the zoom are gone from it. The
  floating window's card draws the same border. Its view moved to `PaneCardParts.swift`, as two files use it.
- **Decisions.** A zoomed card fills the tab as a tab's only card does, so it has the border too. A floating window
  holds one pane, always its window's active pane: its border shows always, as the main window's lit card shows
  whether or not its window is key. The overview's tiles are tabs, not panes, and its selected tile already has the
  keyboard surface: no border there.
- **Sidebar.** Only the default changed. A window the user already resized, or one restored after a relaunch, keeps
  its own width: only a new window opens at 300 pt. At 300 the window still fits CI's 1024 pt screen (480 already did).

### Runs (Track P)

- Chosen-tests run 42154034629 on 13496cee: `testCloseRightAfterQuickSplitsAndTheActiveBorder` (now checks the border
  on one card and after a zoom) and `testFloatingWindowInEachLook` (the float's border and the main window's lone
  card), "Executed 2 tests, with 0 failures".
- Chosen-tests run 42159161407 on 173bd7a5 (the sidebar at 300 pt): the handle's bounds, the Agents view, a swipe into
  many tabs and the drops on the sidebar, "Executed 4 tests, with 0 failures".
- Pictures in `/tmp/ovvi-shots/p56p/`: `one-{dark,light}.png`, `two-{dark,light}.png` (glass, this Mac) and
  `sidebar-300-agents-dark.png` (CI's 1024 pt screen).
