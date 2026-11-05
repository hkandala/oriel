# Cards

`ovvi open` makes a browser card or a plugin card in a new herdr pane. A terminal is a plain herdr pane (the
herdr skill). An agent is in [agents.md](agents.md).

## Open

```sh
ovvi plugins                              # the kinds you can open (plugins.md)
ovvi open <kind> [<arg>] [<place>]
ovvi open <path-or-url> [<place>]         # the default card for that file or URL
```

```sh
ovvi open browser http://localhost:3000
ovvi open explorer .                      # a folder's file tree
ovvi open ./src/main.ts                   # a file in File Explorer: text, Markdown, an image, a PDF
ovvi open git .                           # the repository's home: changes, commit, push, history
ovvi open git . uncommitted               # the uncommitted diff
ovvi open git . 4f2a91c                   # one commit
ovvi open csv-table ./data.csv            # an installed plugin
```

- A relative path is relative to your working folder. A path must exist (`bad_argument`).
- If a path has the same name as a kind, write it as `./name`.
- If the same kind and argument already show in a card of the session, that card is the answer
  (`"reused": true`) and nothing new opens. Add `--new` for a second card.
- The answer names the new pane. Keep it to change or close the card later:
  `{"pane":"w1:p7","kind":"git","arg":"/repo/ uncommitted","label":"ovvi:git#k3x9q2 /repo/ uncommitted","reused":false,"shown":true}`. `shown` is true
  when the user sees the card now.
- To close a card, close its pane with herdr (the herdr skill).

## Where it goes

| `<place>` | Where |
|---|---|
| (none) | a split to the right of your pane |
| `--down` | a split below your pane |
| `--beside <pane>` | a split of that pane (add `--down` for below) |
| `--tab` | a new tab at the end of your workspace. Ovvi does not show it, but offers a notice with Show |
| `--float` | a new tab, in its own window |
| `--replace <pane>` | that browser or plugin card shows the new kind and argument |

With `--replace`, a browser card adds a history entry, so Back returns. A terminal or an agent pane is
`bad_argument`, a card with unsaved edits is `dirty`, and `--new` is `usage`.

## Browser addresses

- `localhost` is your pane's machine, also on a remote machine.
- A `file://` address, or `ovvi open browser ./report.html`, opens only on Ovvi's Mac. On a remote
  machine, serve the file (`python3 -m http.server 8000`) and open `http://localhost:8000/report.html`.
- Ovvi opens `localhost` and local files without asking. Most other sites wait until the user clicks Open.

## Float, point, look

```sh
ovvi float w1:p3 [--on-top]               # its own window over Ovvi. --on-top: Stay on Top
ovvi unfloat w1:p3                        # back into its tab
ovvi reveal w1:p3                         # a flash when in view, else a notice with Show
ovvi card w1:p3 --json                    # kind, arg, title, dirty (unsaved edits), floating, shown, error
                                          # an agent pane adds agent, chat (true with the chat view shown),
                                          # and view ("chat" or "tui") when it has a chat view
ovvi shown --json                         # your session's panes in view, and the ones that float
ovvi balance [w1:p3]                      # evens out the splits of that pane's tab, yours by default
```

- A pane that floats already comes to the front (`"existing": true`).
- `unfloat` of a pane that does not float is `not_floating`.
