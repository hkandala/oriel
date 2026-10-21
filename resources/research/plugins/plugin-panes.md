# Plugin panes: keep the placeholder pane, or show plugin UI only in the app?

Date: 2026-10-21. Research only. No repo changes. Tested on herdr 0.9.5 (protocol 22) in a
throwaway session `oriel-dev-pp`, which I deleted at the end.

Words used below:
- **Placeholder pane**: a real herdr pane that holds a place in herdr's layout. The app draws the
  plugin (or web page) over it. The pane carries a label such as `web:<url>` or
  `oriel:<plugin>#<iid> <arg>`, and runs a quiet process such as `cat`.
- **Label**: herdr's free-text name for a pane, tab or workspace. herdr saves labels to disk.
- **Metadata token**: a small key/value on a pane or workspace (`pane.report_metadata`). At most 80
  characters. Not saved to disk.
- **Cold restart**: the herdr server stops and starts again. Every pane process ends. herdr rebuilds
  the layout from its session file and starts a new shell in each pane.
- **TUI**: herdr's own terminal UI.
- **Zero app state**: a fresh install, or a second device, can draw everything from what herdr and
  the machine hold. The app has nothing of its own to restore.
- **Anchor**: an id that the app can store and find again later.

---

## 1. Short answer

1. **Keep placeholder panes** for every plugin or web page that has a place in a layout. It is the
   only option that keeps zero app state, keeps every device and the herdr TUI in the same layout,
   and reuses the app's existing layout code (splits, ratios, drag, float, zoom) without changes.
2. **Change how the app creates them.** herdr 0.9.5 can start a pane with a command and a label in
   one call: `layout.apply` with `{type:"pane", label, cwd, command:[argv]}`. I tested it. This
   removes the typed placeholder, the `pane.process_info` gate, the race with shell startup, the
   line in shell history, and the separate rename. The app then never types into a shell at all.
3. **The cost is small.** One idle placeholder costs about 110 KB in the herdr server and one `cat`
   process (about 1.2 MB resident, mostly shared pages). No CPU while idle.
4. **The one real weak spot is a cold restart.** The pane comes back as a plain shell with its label.
   herdr's own plugin panes have the same problem, and herdr users already ask to fix it
   (discussion #1367). The card still works, because the label is the truth. Ask herdr upstream for
   the small fix (section 7). Do not work around it.
5. **App-only plugin UI (no placeholder)** is right only for UI that has no place in a layout:
   pickers, chips, popovers, the pill card, an inspector that follows the selection. If a plugin
   ever needs a persistent slot outside the layout, store it in a file on the machine keyed by
   `tab_id` (stable and never reused, tested). Never in iCloud.
6. **The multi-multiplexer future favors placeholders too.** tmux and Rex both have "a pane that runs
   a command" and "a label or user option on a pane". Neither has a native non-terminal pane today.
7. **v1:** web pages (and JS plugins, if they stay in v1) use placeholder panes created with
   `layout.apply` + `pane.move`. The placeholder stays inert: it prints what the pane is and runs
   `cat`. No app-only plugin surfaces in v1.

---

## 2. What I tested in herdr 0.9.5

| Question | Result |
|---|---|
| Can `pane.split` or `tab.create` take a command? | **No.** Both take only `cwd`, `env`, `focus` (and `label` for `tab.create`). |
| Can any public call start a pane with a command? | **Yes, `layout.apply`.** A pane node takes `command` (argv), `label`, `cwd`, `env`. `plugin.pane.open` also runs a command, but only for an installed herdr plugin. |
| `layout.apply {workspace_id, root:{pane, label, command}}` with no `tab_id` | Creates a **new tab** with that one pane. The label is set in the same call. `focus:false` kept herdr's focused tab. The process ran (`pane.process_info` showed `cat`). |
| `layout.apply` with `tab_id` | **Replaces the whole tab.** The old tab `w1:t1` and its shell were gone, replaced by a new tab with new panes. Never use it on an existing tab. |
| `layout.apply` (new tab) then `pane.move {destination:{type:"tab", tab_id, split, target_pane_id}}` | The pane lands in the split. The temporary tab closes by itself (`closed_tab_id`). The terminal and label are kept. Same-workspace moves keep the pane id. |
| Events for that pair | `pane_created` (it already carries the label), `tab_created`, `layout_updated`, `pane_moved`, `tab_closed`. Other devices see the new pane at once, without an `oriel_rev` token. |
| Cost of an idle placeholder | herdr server RSS grew about 2.2 MB for 20 placeholder panes (about 110 KB each). Plain shell panes cost about 166 KB each in the server, plus the shell. Each `cat` is about 1.2 MB RSS. macOS allows 511 PTYs system-wide (`kern.tty.ptmx_max`). |
| `stty raw -echo; exec cat` with Ctrl-C, Ctrl-D and text sent in | Ignored. The process stayed. |
| Placeholder process killed | herdr **closes the pane** (and the tab if it was the last pane). |
| Cold restart, pane started by `layout.apply` with a command | Pane comes back as **a plain shell**, with its label. herdr saves the argv as `launch_argv` in `session.json`, but only uses it after a live handoff, not after a cold restore (`src/persist/restore.rs:690-694`). |
| Cold restart, pane label / tab label / workspace label | All kept. A 400-character workspace label and a tab label holding JSON were kept exactly. |
| Cold restart, pane and workspace metadata tokens | Both **lost**. |
| Cold restart, workspace / tab / pane ids | **Kept**, gaps too (closed `w3` stayed missing). `terminal_id` changes. |
| Are ids reused? | No. After `w4`, a new workspace was `w5`. |
| Cross-workspace pane move | Pane id changes (`w2:p1` → `w4:p3`). `tab.move` only reorders inside one workspace, so a tab never changes workspace. |
| Trick: placeholder reports itself as an "agent" with `resume_argv` | **Works:** after a cold restart, herdr typed the resume command into the new shell, with no TUI attached. **But** before the restart the pane counts as an agent: it shows in herdr's agent list and the tab's `agent_status` became `idle`. Rejected (section 6). |

---

## 3. The options

### A. Placeholder panes (current design)

A real herdr pane, a label, and an inert process. The app draws the plugin in the pane's
rectangle.

What it gives:
- **Zero app state.** A fresh install on a new device reads the snapshot, finds `web:` and `oriel:`
  labels, and draws every plugin card where it belongs. Bigger plugin state is already in a file on
  the machine (D22).
- **One layout everywhere.** herdr's split tree and ratios are the layout for terminals and plugins.
  Every device and the herdr TUI agree.
- **Everything else is free.** Splits, ratios, drag and drop, float (`oriel:float` tab), dock, zoom,
  close, tab moves: plugin cards use the same code as terminal cards.
- **Survives moves.** The label travels with the pane. The instance id in the label keys the card.
- **Simple sync.** A rename or a new pane already sends events. Only `setArg` (a rename) needs the
  `oriel_rev` token.

What it costs, with each failure mode:

| Cost or failure | How bad | With `layout.apply` creation |
|---|---|---|
| A process and a PTY per plugin pane | ~110 KB in herdr + one `cat` | same; negligible |
| Typed-command race with shell startup | needs a `process_info` check, then `send_input` | **gone**: herdr starts the argv itself |
| Line ends up in shell history; fish quoting; base64 envelope | small but ugly | **gone** |
| Two calls (split, rename) leave a short window with an unlabeled pane | another device may show it as a terminal for one snapshot | **gone**: label set at creation. The temporary tab for a split shows for one snapshot instead (section 5) |
| Cold restart returns a plain shell with the label | card still draws; TUI users see a shell in a labeled pane | same; upstream fix in section 7 |
| TUI user types into it | input is discarded (`stty raw`, `cat`) | same |
| TUI user closes it | the plugin card closes on every device | same, and correct: herdr is the truth |
| TUI user renames it | the card turns into a terminal; renaming back restores it | same |
| Process killed | herdr closes the pane, so the card goes away | same |
| Agent detection | `cat` is never detected as an agent | same |
| Close confirmation (D41) uses "only a shell runs" | a placeholder is not a shell, so the app would ask | the app should close plugin panes without asking; it knows them by label |
| Streams | the app must not open `terminal session` for plugin panes, except **Show terminal** | same |
| Resize | the PTY size does not matter; the app never streams it | same |
| iOS | nothing extra: the phone draws the card and never streams the PTY | same |
| Windows herdr servers | `sh -c` does not exist there | same; skip the placeholder text or use `cmd` later |

### B. App-only plugin UI, outside herdr's layout

The plugin is not a herdr pane. The app draws it somewhere herdr does not know about. Three ways
to store where it is:

**B1. App storage, synced with iCloud (CloudKit).**
- A fresh install on the same Apple ID gets it back after a sync. A device on another Apple ID, a
  teammate, the herdr TUI and any other herdr client get nothing.
- Anchors must point into herdr: `(machine, session, tab_id)` works (stable, never reused). A
  pane-attached plugin has no good anchor (see B2).
- Adds a sync service, conflict rules and offline cases. It breaks D1 ("herdr is the source of
  truth") and principle 1.

**B2. A file on the machine**, for example
`$HOME/.local/state/oriel/<session>/surfaces.json`.
- Zero app state stays true: every device that reaches the machine reads the same file. The design
  already does this for instance state (D22), so no new mechanism.
- Anchors I tested:
  - `workspace_id` and `tab_id`: stable across cold restarts, never reused, and a tab never changes
    workspace. **Good anchors for "a plugin attached to a tab".**
  - `pane_id`: changes on a cross-workspace move. `terminal_id`: changes on every cold restart.
    Metadata tokens: lost on restart. The pane label: already taken by the user's own label or by
    `web:`/`oriel:`. So **there is no robust anchor for "a plugin attached to a pane"** unless the
    pane label holds it, which brings back half of option A.
- The herdr TUI sees nothing. The file is not in herdr's snapshot, so the app needs its own change
  signal (a workspace token, lost on restart but fine as a signal) and must clean up entries whose
  tab is gone.
- Any process on the machine can write the file, so the same "approve before load" rule as labels
  applies.

**B3. herdr metadata without panes.**
- Tab label or workspace label: saved and unlimited in length (tested). But the TUI shows the label
  as the tab or workspace title, so JSON in it is ugly, and a user rename deletes it.
- Workspace or pane tokens: lost on cold restart (tested). Not usable as storage.
- So B3 only works as a short marker, like the existing `oriel:float` tab label.

**Where B's UI would go**, and what each choice does to layout:

| Place | Fits | Layout effect |
|---|---|---|
| Inspector side panel per tab | "the diff of the agent I am looking at" | The tab page in the app has an area herdr does not know. Terminals in the app are narrower than in the TUI. This is harmless for PTYs (the app's stream owns the size), but the app now has two layout systems. |
| Drawer or popover | transient views | no effect |
| Floating cards | like floating panes | needs app-owned frames; today floating cards keep frames in memory only |
| A fake "tab" in the strip herdr does not know | a full-page plugin | the app's tab list and herdr's tab list disagree; reorder, ⌘1…9 and the iPhone tab list all need special cases |

The real cost of B is not storage. It is a **second layout system**: if a plugin card can sit next
to a terminal, be resized, moved to another tab, floated or zoomed, the app must store and sync its
own split tree for plugin cards. Today herdr does all of that (D10, D28). A fixed slot (one
inspector per tab, no splits) avoids this, but then plugins cannot sit next to the agent the way a
web preview should.

Multi-device under B: B1 agrees only across one Apple ID; B2 agrees across every device that reaches
the machine; neither agrees with the herdr TUI or other herdr clients.

### C. Hybrids

**C1. Placeholder runs a useful TUI fallback declared by the plugin** (web: print the URL;
git-history: `tig`; diff: `git diff | less`; markdown: `glow`).
- Good for TUI users, and costs nothing for the app.
- Risks: a real program can exit (user presses `q`), and then **herdr closes the pane, so the card
  disappears on every device** (tested). It accepts input and can change things. It uses CPU while
  it redraws. The tool may not be installed.
- A middle ground keeps the pane alive: `sh -c 'tig; exec cat'`, or a loop. Still, it is extra code
  and a manifest field, for TUI users of a GUI client.
- Verdict: not in v1. The inert placeholder should still be helpful: print the title, the URL or
  argument (an OSC 8 link, so a TUI user can click a URL), and "shown by Oriel". Revisit a
  `fallback` argv in the manifest when users ask.

**C2. Create the pane with its command directly.**
- `pane.split` and `tab.create` cannot. `layout.apply` can (section 2).
- New tab: one call, `layout.apply {workspace_id, tab_label?, focus:false, root:{type:"pane",
  label, cwd, command}}`.
- Split: that call, then `pane.move {pane_id, destination:{type:"tab", tab_id, split,
  target_pane_id}, focus:false}`. For left or top, then `pane.swap`, as for drops today.
- Float: `layout.apply` with `tab_label:"oriel:float"` when there is no floating tab, else the same
  move into it.
- **Verdict: adopt.** It deletes the riskiest part of option A.

**C3. Plugins only as attachments to a terminal pane** (sidecar or inspector).
- Needs a per-pane anchor. As shown in B2, there is no robust one besides the pane label, and the
  label belongs to the user or to `web:`/`oriel:`.
- Fine as a pure view with no saved state ("show the diff of the selected agent's repo"), derived
  from the selection each time. That needs no storage at all and is a later feature, not a plugin
  pane.

### D. Upstream herdr

What exists or is asked for:
- herdr's plugin docs say "native non-terminal plugin UI is not part of plugin v1". herdr plugin
  panes are terminal panes.
- Issue #244 asked for virtual panes (a pane id with no terminal). The maintainer said it is "too
  large and too specific for herdr core", because pane identity, focus, read, send, waits and
  rollups all assume a terminal. He added: "I do expect to add a more general custom rows/surfaces
  feature soon" (May 2026). Nothing shipped yet.
- Discussions #4445 (native right sidebar surfaces for plugins, Sep 2026) and #5421 (sidebar widgets
  for plugins, Oct 2026): no answer yet.
- Discussion #1367 (Jul 2026, open): plugin panes "don't survive server restarts"; they "come back in
  place but as a plain shell". Two more plugin authors confirmed it on 0.9.3. **This is exactly our
  cold-restart problem**, and herdr's own plugin authors want it fixed.
- Issues are for bugs only; feature requests go to discussions.

So:
- A `pane.create {kind:"external"}` drawn as a static card: possible some day, but it is the same
  shape the maintainer already called too large. Do not plan on it.
- **A small, likely ask:** restore `launch_argv` panes on a cold restart. herdr already saves the
  argv in `session.json`; only the cold path ignores it. Add it to #1367 as a concrete proposal,
  for example an opt-in `restore: true` on the `layout.apply` pane node and on plugin `[[panes]]`.
  It fixes our problem and herdr's plugin authors' problem with one change.

---

## 4. Comparison

✓ yes · ~ partly · ✗ no

| | A. placeholder (typed) | **A′. placeholder via `layout.apply`** | B1. app + iCloud | B2. machine file | B3. herdr labels/tokens | C1. TUI fallback | Upstream external pane |
|---|---|---|---|---|---|---|---|
| Zero app state (fresh install, new device) | ✓ | ✓ | ~ same Apple ID only | ✓ | ~ labels yes, tokens no | ✓ | ✓ |
| Same layout in app, every device and herdr TUI | ✓ | ✓ | ✗ | ✗ (devices agree, TUI not) | ✗ | ✓ | ✓ |
| TUI user sees what the pane is | ✓ text | ✓ text | ✗ | ✗ | ~ a title | ✓✓ a working tool | ✓ |
| Reuses splits, ratios, drag, float, zoom | ✓ | ✓ | ✗ second layout system | ✗ second layout system | ✗ | ✓ | ✓ |
| Survives pane moves | ✓ label | ✓ label | tab only | tab only | tab only | ✓ | ✓ |
| Survives cold restart | ~ shell + label | ~ shell + label | ✓ | ✓ | labels ✓, tokens ✗ | ~ | ✓ |
| Process and PTY per plugin | 1, tiny | 1, tiny | 0 | 0 | 0 | 1, real program | 0 |
| Typed-command race / shell history | ✗ has it | ✓ none | n/a | n/a | n/a | depends | n/a |
| Card can vanish if the process exits | rare | rare | no | no | no | **yes** (user quits the tool) | no |
| Label/file written by any local process needs approval | yes | yes | no | yes | yes | yes | yes |
| iOS | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Maps to tmux | ✓ `split-window -d cmd` + pane `@option` | ✓ | ✓ | ✓ | ~ | ✓ | ✗ |
| Maps to Rex | ✓ blocks with labels, stable ids | ✓ | ✓ | ✓ | ~ | ✓ | ✗ (Rex: "today a block is a terminal") |
| New app code | typing path, gate, envelope | **less**: two calls | sync + layout store | layout store + file + cleanup | small | manifest field | none, but not ours |
| Ponytail | ~ | **★★★** | ✗ | ~ | ✗ | ~ later | wait |

---

## 5. Details for A′ (what changes in the design)

Create, in place of steps 2-5 in `plugins/labels.mdx` and steps 2-4 in `plugins/web-page.mdx`:

```text
layout.apply {workspace_id, focus:false,
              root:{type:"pane", cwd, label:"oriel:<plugin>#<iid> <arg>",
                    command:["sh","-c", <placeholder script>, "sh", <title>, <arg>]}}
  → new tab with the pane (or tab_label:"oriel:float" for a floating pane)
pane.move {pane_id, destination:{type:"tab", tab_id, split, target_pane_id}, focus:false}
  → only for a split; the temporary tab closes itself
```

- Pass the title and argument as argv after the script (`"$1"`, `"$2"`), so no quoting of untrusted
  text and no base64. herdr runs argv directly, so the user's login shell (fish or not) is not
  involved.
- Do both calls before reading the snapshot, so this device never shows the temporary tab. Other
  devices and a TUI may see it for one snapshot (≤ 500 ms). Accepted.
- Never pass `tab_id` to `layout.apply`: it replaces the tab and kills its panes.
- Remove: the `pane.process_info` check, `send_input` of the placeholder, the envelope for it, the
  `oriel_rev` token after creation (`pane_created` carries the label), and **Restore placeholder**
  (it was the only time the app typed into a shell).
- Keep: `oriel_rev` after `setArg` and state writes; labels as the truth; the click-to-approve rule.
- Close a plugin or web pane without the "only a shell" question; it is known by its label.
- Placeholder script: print the title, the URL or argument (OSC 8 link for URLs), the
  `oriel:<plugin>#<iid>` marker and "shown by Oriel", then `stty raw -echo; exec cat >/dev/null`.

After a cold restart the pane is a shell with its label. The card draws anyway. A TUI user sees a
shell in a labeled pane. If that bothers users before herdr fixes #1367, the app could re-create the
pane (A′ next to it, then close the old one), but that halves the neighbor's split. Do not build it
now.

---

## 6. Rejected tricks

- **`resume_argv` self-report.** The placeholder reports itself as an agent with a resume command.
  herdr then re-types it after a cold restart, even with no TUI attached (tested). But until then
  herdr counts the pane as an agent: it shows in herdr's agent list and changes the tab's
  `agent_status`. That pollutes every herdr client. It also types into a shell again.
- **`env` on `pane.split` to change the shell** (for example `ZDOTDIR` tricks so zsh runs the
  placeholder). Shell-specific and fragile. `layout.apply` does it properly.
- **A herdr plugin as the placeholder** (`plugin.pane.open`). It runs argv without typing, but needs
  a herdr plugin installed on every machine. That reverses D20 ("no setup on any machine").
- **JSON in a tab label (B3).** It persists, but the TUI shows it as the tab title and a rename
  deletes it.

---

## 7. Recommendation

1. **Keep placeholder panes as the one model** for any plugin or web content that has a place in a
   layout. The user's two reasons hold up under testing: it is the only way to keep zero app state
   for a fresh install or a second device, and the only way to keep herdr's layout and the app's
   layout the same. It also saves the app from building a second layout system.
2. **Switch creation to `layout.apply` (+ `pane.move` for splits)**. This removes the typed-command
   race, shell history lines, quoting, the `process_info` gate and the "Restore placeholder" path.
   Update D21, `plugins/labels.mdx`, `plugins/web-page.mdx`, `floating-panes.mdx` (floating create)
   and `reference/herdr-calls.mdx` (add `layout.apply`, with "never with `tab_id`").
3. **Keep the placeholder inert.** Make its text useful (title, clickable URL or argument). No TUI
   fallback programs in v1.
4. **Accept the cold-restart shell.** The label is the truth and the card works. Post a concrete
   proposal on herdr discussion #1367: "restore `launch_argv` panes on cold restart, opt-in".
5. **App-only UI only for transient or selection-driven views** (chips, popovers, pill cards, a
   later inspector that derives everything from the selection). If a persistent app-only slot is
   ever needed, store it in a machine file keyed by `tab_id`, never in iCloud.
6. **Multi-multiplexer:** "a pane with a label that runs an inert command" is the common shape of
   herdr, tmux (`split-window -d '<cmd>'`, pane user options like `@oriel`) and Rex (blocks with labels
   and stable ids). Keep it behind the existing HerdrKit seam; no adapter now.

**What v1 should do:**
- If v1 follows the positioning report and cuts the JS plugin runtime: v1 has one placeholder kind,
  the web page, created with A′. That is about two calls and one short script.
- If JS plugins stay: the same A′ path for `oriel:` panes. Nothing else changes in the plugin design.
- Either way: no app-only plugin surfaces, no iCloud, no TUI fallback, no restart workaround in v1.

---

## Sources

- Repo design: `docs/content/docs/plugins/{index,labels,state,web-page,plugin-ui,api,security}.mdx`,
  `data.mdx`, `layout.mdx`, `floating-panes.mdx`, `decisions.mdx` (D1, D10, D18-D28, D41),
  `talking-to-herdr.mdx`, `index.mdx`.
- Earlier reports: `/tmp/oriel-brainstorm/positioning.md` (cut the plugin runtime),
  [`remote-plugins.md`](remote-plugins.md) (run/dial).
- herdr 0.9.5: `herdr api schema --json` (`PaneSplitParams`, `TabCreateParams`, `LayoutNode`,
  `PluginPaneOpenParams`, `PaneReportAgentParams.resume_argv`); tests in `oriel-dev-pp` (section 2).
- herdr source (`/tmp/oriel-brainstorm/repos/herdr`, commit 143bf5fd): `src/persist/restore.rs:540,690-694`
  (launch_argv only respawned after a live handoff), `src/persist/snapshot.rs:352,390` (launch_argv
  saved); docs `plugins.mdx:31-33,300-335`, `cli-reference.mdx:515-536`, `session-state.mdx:29-35,73-115`,
  `add-herdr-support.mdx:53-95`.
- herdr GitHub: issue #244 (virtual panes, maintainer reply), #1608, #1125, #4206; discussions #1367
  (plugin pane restore), #4445 (right sidebar surfaces), #5421 (sidebar widgets), #4644.
- Rex CLI docs: https://www.superlogical.com/rex/docs/automate/cli ("A block is one application in a
  window. Today that means a terminal."; ids never change and are never reused; labels on blocks).
- tmux: `split-window -d [shell-command]`, pane user options (`set-option -p @name`, tmux 3.0+).
