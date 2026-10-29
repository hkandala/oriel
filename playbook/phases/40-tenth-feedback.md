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

### Track C

- **Cause (14):** each run of tool calls was a Liquid Glass card with stacked edges, as loud as a reply, and the
  parsers kept only a call's first line, so there was nothing to open. **Fix:** a run is one quiet line (the
  summary, a chevron, the time); open, a row per call (symbol, name, target, result, time), each opening on its own to
  its Input (an edit's diff instead) and Output, monospaced, at most 180 pt, then it scrolls. `ChatTool` keeps
  `input` and `output` whole (capped at 20 000 characters) from all four parsers. The todo list lost its glass too.
- **Decisions (14):** the turn's quiet line ("Worked 7s · 1 command") takes the run of calls right under it, so the
  two lines never say the same twice; a run after a reply keeps its own line. Calls open at Steps too, wherever a run
  is open. Diffs show only when their call is opened.
- **Cause (16):** one 13 pt face with 8 pt between every block: headings were only semibold, list items had no
  hanging indent, inline code read larger than the text. **Fix:** 14 pt with 4 pt line spacing, headings 22/18/16 pt
  with 22 or 16 pt above them, hanging bullets (•, ◦, ▪ by depth), a list item's later paragraphs under its text,
  inline code at 0.9 of its block on a faint fill, 32 pt side padding, and the reply box on the same edges.
- **Fix (10):** the reply box grows from 1 to 10 lines, then scrolls; under the text, the model as the picker names
  it (Claude's `claude-opus-5-5` reads "Opus 5.5", others raw) and `· effort` when track B gives one, and a 22 pt
  round Send or Stop at the right.
- **Cause (13):** only the reply box took clicks. **Fix:** a simultaneous tap on the whole message list gives the
  reply box (and so the card) the keyboard, also on a reply's text and around the box; while the drawer shows, its
  terminal. Buttons and links act as well. A double or triple click, a ⇧-click or a ⌃-click leaves the keyboard where
  it is, so a selected word can be copied.
- **Decisions:** `ChatRow` and the rows logic moved out of HerdrKit's `ChatHistory.swift` (near the 400-line limit
  before track B's `effort`). A list marker wider than 12 pt (`10.`) pushes that item's first line a little right
  of its later paragraphs; left as is.
- **For the user:** a long tool output scrolls inside its 180 pt box under the wheel, then the chat scrolls; check
  the feel with a real agent. Check the model line with Claude Code, Codex and OpenCode once track B lands.

### Track B

- **Cause (titles):** each agent keeps its title in its own place. Claude Code writes `ai-title` lines into its
  transcript (`custom-title` after `/rename`, which wins); Codex keeps `thread_name` in `~/.codex/session_index.jsonl`;
  pi writes `session_info` with `/name` only (it names nothing itself); OpenCode has `session.title` in its database
  (`New session - …` until it names one). herdr's `agent_session` on each pane gives the session: an id for Claude
  Code, Codex and OpenCode, the file for pi.
- **Fix (titles):** one short `sh` run per agent pane on its machine reads the title, again when the session, the
  terminal title or the status changes (through the program asks' gate). Shown as the user's herdr label, else the
  title, else "New Session": the Agents view's rows and the tab (`Claude Code` then the title, dimmed).
- **Fix (Enable Chat):** an agent herdr knows, with a session herdr knows and no launch marker, gets Enable Chat
  where Chat · Terminal sits. It stops a turn or dialog (asking first, in an alert), clears the prompt with ⌃C, types
  the agent's quit command, waits for the shell, then types the chooser's launch line with the resume arguments
  (`--resume <id>`, `resume <id>`, `--session '<file>'`, `--session <id>`) under the chooser's loader. Claude Code's
  marker is now the hooks' folder in `--settings`, so a resumed launch is a chat pane too.
- **Fix (model, effort):** `chat.history.model` and `chat.history.effort` (String?) from the last reply: Claude Code's `effort` line
  field, Codex's `turn_context.effort`, pi's `thinkingLevel`, OpenCode's `variant`.
- **Decisions:** no session from herdr hides Enable Chat (no file scan for one). No title source for an agent herdr's
  integration does not report: "New Session". A resumed launch has no bare-command fallback (it would start a new
  session). Enable Chat makes its launch line before the agent quits, so a failed run on the machine leaves the agent
  running. While it restarts, the tab reads "New Tab", as for any chooser. Codex shows its old history only after the
  first message (its hook runs then).
- **For the docs pass:** Claude Code's marker is now the hooks' folder in `--settings` (a launch can be
  `--resume <id>`), and Enable Chat with its resume arguments belongs under "Which panes have it".
- **Spike:** herdr 0.9.5 takes `pane.report_agent_session` from the CLI for Claude Code and Codex ids, but not for a
  pi file (dropped silently), so the UI test uses Claude Code's stand-in. After a session report from `herdr:claude`,
  herdr takes no more state reports for that agent from any source, so the stand-in reports a session only when
  started by hand. A stand-in that quits must turn bracketed paste off: CI's bash 3.2 typed herdr's paste marks
  (`00~claude …`) into the relaunch line (run 40809967139).
- **For the user:** Enable Chat on a real Claude Code, Codex, pi and OpenCode started by hand (idle, and working:
  the alert), and that each comes back in the same session with its chat. That Codex's `codex -c … resume <id>`
  keeps the hook. The titles of real sessions in the tab and the Agents view, and a `/rename` (Claude Code), `/name`
  (pi).

### Track D

- **Fix:** one helper each where code was written several times: `Exec.succeeds` (a short script with input, true
  on exit 0) for five runs, `ChatAdapters.marked`/`token`/`after` for the four adapters' marker scans, the side
  folder in the adapter protocol, `Exec.follow` built on `Exec.lines`, one KVO mirror for the toolbar's six values,
  one `Page.kindTitle` for the floating window's title and title row, and the popup and its host as one value.
- **Fix:** one-use pieces went (`FlowButtons`, `OpenCodeSession.Call`, `closePopup`, `ChatView.init`,
  `Segments`' generic), formatter-wrapped lines read straight, and the chat's message list is its own part.
- **Fix:** comments that said what the code says or told history went (about 45 lines); the design links,
  `ponytail:` ceilings and the AppKit, WebKit and SwiftUI traps stayed. Guards with no visible reason kept theirs
  (the toolbar's single dim, `dropClaim`'s equal-write guard).
- **Decisions:** no behavior change: Pi's marker now needs an absolute path (its flags always give one).
- **For the orchestrator:** Claude Code's `structuredPatch` and `DiffLine.unified` count lines alike, but Claude's
  keeps `\ No newline` rows; sharing one counter drops them (a small fix, a behavior change). `ChatQuestion.raw` as
  JSON `Data` (OpenCode puts a `[String: String]` in it) could be a typed value, touching both adapters' `answer`.
  TabButton keeps a third copy of the browser title (out of scope).
