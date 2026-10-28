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
