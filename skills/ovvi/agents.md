# Agents

Ovvi's chat view is a chat window over an agent's terminal. It needs launch flags that Ovvi makes for each
launch, so start the agent through Ovvi.

```sh
ovvi agent claude                         # beside you, its card on the chat view: claude, codex, pi or opencode
ovvi agent pi --tab                       # the places of open (cards.md), but not --replace
ovvi --timeout 20 chat w1:p4              # relaunch an idle agent with the chat view
ovvi view w1:p4 tui                       # the card's Chat | TUI switch: chat or tui
ovvi info --json                          # "agents": the agents that ovvi agent starts
```

- `agent` answers when it typed the agent's command, not when the agent is ready:
  `{"pane":"w1:p9","agent":"claude"}`. Its card opens on the chat view. To wait for the agent or talk to it,
  use herdr (the herdr skill).
- `view` flips what the card shows in every window of the session; the agent goes on. A pane whose agent has
  no chat view is `bad_argument`. `ovvi card <pane>` tells which view shows (`"view"`).
- `chat` quits the agent and starts it again in the same session. It takes about 3 seconds, and up to 10 when
  the agent is slow to quit, so pass `--timeout 20`.
- `chat` answers `self` for your own pane, `busy` for an agent that works, waits for the user or starts again,
  and `bad_argument` for a pane with no chat agent, one that shows the chat view already, or an agent session
  that herdr does not know.
- `chat` clears what the user typed into that agent. Do not run it on an agent the user works with.
- For an agent without the chat view, run its command in a herdr pane (the herdr skill).
