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

## Track G: mockups (items 7, 20, 12)

- HTML mockups in `~/Downloads/ovvi-research/phase56-mockups.html`, drawn from real screenshots of the current
  cards: 3–4 File Explorer status bars (in a repo with changes, ahead and behind, clean, not a repo, a remote
  machine) and 2–3 ways to make Markdown two modes with a read lock. The user picks; Tracks E and F build the pick.

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

## Track I: Git's diff (items 17, 18)

17. "we should have similar cmd+f filter in diff view as well".
18. "we should also have keybinding ] and [ to jump files in diff view basically pressing ] should jump to next file
    and pressing [ should jump to previous file, it will be actually better if it can jump based on hunks instead of
    files, but check how feasible it is to do the hunk jumps correctly, if not fallback to file jump".

## Track J: new tabs beside (item 21)

21. "let's say i have so many tabs where not all tabs are in view, and when we open a new tab now that opens at the
    end, actually can we revert this to previous behavior, pressing cmd+click or open in new tab from any tab should
    open the tab beside the current tab, instead of moving it at the end. only thing is we should make sure there is
    no flicker in the tab movement, previously we reverted that coz by default tab goes to the end and it flickers and
    then shows in correct position, we should show it directly in its correct position withou flicker".
    - The new tab shows in its final place in its first frame (an optimistic tab placed beside, as instant tabs do),
      and the strip scrolls to it.

## Track K: notifications check (item 22)

22. "it also looks like we already implemented notifications as well right? check the research report we had earlier
    and then see if its fully implemetned or anything left, ignore the apple signing stuff etc for now though".
    - A report only: each part of `~/Downloads/ovvi-research/notifications-plan.html` against the code, built, part
      built or not built, with what is left and its cost.
