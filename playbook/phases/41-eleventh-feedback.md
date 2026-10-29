# Phase 41: Eleventh feedback: browser links, titles, the chat's reply box, rows, loading, overview, swipes

Goal: the fixes from the user's eleventh round, all on main. Browser links open in new tabs and splits animate
smoothly; titles read the same everywhere; the chat starts on the TUI, its reply box behaves like a real editor, its
rows count everything, every session loads whole, Markdown renders in full; the overview shows every card kind; the
three-finger swipe never gets stuck.

Design: [Browser](../../docs/content/docs/ui/browser.mdx), [Chat view](../../docs/content/docs/ui/chat-view.mdx),
[Window](../../docs/content/docs/ui/window.mdx). The user's words are quoted; the decisions under them are the
user's answers to the orchestrator's questions.

## Track A: browser (items 1–3)
1. **Open links in new tabs.** "right when you right click and click on option on open in new window, it opens the
   link in an overlay which you can't close, can we may be include an option like open in new tab which basically
   creates a new herdr tab starts our browser plugins and opens that link? let's also make open in new tab work with
   cmd + click on links." Replace WebKit's Open Link (and Image, Frame) in New Window items with Open Link in New Tab;
   ⌘-click and a page's `target=_blank` without an opener do the same. A popup a page opens for itself (OAuth) stays
   a sheet, and that sheet always has a close button and closes on Esc.
2. **No Download Linked File.** "there is one more option like donwload linked file, that doesn't do anything and we
   don't need it, let's remove that". Remove every download item from the page's context menu.
3. **Smooth splits beside a browser.** "when browser pane is there splitting panes within that tab has some jagged
   animation, like its not smooth for some reason, not sure if the browser pane is adding load on the tab? check and
   ivnestigate and fix that, i don't see that when i just have terminal tabs". Measure first (the frame-record
   tests), find the cause, fix it there.

## Track B: titles (items 4–6, 13)
4. **One separator in plain-text titles.** "when i press cmd+k for browser tabs we show "Browser Page Title", in
   regular tab we have low opacity for page title and makes it fine, but in cmd+k menu that distinction is not
   there, so it looks weird, ... this applies for agents as well, i see Claude Code followed by session title, with
   no separator, let's add line separator for all such tabs". Decision: ` | ` wherever a title is plain text (⌘K,
   the Window menu, the window title, any other text-only place) for every tab: `Browser | Hacker News`,
   `Claude Code | Fix login`, `zsh | oriel`. Tab capsules keep the dimmed second part.
5. **New Pane in a floating window.** "right now we see new pane and new tab in tab and pane titles which is good,
   but if i open that to a floating pane, i see zsh in the title, we should show New Pane there as well".
6. **The tab's busy dots.** "when loader is shown on tab, i see loader overlapping with text, can we handle it on how
   we handle cross button" (screenshot: `Codex Explain herdr conne` under the dots). The title fades before the
   dots, as it does before the ×.
13. **Untitled.** "when no title is assigned, let's show Untitled instead of New Session like now".

## Track C: the reply box and the chat's behavior (items 7–12, 14, 15)
7. **The TUI by default.** "i still see chat view is default, i mentioned to make terminal as default view when
   opened from agents in new tab". A chat pane opens on its TUI; the user switches to Chat.
8. **Names.** The switch is `Chat | TUI`; the button on a pane without Oriel's flags is `Relaunch with Chat` (help
   tag: "Restart ‹Agent› with chat, in the same session").
9. **Placeholder.** "let's change placeholder to Ask Anything instead of Reply to Pi or Reply to Claude Code etc".
10. **⇧Return.** "in input, shift+enter doesn't add a new line, so i can't type multi line things". ⇧Return (and
   ⌥Return) add a line; Return sends.
11. **Edges.** "input should be slightly bigger than content such that the placholder text aligns with markdown text
   on both left and right". The box's text sits on the Markdown column's edges; the box itself extends past them by
   its own padding.
12. **Esc stops.** "pressing esc should stop the running session, equivalent to pressing esc when agent is running".
   Anywhere in the chat while the agent works; nothing when it is idle.
14. **Content under the box.** "can we make the markdown content flow below the liquid glass input to have that
   effect, when you scroll i mean". The reply box is Liquid Glass over the bottom of the scrolling messages (the
   user's explicit exception to "nothing over pane content"); the last message scrolls clear of it.
15. **Top padding in a floating window.** "can we have bit of top padding when the chat view is opened in flaoting
   pane, its bit too close to border".

## Track D: the chat's rows (items 16–21)
16. **Levels.** "default visibility mode for tool calls should be replies only, also can you give me some options on
   terms for the vsibility, replies, steps, all doesn't sound good to me". Decision: `Show: Replies · Activity ·
   Everything`, Replies by default (the pull-down's labels in ChatCard.swift are this track's one edit there).
17. **The summary line per level** (screenshot: `Working · 4 commands 48s` over groups that read 9 files and ran 4
   commands, and a loader at the top and at the bottom). "top line says working 4 commands, i am guesing that should
   show count of all commands, reads, write etc, but it just shows 4 commands? we should fix that, tool group conuts
   are fine though, and also i see two loading animations, one on top and one on bottom, let's keep only bottom one,
   so let's do it like this if its just replies, we show working, followed by how many commands, reeds, write etc
   full count, if steps, then that same line can be expandable and see all steps, if its all then let's not show
   that top worked and commands,reads count etc, just show tool groups, thoughts and final markdown content". So:
   Replies: the line with the full count, not expandable. Activity: the same line, opening to every step.
   Everything: no line; tool groups, thoughts and replies. One loader, at the bottom.
18. **Wording from pi-content-layout.** "check pi content layout in pi-hkandala for the tool groups naming logic we
   use and how we structure it, let's follow whatever relevant from that extension to chat view".
   `~/code/pi-hkandala/extensions/pi-content-layout/tools.ts` (WORDING: verb, noun, plural; codemode's calls count
   as their own; "ran ‹tool› N times") and `index.ts` (how runs group).
19. **Same-size icons.** "for tools can we use better icons so they are all either rectangle or square so the icons
   don't look different in sizes".
20. **Scrolling inside an open tool call.** "when a tool call is expanded, and it has lot of content to scroll,
   regular scroll doesn't work within it, if i hold the scroll bar and scroll it then works, we should fix that".
21. **No flicker.** "when tool call detail level is steps and then the tool calls are collapsed, then when the stream
   is running, i see flicker of tool calls".

## Track E: loading and Markdown (items 22–26)
22. **Whole sessions.** "i only see last few commands and last markdown message, previous user message etc i can't
   see them in chat view, are we limiting how far we see in transcript?" and "actually happens with other agents as
   well, when i restart app and the chat view loads for same session i see only last markdown response with nothing
   shown for previous ones". Cause found: a newly opened file is read from its last 256 KiB (`Follow.swift`); a
   one-turn Claude Code session is about 800 KB (its `api-request-*` lines). Read the whole file the first time; on
   a remote machine, drop line types no parser reads before they cross the relay.
23. **Show once loaded.** "when long session is being loaded in chat view, its content should be shown after all
   content is loaded, right now on initial load, i see like one one message loading".
24. **Switching mid-stream.** "when i switch to chat view when response is streaming i usually see empty content, it
   settles after the response stream is done, usually i don't see that issue when i am already in chat view and
   stream is happening though".
25. **All of Markdown.** "table rendering doesn't work in chat view, make sure all standard markdown things do work in
   chat view". Decision: parse with Apple's `swift-markdown` (cmark-gfm): tables, task lists, strikethrough, nested
   quotes and lists, rules, footnotes, images, autolinks. "let's not hand madde things pelase, let's use already
   recognized libraries or whatever swift prvoides". Draw with SwiftUI as today.
26. Track E owns `Follow.swift`, the followers in `ChatAdapter.swift` and `Markdown.swift`; track D owns the rows.

## Track F: the overview (item 27)
27. "on overview mode, i don't see browser and chat view correctly, can we snapshot and show browser and chat view as
   well along with how we do for terminal, basically it should work generically for anything on the tab". One path
   for any card that is not a terminal: a snapshot of its view (WKWebView's `takeSnapshot` for a browser, the card's
   own view for the rest), refreshed while the overview shows.

## Track G: the three-finger swipe (item 28)
28. "this three finger swipe sometimes stop working ... i open bunch of tabs, with brwoser, chat view, navigate across
   multiple tabs and stuff, and then suddenly three finger swipe doesn't work, i have to quit the app and restart it
   to fix it". Lead: `SwipeRouter`'s static `ThreeFingers` resets only when every touch on the pad has phase
   `.began`; one lift the app misses (a menu, a web view or a sheet holding the events) keeps a stale touch and may
   stop every swipe after it. Prove the cause, fix it so the state cannot stick, and test the missed lift.

## Findings

### Track B
- **Cause (4):** every plain-text title joined its two parts with a space; only the tab capsule dims the second
  part, so ⌘K, the Window menu and window titles read `Browser Hacker News`.
- **Fix (4):** one `plainTitle` joins a title's parts with ` | ` for the tab's text title (⌘K, Window menu, Move Pane
  to Tab, the window title, close dialog, agent rows), the card's plain title and the floating window's title. The
  capsule, the hover card and the overview keep the dimmed part.
- **Cause (5):** the floating window's title row and window title took the pane's program (`zsh tmp`); only the card
  header checked the chooser. **Fix:** the floating window's title says `New Pane` while the chooser shows.
- **Cause (6):** the title made room for the × only; the dots sit in the same 28 pt slot. **Fix:** the title fades
  before them too.
- **Decisions:** accessibility labels built from the plain title carry the bar too; the capsule's label, read from
  its drawn text, does not.
- **For the user:** ⌘K on a browser, an agent and a shell tab; a long agent tab title while it works; float a new
  pane (⌘D, then Float) before you pick.

### Track C

- **Fix, items 7 and 8.** A chat pane opens on its TUI (`Chat.showsChat` is false at first). The switch reads
  `Chat | TUI`, so its identifiers are `pane.‹id›.view.chat` and `.tui`. The button reads `Relaunch with Chat`. Its
  help tag already said "Restart ‹Agent› with chat, in the same session".
- **Decisions.** Relaunch with Chat opens on the chat, because the user asked for it (`Pane.relaunched`, read once
  when the chat is made). If the relaunch fails, the flag stays set. That is harmless: only another relaunch puts a
  marked agent in that pane. The code keeps the names `EnableChat` and `enable-chat`.
- **Fix, items 9 and 10.** The placeholder is "Ask Anything". ⇧Return (and its key repeat) sends
  `insertNewlineIgnoringFieldEditor:`, the same action as ⌥Return. A vertical `TextField` sent ⇧Return to
  `onSubmit`.
- **Fix, item 11.** The box's text is 14 pt in from its sides, and the box is 18 pt in from the column, so its text
  lines up with the messages' 32 pt edges. Send stays 7 pt from the box's side.
- **Fix, item 14.** The question card and the reply box are a `safeAreaInset` on the messages' scroll view, inside
  the top fade's mask. The content scrolls under the glass, and the bottom anchor keeps the last message clear
  of the box as it grows. The scroll view's accessibility frame stops at the inset, so a test cannot read the
  overlap from that frame. The waiting drawer keeps its own row under the messages, because pane content never
  sits under a terminal.
- **Fix, item 12.** `onExitCommand` on the chat calls Stop. It acts only while the agent works. It needs the chat to
  have the keyboard: the reply box almost always has it, but after a double-click selects text it does not. While
  the drawer shows, the terminal takes Esc itself.
- **Fix, item 15.** A floating window's chat starts 28 pt from the card's top, not 16 pt, because the floating
  card has no header of its own above the messages.
- **Decisions.** A wheel over the reply box does not scroll the messages under it (CI showed it). The box is drawn
  over the scroll view, not inside it, and before this change the wheel did nothing there either. A pinned section
  footer inside the scroll view would pass the wheel on, but it needs negative padding and puts lazy-stack layout
  around the text field. Not worth that now.
- **For the user.** In a long chat, scroll up: the messages show under the glass box. Hold ⇧Return: lines, no send.
  Press Esc while the agent works.

### Track D
- **Fix (16):** `Show: Replies · Activity · Everything`, Replies by default (`ChatLevel` cases renamed, so an old
  saved `steps` or `all` reads as Replies).
- **Cause (17):** the turn's line counted only edits and commands (reads only when there was neither), and each running
  run and the line drew their own working dots beside the chat's bottom loader, which hid while the line was last.
  **Fix:** Replies: `Working 48s · Read 9 files, ran 4 commands` with every tool counted, not openable. Activity: the
  same line, opening to every step of the turn (tool calls and thinking). Everything: no line; runs, thinking and every
  reply. No dots on lines or runs; the bottom loader shows whenever the agent works.
- **Fix (18):** runs are worded as pi-content-layout words them: its verb and noun per tool for every agent's names,
  calls counted (not distinct files), in the order the tools first ran, `ran ‹tool› N times` for others, codemode's
  script calls counted as their own (pi's `details.calls`). As in its groups, thinking between tool calls is a step of
  the run (a `Thought` row inside it) instead of splitting it; thinking alone keeps its own row.
- **Fix (19):** one shape family for the step symbols: `doc.text`, `square.and.pencil`, `terminal`,
  `doc.text.magnifyingglass`, `curlybraces.square`, and `text.bubble` for thinking.
- **Cause (20):** an open call's Input and Output were one scroll view of both axes; inside the strip's sideways
  scroll view such a scroll view gets no vertical wheel (a probe window showed it). **Fix:** a vertical scroll view
  around a sideways one.
- **Cause (21):** while a closed run streamed, its header changed on every call: the running call's target came and
  went, its working dots came and went, and the verbs flipped between Running and Ran; the bottom loader hid and came
  back as the line stopped or started being the last row. **Fix:** all of those are gone; only the counts and the
  line's time change.
- **Decisions:** Activity shows the same rows as Replies (no plans, no earlier replies): only the line opens. Runs at
  Everything open by default, as All did. Claude's MCP tools now show their own name (`search_files`, it was
  `files`). Running verbs (`Running 1 command`) are gone with pi's wording. Not pi's: `web_fetch` counts calls, not pages,
  pi-herd tools count calls, not agents, and a codemode call's failed script calls do not count as failed (the parsers
  keep no per-call args or status).
- **For the user:** at Activity while a turn streams, the closed line must not flicker; the step symbols in an open
  run read as one size; a sideways swipe over an open output box whose text fits still turns the strip.

### Track E

- **Cause (22, 24).** `Exec.follow` read a new file from the first line of its last 256 KiB. A Claude Code session
  passes that in one turn (the user's 796 KB session has its first prompt at 70 KB), so a chat opened after a relaunch
  or mid-stream started inside the running turn: no earlier turns, and at Replies only "Working" until the reply came.
  Item 24 is the same cut, not a separate bug.
- **Fix (22).** A new file is read from its start. On the pane's machine, awk drops the lines the parser skips (an awk
  pattern next to each parser: Claude's records that write `type` first and its non-queued attachments, Codex's
  top-level types but `event_msg` and `turn_context`) and prints `oriel-skip <bytes>` for each, so the mark still
  counts the file's bytes. Pi's and OpenCode's files pass whole (pi's tree needs every entry).
- **Runs (22).** On the user's files: the 796 KB session passed 208 KB and showed its first prompt (the old start: 7
  entries, no prompt); 17 Claude sessions passed 3.0 of 12.5 MB and 40 Codex rollouts 3.1 of 14.7 MB, each with the
  same history as the whole file. The unit test fails on the old start.
- **Fix (23).** The script also tells where the file's whole lines end when opened; the follower says `loaded` there.
  The chat reads up to it into a copy and shows the copy at once (a cut-short read keeps what its marks read).
- **Decisions.** awk reads a FIFO only `tail` writes to (opened, then removed at once), so the wrapper's kill of `tail`
  ends awk by EOF: no orphan, no `pkill`. The filter runs on This Mac too (one path). No loading indicator: the chat is
  empty for the few milliseconds of a local read.
- **Fix (25).** swift-markdown 0.9.0 (cmark-gfm) parses; the views draw tables (head on a fill, column alignment),
  task lists, strikethrough, nested quotes and lists, rules, and web images alone in a paragraph (a path belongs to the
  pane's machine). swift-markdown has no autolink extension: bare `http(s)://` and `www.` addresses are linked with
  `NSDataDetector` (not names such as `Oriel.app`). It has no footnotes either: `[^1]` reads as written.
- **Also.** An unknown tool's target was its "first" text argument in a parsed dictionary's random order (a flaky
  history); it is now the first by key, in Claude's and pi's parsers.
- **For the user.** Open the chat of a long Claude Code or Codex session after a relaunch: every turn shows, at once;
  switch to Chat while a reply streams; ask an agent for a table and a task list.
