# Phase 45: Twelfth feedback: the chat's turns, empty state, speed and the panes skill

Goal: the fixes from the user's twelfth round, all on main. A turn reads as one block: what the agent did on top,
"Working" or "Worked" with the time at the bottom. The chat has room between messages, an empty state, Markdown in
the user's own messages and a scroll-to-bottom button. Long chats open at once, scroll smoothly and keep their place
when the pane resizes. The oriel-panes skill opens any kind of pane.

Design: [Chat view](../../docs/content/docs/ui/chat-view.mdx). The user's words are quoted; the decisions under them
are the orchestrator's.

## Track A: the chat's look (items 1–6)
1. **One Working.** "i still see two working, let;s show working and timer at the bottom, and at the top show only
   ran commands, read files etc" (screenshot: `Working 29s · Ran 3 commands >` and, under it, `••• Working`).
   The summary row on top drops the state and the time; the bottom of the turn shows `••• Working 29s`.
2. **Room between messages.** "there is very less gap between assistatn and user messages, can we space it up a
   bit". More space between a reply and the next user message (and the other way round) than between rows inside
   one turn.
3. **An empty chat.** "on a new chat it looks empty, can we have agent logo in like grey color or something and like
   medum to large size centered". The agent's program icon, gray, about 64 pt, centered, while the chat has no
   messages.
4. **Long turns.** "when its a long turn with too many things going on, it looks pretty cluttered yk, can we improve
   the view here better on how we show summary of tool calls, let's show worked and time at the bottom of agent
   message similar to working and show tool calls to the top" (screenshot: `✓ Worked 7h 17m · Talked to 69 agents,
   ran 89 commands, read 13 files, stopped 26 agents, …` wrapping to two lines). The summary on top is one line
   (the largest counts first, the rest as `+N more`); `Worked 7h 17m` sits under the turn's last reply, quiet, like
   Working. A failure count stays visible in the summary.
5. **One summary look.** "make the tool call summary look similar in reply mode and steps mode? like steps mode has
   bit more spacing and arrow, in reply mode spacing should be there but no arrow". Same padding in Replies and
   Activity; only Activity shows the disclosure arrow.
6. **Markdown in the user's messages.** "can we enable markdown rendering for input text as well". The user's bubble
   renders Markdown with the same renderer as replies.

## Track B: the chat's speed (items 7–10)
7. **Scroll to bottom.** "let's have scroll to down button when scrolled up". A round glass button with a down arrow
   above the reply box, shown only when the newest message is out of view.
8. **Long chats.** "let's enabled virtualisation of long chats, i see its pretty jagged and lagging when long
   sessions are opened, especially with too many tool calls and stuff". Measure first (a long recorded session),
   find what costs the time, fix it there: rows built and rendered only near the view, parsed Markdown kept per
   message, no work per scroll frame.
9. **Long chats load blank.** "when chat view is loaded for long chat, it stays blank, i have to swithc between tui
   and chat to see the conversation, make the chat view more reliable when loading". Find the cause; a long session
   shows its messages when the load ends, without a switch.
10. **Splits beside a chat.** "when chat view pane is split, its lagging similar to browser pane earlier, and also it
    scrolls to different position after things are adjusted". Splits animate smoothly; after a resize the chat shows
    the same messages it showed before (at the bottom if it was at the bottom).

## Track C: the panes skill (item 11)
11. **Any pane.** "make oriel panes skill generic and any pane should be opened by agent not just browser panes".
    The `oriel-panes` skill in pi-hkandala tells an agent how to open every kind Oriel shows: a terminal, an agent,
    a browser page, and the plugin cards where the build has them.

## Findings

### Track A

- **Fix:** a turn is counts on top (`Ran 3 commands, read 4 files`), its last reply and notes, then `Worked 7h 17m`
  under them; while it runs, the chat's loader says `Working 29s`. The top line has no state and no time, so there is
  one Working. Replies and Activity draw the line at the same place and height; only Activity has the chevron.
- **Fix:** the summary is one line: the three largest counts, `+N more`, then the failures; it cuts in the middle when
  the card is narrow, so the failures stay. Everything's runs use the same words.
- **Decisions:** `Worked` shows only under a turn with tool calls (the old line's rule), and not at Everything (no turn
  line there). `+N more` counts kinds, not calls. A user's bubble has 8 pt more above and under it (26 pt against the
  10 pt between a turn's rows). The empty chat's glyph is the header's `ProgramGlyph` at 64 pt and half opacity.
- **Cause:** the empty chat's id first sat under the scroll view's own `chat.‹pane›` id, which replaced it (the
  container-id lesson); it now sits after it.
- **Decisions:** user bubbles keep their typed line breaks (each `\n` becomes a Markdown hard break). Links in a bubble
  are its text color with no underline: rare in typed text, and an underline would change the replies too.
- **For the user:** the empty chat while a long chat loads shows the icon until the history arrives (Track B's load).
  Check a multi-line and a Markdown message in a bubble, in light mode too.

### Track B

- **Measured** on the orchestrator's own pi session (106 MB, 3,603 entries, 1,889 tool calls, 869 rows at Replies) in
  a probe app hosting the chat's rows off screen, and in HerdrKit's follower: load 6.9 s to the history; the one
  update that shows it 50–140 ms; 46 keys typed 600–670 ms of main-thread time (13–20 ms a key); a split's 16 frames
  21–108 ms each at the 95th percentile; scrolling 240 × 30 pt 1.3–2.3 s busy, 10–20 frames over 16 ms.
- **Cause, item 9.** macOS's `tail -c +N` copies about 17 MB a second and its awk passes 30 MB: the follower took 6.9 s
  to send a 106 MB backlog, the chat empty meanwhile; a switch cut the read short and showed what it had. And a
  one-step width change (Reduce Motion, a first layout) with the bottom anchor left the offset past the content: a
  blank chat until a switch made the view again. **Fix:** the whole lines go out through `head` after a `dd` seek,
  only the rest through `tail -F`, with no awk when nothing is skipped: 0.75 s. The anchoring below fixes the blank.
- **Cause, item 10.** `defaultScrollAnchor(.bottom, for: .sizeChanges)` held the bottom whatever was in view, so a
  resize while scrolled up jumped to the end; and the card's width changed at every frame of a split, so every visible
  row wrapped again. **Fix:** `scrollPosition(id:)` keeps the row at the top while scrolled up (the bottom anchor
  only at the bottom); a card under 824 pt takes its new width once it holds for 150 ms, as `SettlingHost` does
  (wider cards keep their 760 pt column and follow at once). A split's frames: 2–11 ms at the 95th percentile.
- **Cause, item 8.** The rows were built from the whole history in `ChatView`'s body, which ran again for every key in
  the reply box and every resize frame (5–8 ms in Release at 3,600 entries, plus the list's diff). **Fix:** the rows,
  the message list and the reply box are their own views: 46 keys 87 ms (2 ms a key).
- **Cause, scrolling (item 8).** The main thread's scroll time is building rows as they come into view: SwiftUI's text
  layout, the lazy stack measuring them, and one AppKit text field per paragraph for text selection (about 40 %: busy
  1.7 s against 1.0 s with selection off, on a quiet machine). Markdown parsing did not show in the samples. At
  p95 a scroll frame takes 5–15 ms (240 × 30 pt, 869 rows); 2–4 % of frames take more than 16 ms, up to 60–130 ms, when
  a long reply comes into view whole. **Tried, dropped (no gain beyond the noise of a loaded machine):** a lazy row per
  reply block, a reply's paragraphs and headings in one `Text`, `List` (no bottom anchor, slower resizes), selection
  only on hover (it rebuilds a message per hover). Kept: the link detector runs only on text with `http` or `www.`.
- **Decisions.** Scroll to Bottom shows when the bottom is more than 40 pt out of view above the reply box, jumps
  without animation, and sits 10 pt above the reply box. The place is a row's: scrolled up inside the
  newest reply, the bottom holds until a row crosses the top; in the middle of a reply taller than the view, a resize
  can bring that reply's top to the top. `ScrollPosition` with a view id did not keep the row across a resize in the
  probe; `scrollPosition(id:)` did.
- **Cause, review.** The backlog's `head` outlived the follow's kill: over the relay the rest of a dropped 100 MB backlog
  still crossed the SSH session, and through awk an orphaned `head` hung on the FIFO. It now runs in the background,
  killed from a TERM trap (a unit test, red before).
- **Runs.** The long-chat test (scroll up, split, the same messages at the top, Scroll to Bottom, widen at the bottom,
  relaunch and show the backlog) is green on CI; without the feature it has no button, and the probe saw the old
  code jump to the end on a split. The other 13 chat tests, the remote ones too, are green.
- **For the user.** Open the chat of a long pi or Claude Code session: it shows at once. Scroll up, split beside it
  (⌘D) and close the split: the same message stays at the top, and the split moves as smoothly as beside a terminal.
  Scroll to Bottom shows while scrolled up. Trackpad scrolling through a long chat can still drop a frame as a long
  reply comes into view.

### Final review fixes

- **Fix:** only the messages wait for the settled width; the reply box, Scroll to Bottom and the empty glyph follow
  the card at once, so a split no longer clips the Send button.
- **Runs:** a HerdrKit test follows an 80 MB file to `loaded` under 2.5 s: 0.9 s at a load of 15, 5.3 s (red) on the
  old `tail -c +N` script. The bound is wall-clock, so a much busier Mac can still trip it.
- **Fix:** the follow script sets its TERM trap before it starts `head`, so no TERM can come before the trap.
- **Fix:** the chat no longer cancels the width wait on disappear: the state goes with the view.
- **Fix:** a user's bubble no longer repeats `Markdown`'s accessibility element and trait, only its raw-text value.
- **Decisions:** a bubble's fenced code keeps the two spaces per line that its hard breaks add, and Copy keeps them
  too: rare in typed text.
- **Fix:** the chat-view page says both the `head` backlog and `tail` go through awk.
- **Runs:** the five chat tests are green on CI. One earlier run failed the long-chat test at its first wait: the stand-in
  had written its 150 turns by then, but the app drew them live at about 6 turns a second, and `agent.prompt` timed out
  ("Not sent"). The same tests on main and on this code in parallel were both green. Watch for it: lines that come
  live (not the backlog) can still go into the history one by one.
