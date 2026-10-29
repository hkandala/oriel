# Phase 40: Tenth feedback: two-row headers, browser polish, chat sessions and reading

Goal: browser and agent cards get a two-row header (the title and the pane buttons, then the kind's controls),
agents show their own session titles, a pane started without Oriel's flags can turn its chat on, and the chat
reads better: a growing reply box, quieter tool calls, roomier Markdown. Then one review of the whole browser
and chat code for simplicity.

Design: [Browser](../../docs/content/docs/ui/browser.mdx), [Chat view](../../docs/content/docs/ui/chat-view.mdx),
[Floating panes](../../docs/content/docs/ui/window.mdx#floating-pane). The user's words are quoted; the sketches are the
orchestrator's reading.

The header, for both kinds (a terminal card keeps its one row):

```
browser  row 1: [favicon] Page Title ······························ [state] [pane buttons: hover or active only]
         row 2: [‹] [›] [↻] [ address field ································ ] [Web Inspector]
agent    row 1: Session title ······································ [state] [pane buttons: hover or active only]
         row 2: [logo] Claude Code ~/code/oriel ················ [Show: Replies ▾] [Chat | Terminal]
                (no chat flags: [Enable Chat] where the switch is)
```

## Track A: headers, the browser, floating panes (items 1–6, 9, 11, 15)
1. **Two rows.** "let's separate browser header into two rows, first row shows favicon, page title, and top right
   with regular pane controls which hide on inactive or not hover like regular pane and next row has back and
   forward button, reload, address bar and devtools at the right". The same frame for agents: "first row shows
   the session title and right with pane controls and next row should show the agent name and path like what we
   show now with right shows the chat and terminal toggle". The row-1 title is the one track B provides (until
   it merges: the program's name).
2. **No ports chip.** "i am not sure what that ports button does? can we remove that? what value does it add in
   general?" Removed with its code (the SOCKS forward stays).
3. **Brighter back and forward.** "back and forward buttons are bit too light especially in dark mode making it
   almost invisible". The same weight as the other header buttons; dimmed only when disabled.
4. **Titles.** "tab title should show something like Browser | page title, same with floating pane title as
   well". As terminal tabs show `zsh oriel`: `Browser` then the page title dimmed.
5. **No path for plugins in a floating window.** "in the floating pane breadcrumb we still show path and zsh?
   better not to show it for any plugins in general, only for terminal or agents we show it".
6. **The address field on hover.** "when we hover address bar can we show text caret mouse icon and then
   highlight the address bar a bit to indicate we can click it to activate".
9. **The detail level in the header.** "the detail control we have in the bottom, let's move it beside chat
   terminal toggle, but making it like a dropdown instead of three button toggle and give some name to indicate
   what exactly it is". A pull-down `Show: Replies ▾` with Replies, Steps and All.
11. **Chat in a floating window.** "in floating pane i don't see option for chat view, let's have that option
   there as well".
15. Track A merges first: B and C put their parts into its rows.

## Track B: agent sessions (items 7, 8, 12)
7. **Session titles.** "let's figure out how to get auto generated agent session titles for claude code,
   opencode and codex, i don't think pi does it, but one can manually change session titles in pi, so we should
   show those session titles as the pane name and in agent sidebar as well". The card's row 1, the floating
   window's title, the Agents view's rows, and the tab as `Claude Code` then the title dimmed. A user's own herdr
   label wins. Before an agent has one: "New Session".
8. **Enable Chat.** "for the sessions where it doesn't have enough flags we don't show any chat and terminal
   toggle which is correct, but in that button place can we show something like restart session to enable chat
   view which resumes the same session with flags needded, use better naming for that button so its concise".
12. **Model and thinking effort** for track C's reply box: what each agent's files say, nil when they don't.

## Track C: chat reading and the reply box (items 10, 13, 14, 16)
10. **The reply box.** "let's make it auto expandable and let's move the circular send button inside the
   input, make it small and stays in the bottom right, bottom left should show model and thinking effort, and
   the abvoe input layer basically auto expands for like 10 lines max".
13. **A click anywhere activates.** "chat view doesn't get activated when i click anywhere on the chat view pane,
   only when i click input it activates, clicking anywhere on chat view should activate the input".
14. **Quieter tool calls.** "i feel tool calls are taking more attention coz of liquid glass, may be let's drop
   liquid glass and make it subtle so the markdown content has more attention, and in the all detail view user
   should be able to expand each indidvual tool call to see its input and output, overall improve the tool call
   parts".
16. **Readable Markdown.** "the markdown content rendering is bit tightly packed, let's have some good left and
   right padding for entire chat view and also may be increase line height or something to make it more
   readable, right now i can't see proper markdown hierarchy and not very readable, improve it overall and make
   it look better".

## Track D: simplify the browser and chat code (item 17), after A–C merge
17. "let's do review of entire browser component and chat view components code, and let's elminate unnecesary
   code comments, let's avoid unnecessary complexities and refactor if needed to make the code overall simple
   and more readable". A read-only review of `Oriel/Browser`, `Oriel/Chat` and their HerdrKit parts, then the
   refactor, no behavior change.

## Findings

### Track A

- **Cause (item 3):** the toolbar dimmed a disabled button twice: its own 0.35 opacity on top of the 0.4 that
  `ChromeStyle` gives every disabled button, so Back and Forward drew at 0.14. **Fix:** the toolbar's opacity
  went; they dim once, as Zoom does.
- **Fix (items 1, 9):** a browser's or an agent's card has two header rows: row 1 (36 pt, so it lines up with a
  terminal card's header beside it) has the title, the state capsule and the pane buttons on hover or on the
  keyboard card; row 2 (32 pt) has the toolbar, or the agent's program and folder with `Show: Steps ⌄` and
  Chat | Terminal. Row 2 ends on row 1's trailing inset. The detail level is a native `Menu` with an inline
  `Picker` in `ChromeStyle`.
- **Fix (page icon):** WKWebView has no favicon API. After each load one script in the page reads
  `<link rel~=icon>` (else `/favicon.ico`) and fetches it, at most 1 MiB in 5 s, as base64. The page's own
  fetch goes through its proxy and its loopback rule, needs no ATS exception and decodes `data:` hrefs that
  `URL(string:)` escaped twice; CORS keeps a few cross-origin icons out (the globe). The globe also shows
  over a failed load.
- **Decisions:** the state capsule sits in row 1 for any agent card (the chat's own capsule for a chat card,
  herdr's state for others). A floated card in its tab keeps one row. In a floating window the chat's
  switch and Show menu sit in the title row, right of the place, and Show shows only while the chat does. A
  floated plugin pane (any `oriel:` label) shows no place and no divider. The browser tab and the floating
  window read `Browser` and the page dimmed; a browser card's row 1 shows the page alone.
- **Decisions (item 2):** the ports chip, `Exec.listeners()` and their tests are gone; the remote browser
  test still checks the proxy's localhost and its refusal.
- **For the user:** check a real site's icon (github.com, a dev server), the I-beam and the fill on the
  address field, and Back and Forward in both appearances. An agent started by hand in a shell grows the
  second row when herdr notices it, and the terminal gets 32 pt shorter then.

