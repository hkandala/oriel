# Remote machines

Your pane can be on a remote machine that Ovvi connects to over SSH. The command, its files and herdr are
all on your machine, and the command works the same as on Ovvi's Mac.

- While Ovvi shows your pane, `ovvi status --json` says `"remote": true`. Your own `pbcopy` does not
  reach the user's Mac, so use `ovvi copy`.
- Paths are your machine's. `ovvi open ./notes.md` opens your file.
- `localhost` in a browser card is your machine. A `file:` URL, and so `ovvi open browser ./page.html`, is
  `bad_argument` (cards.md, Browser addresses).
- `plugins new`, `reload` and `install` answer `other_machine`: plugins live on the Mac. `ovvi plugins` and
  `ovvi open <plugin>` work. To read a card's error, run `ovvi card <pane> --json`.
- A pane argument always names a pane on your machine.
- If the SSH link drops (sleep, a network change), Ovvi takes no requests until it connects again (exit 3).
  Try again later, or tell the user.
