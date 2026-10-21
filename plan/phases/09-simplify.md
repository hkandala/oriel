# Phase 9: simplify the design (same features, simpler mechanisms)

Source: two ponytail design reviews (transport; panes and plugins) and two spikes. Every
feature stays. Only the way it works gets simpler. The user approved every item below.

## Design (docs + overview)

- **A. Decisions are current rules.** Rewrite every decision row as the rule that holds now,
  in one or two sentences plus a link to the page that has the mechanism. Superseded
  choices move to the row's "Rejected" column. No "Changed by"/"Dropped by" residue (a row
  that no longer holds is deleted; numbers of the others stay stable). Each mechanism is
  written on one page only; other pages link to it.
- **B. One card key:** every card is keyed by `(machine, terminal_id)`. The iid only names
  the state file. Remove the plugin-iid key, the copied-iid rule and the pane-id update step.
  After a herdr cold restart cards rebuild (as every card already does after D59).
- **C. State cleanup:** the device that closes a pane removes its state file (`rm`); on
  connect, one `find <state dir> -type f -mtime +30 -delete`. Remove the `.gc` file, the
  daily pacing, the full-snapshot wait and the label check.
- **T1. No channel budget counting:** open channels when needed. When the server refuses
  one, close the least recently shown kept stream (D46) and retry once; else the card shows
  Retry. Remove the reservations, priority levels and learned limit.
- **T2. Special keys:** document the real input path (special keys and Ctrl chords go
  through `pane.send_keys`; text through `terminal.input`). Future work: ask herdr to accept
  keys on `terminal.input` so there is one path.
- **T3. One health loop per machine:** the snapshot read is the heartbeat (it carries the
  version and catches missed events). Same cadence as today (healthy: every 30 s; while
  failing: every 2 s). Automatic retries use BatchMode and never prompt; a host that needs a
  password or OTP shows **Reconnect** instead. Replaces the separate ping, timeout-then-ping,
  wake check and back-off rules.
- **T4. Snapshot pacing:** one read in flight plus a read-again flag. Remove the debounce,
  max wait, trailing read and the own-write special case.
- **T5. Open :port chip** comes from the terminal text the app already streams (the selected
  tab's panes). No second event stream, no `pane.output_matched`; events stay
  "read the snapshot again" with no payload decoded.
- **T6. Ending a child = closing its stdin** (spike: `/tmp` report summarized here):
  `control` exits in ~2 ms and frees the pane; the bridge exits in ~100 ms; on an app crash
  the kernel closes the pipes and every child ends itself, remote ones too. Bare `observe`
  ignores EOF, so `observe` always runs inside the small wrapper
  `sh -c '<cmd> & c=$!; cat >/dev/null; kill $c'`, on This Mac too. Remove the
  `terminal.release` message, the global pid list and the atexit kill. One fallback: a
  channel SIGKILLs its own pid if it is still alive ~1 s after the close.
- **T7. Checks on connect: two steps.** herdr's usual install folders are on `PATH` inside
  the envelope (no discovery step, no `--check`; a missing herdr fails the first call and
  shows the install command); the version comes from the snapshot; no newer-protocol banner;
  `integration.list` runs when the picker opens; state paths are relative to `$HOME` (no
  `$HOME` read).
  - Later decision (user, loop 2): no install folders on `PATH`. The machine's login shell
    finds herdr once (`$SHELL -lic 'command -v herdr'`; This Mac: the same run that reads the
    environment), every call runs that absolute path, and the server's `PATH` is the login
    shell's unchanged. No path: the install command, and the next try asks again.
- **T10. Machine import:** only the Add Machine sheet lists herdr's machines; it opens with
  them checked when the app's list is empty. No first-launch import, no flag.
- **XDG fix:** the launchd job that starts This Mac's server gets the same environment the
  CLI sees (at least `PATH`, `HOME`, `XDG_*`), so server and CLI agree on paths.
- **P1. No live follow for renames either:** an open card changes only when it is built or
  on Refresh; Refresh reads the snapshot first. Delete `oriel_rev` (D23) entirely, and the
  `pane.report_metadata` call after renames. Check whether the app still needs
  `pane.updated` at all.
- **P3. Web load rule:** a page you create or type loads at once and approves its origin for
  that machine. A card built from a label (fresh start, another device, a card an agent or
  the TUI made) loads by itself if its origin is approved for that machine or on the safe
  list; otherwise it shows **Open ‹url›?** once, and Open approves the origin. Approvals are a
  per-device setting (app storage, per machine). Safe list: the machine's own `localhost` and
  `127.0.0.1` on any port (always); built in: `github.com`, `gitlab.com`, `bitbucket.org`,
  `developer.apple.com`, `developer.mozilla.org`, `docs.github.com`, `vercel.com`,
  `*.vercel.app`, `*.netlify.app`; the user can view and edit approvals and the list in
  Settings. Remove "this device created or edited the label" tracking and D58's two-part
  rule.
- **P5. No permissions field:** v1 has one capability (`run`/`dial`) that every plugin has.
  Remove the manifest field, the no-run mode, the bridge check and the
  consent-on-new-permission rule. Install consent stays.
- **P7. Open and copy through WebKit** (spike passed). Cards use WKWebView + WKUIDelegate (SwiftUI `WebPage` has no new-window hook). `target=_blank`/`window.open` from a gesture reach the app, which confirms and opens the URL; copy is native `navigator.clipboard` (WebKit requires a gesture). Remove the Swift gesture tracker, bridge `clipboard.copy` and `toast`. The app never pushes into a page with evaluateJavaScript (forced user gesture); app-to-page messages are replies to the page's bridge calls. CSP: `script-src 'self'`, inline styles allowed.
- **P9. Plugin API:** keep the snapshot-changed event, drop the `snapshot()` data (it leaks
  herdr's schema past the Multiplexer interface, D49). Plugins that need herdr data use
  `run`.
- **P10. Picker:** Terminal, Agent and Web page are fixed picker rows, not bundled "native
  manifests". Remove the native manifest variant, the reserved ids and one resolution level.
- Not adopted: P8 (plugin preferences stay as designed).

## Code (v0 app), behavior per the design above

- T3 health loop (snapshot as heartbeat; 30 s / 2 s; no prompts: This Mac has none anyway).
- T4 pacing (one read in flight + read-again flag).
- T6 stdin close (drop release message, pid list, atexit kill; per-channel SIGKILL fallback
  after ~1 s; wrap `observe` if the app uses it).
- T7 where v0 implements connect (version from the snapshot, no newer-protocol banner).
- XDG fix in the launchd plist.
- e2e tests keep passing; add or adjust tests where behavior changed (e.g. no leaked
  children after quit, recovery after a stopped session).

## How to ship

No PRs: small atomic commits straight to `main`; hooks; never `--no-verify`. Docs build and
links pass; CI green; every check on the final commit green (GitHub check-runs and commit
statuses, including Vercel). Then review loops (spec, ponytail, code, visual) until clean.
