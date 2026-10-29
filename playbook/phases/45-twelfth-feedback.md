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
