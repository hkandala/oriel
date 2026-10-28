# Phase 35: Choose what a new pane runs

Goal: a new pane asks what it should be (Terminal, Agent or Browser) instead of showing the shell at once.
Return picks Terminal, so a quick terminal stays one key away. The ⌘K palette can turn the current pane into
another kind.

The user's words (2026-10-27): "Whenever we open a new pane, let's not show the terminal directly. We show
three options: terminal, agent and browser. Browser can be a placeholder for now. Terminal just fades in and
shows the already loaded zsh. Agent shows four options, all 4 supported agents. Later the user can control
what flags to provide, but for now just use the claude, codex, pi and opencode commands; we run those
commands and show the agent. We should wait for the agent to be ready and show a loader till then, then fade
in the agent TUI. Browser the same: load with a loader and fade in. This is the default view when you open a
new tab, split pane, whatever. Default selection is Terminal, so to quickly open a terminal I just press
Enter. Replace Pane should replace with a shell and not show this overlay if the user is already on a
terminal. Add ⌘K options to open a browser, an agent or a terminal in the pane. Hide the terminal and
browser ones when the pane already is one; the agent one shows all the time. Use better wording than
'in pane'."

## Track A: the chooser (items 1–5)

1. **The chooser.** Every pane Oriel creates (⌘T, ⌘D, ⇧⌘D, ⌃⌘T, New Workspace, a drop on New Workspace, an
   empty session's first workspace) shows, on its card, a small glass chooser over the waiting terminal:
   **Terminal** (selected), **Agent**, **Browser**. ←/→ or ↑/↓ move, Return or a click picks, Esc picks
   Terminal. The herdr pane and its shell start at once behind it, as today. Panes made outside Oriel (herdr's
   TUI or CLI) and panes that already run something show their terminal as today. The chooser is the app's
   state only (not herdr's); after a relaunch, a pane still at the chooser shows its terminal. Design bar (user):
   "modern Liquid Glass, center aligned, spacious with good padding and icons"; the full design is
   `docs/content/docs/ui/new-pane.mdx`. Send the orchestrator one rough screenshot first.
2. **Terminal** fades the terminal in (the usual reveal) and gives it the keyboard.
3. **Agent** shows Claude Code, Codex, pi and opencode (the program icons) on the same chooser. Picking one
   runs its command (`claude`, `codex`, `pi`, `opencode`, no flags) in the pane's shell, shows a loader on
   the card until the agent is ready (herdr's agent status for that pane, or its first full screen; spike
   which signal each agent gives, local and remote), then fades the TUI in. A command that fails or exits
   shows the terminal with its output.
4. **Browser** is a placeholder until phase 36: the option is there and says so in one short line; picking
   it shows the terminal.
5. **⌘K and menus.** Palette commands, worded without "in pane" (for example "Open Terminal Here", "Start
   Agent Here…", "Open Browser Here"; pick the clearest): Terminal and Browser are hidden when the pane
   already is that kind; Agent always shows and opens the agent list. They replace the pane's content with
   the chosen kind through Replace Pane's machinery and its confirmation rule. **Replace Pane (⌘R)** on a
   terminal gives a fresh shell with no chooser (as today); on an agent pane it shows the chooser.
   Shortcuts panel and card menu as fits.

e2e: a new tab and a split show the chooser; Return gives a terminal that takes keys; picking an agent runs
its command (CI has no agents: use a stand-in command on PATH that the test provides) and fades in after
ready; Esc gives a terminal; ⌘R on a terminal shows no chooser; the palette commands show and hide by kind.

## Findings

### Track A

- **Decisions (design change, user-approved, for the docs pass):** no glass panel and no tiles. The chooser is a
  compact list centered on the card's own fill (at most 300 pt wide, 28 pt rows, the palette's accent pill, symbol or
  program tile, the description on the right, hidden under 300 pt), with no title and no key hint; the card's header
  says "New Pane" while it shows. Agent is not a second step: it opens its four agents in place, indented under it
  (› / ⌄), and a short card scrolls the list to the selected row. Keys: ↑ ↓ move and stop at the ends, Return picks
  (on Agent it opens it, its first agent selected), → opens Agent, ← and Esc close it, Esc on a closed list picks
  Terminal; 1–3 pick the top rows, 1–4 the agents while Agent is open. The back button and `.back` id are gone; the
  Agent row's value is "expanded" or "collapsed". Mock-up: `~/Downloads/oriel-research/new-pane-final.html`.
- **Decisions:** Open Browser Here waits for phase 36 (it would do what Open Terminal Here does). Start Agent Here is
  a submenu / palette sub-page; Open Terminal Here shows only on an agent pane. Both are Replace Pane with its question
  (red button "Open Terminal", "Start ‹agent›"); on a pane at the chooser Start Agent Here is the chooser's pick.
- **Spike:** all four agents get herdr's `agent` 0.3–0.7 s after the command with status `unknown`, then a real one
  (`idle`, or `blocked` on claude's trust prompt) at 2.8–5 s. herdr reads it from the screen with its detection
  manifests (`herdr agent explain`), not the integrations, so it works on remote machines too. Ready is `agent` set and
  status not `unknown`; no frame-quiet fallback, the 10 s ceiling covers the rest. Remote not run (no user hosts).
- **Cause (keys):** the old card's terminal keeps the first responder until herdr makes the new pane, so ⌘T then a
  fast Return went to the old shell. **Fix:** an app key monitor sends the keyboard card's chooser its keys (stand-ins
  included, by `Page.keyCardID`) before any terminal; ⌘ keys and text fields are left alone.
- **Decisions:** the chooser hides its terminal by the host view's alpha (it stays first responder and streams), and
  the terminal fades in over 0.15 s as the list fades out. `tab.create` / `workspace.create` now return herdr's
  `root_pane`, so the chooser follows its pane by terminal id (a move keeps it).
- **For the user:** a real agent start (claude, codex, pi, opencode) with the loader; a fast ⌘T then Return; the
  list in light mode, Increase Contrast and a very narrow or short pane; Replace Pane on a floated agent pane.
