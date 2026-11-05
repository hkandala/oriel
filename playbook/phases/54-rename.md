# Phase 54: the name Ovvi everywhere

Goal: the app, the repository and every file in it use the name Ovvi. The website is
[ovvi.dev](https://ovvi.dev). Behavior does not change, and nothing breaks: the app, the `ovvi`
command, the plugin runtime and pi-hkandala still agree on every name they share.

The user's words: "[...] i am buying a domain name ovvi.dev, so let's make sure to update everywhere to use this new
name, [...] grep throug entire repo and update at all files including [...] research files etc and update the name to
ovvi. and we should rename repo as well to ovvi, make sure to udpate readme, and link ovvi.dev wherever necessary" and
"[...] review all renames, don't blindly do grep and replace it, you can do for certain places find and replace, but
we need to make sure nothing breaks it".

Decided with the user:
- The bundle id is `dev.ovvi.app`.
- Git history stays as it is.
- Screenshots stay as they are, whatever their pixels show.
- The user sets up the domain's DNS.
- The repository has no migration code and names only Ovvi. One-off steps on the user's Mac (settings, folders,
  browser data, herdr labels, the installed app, the GitHub repository's name) run once, from a script outside
  the repository.

## How

1. **A script for the mechanical part.** It writes the name into the text of every tracked file and then into
   every path, with `git mv`. The specific forms go first: the docs address `https://ovvi.dev` and the bundle id
   `dev.ovvi.app` (with its suffixes `.uitests`, `.drag`, `.herdr.<session>`, `.plugin-log` and `.savedState`).
   Then the app's word in its three cases: `Ovvi`, `ovvi` and `OVVI`. It runs `swiftformat`, and it keeps the
   columns in Markdown code blocks where they belong. It fails when a rule matches nothing or when a file or a
   path does not follow the rules after it ran. The script lives outside the repository, so the branch can be
   built from it on the latest main.
2. **Hand fixes, one commit each,** for what a replace cannot see (the table below).

## Classes

Every distinct form of the name, in the contents and the paths of every tracked file.

| Class | Examples (new form) | How | Must change in step |
|---|---|---|---|
| The name in prose, UI text and menus | Ovvi, Ovvis, "Shown in Ovvi", About Ovvi | script | UI tests that read names: updated with them |
| Swift and TypeScript names | `OvviApp`, `OvviError`, `ovviCommand`, `ovviDrag`, `ovviShows`, `minOvvi`, test names | script | `scripts/test-times.tsv` and the Makefile's `ON_DEMAND` list name the tests |
| The Xcode project | `Ovvi.xcodeproj`, scheme and target `Ovvi`, `OvviUITests`, `Ovvi/Info.plist`, the module `Ovvi` | script and `git mv` | the Makefile, CI, `scripts/e2e.sh`, the lint paths |
| Bundle id | `dev.ovvi.app`, `dev.ovvi.app.uitests`, the drag type `dev.ovvi.app.drag`, the launchd label `dev.ovvi.app.herdr.<session>`, log subsystem | script (specific rule) | Info.plist's exported type, the UI test that attaches by bundle id |
| URL schemes | `ovvi://float`, `ovvi-plugin://` | script | Info.plist, the e2e helper's URL check |
| herdr metadata | labels `ovvi:<kind>#<iid> <arg>`, tokens `ovvi-shown`, `ovvi-open`, `ovvi-req`, `ovvi-float`, `ovvi-float-id`, `ovvi-copy`, source `ovvi`, `ovvi-cli` | script | the app, the `ovvi` script, the placeholder's label parser, pi-hkandala (a patch), the docs' grammar |
| Fixed prefix lengths | `ovvi:`, `ovvi-`, `ovvi-skip `, `# ovvi-cli ` | by hand | four `dropFirst(n)` in HerdrKit and the app |
| The command | `ovvi`, `~/.cache/ovvi/bin/ovvi`, `# ovvi-cli 1.2`, error code `no_ovvi`, the mailbox `~/.cache/ovvi/rpc` | script | `cli.mdx` holds the script word for word (`make test` checks it) |
| The app's folders | `~/.config/ovvi`, `~/.cache/ovvi`, `~/.local/state/ovvi`, `~/Library/Logs/Ovvi`, `~/Library/Caches/ovvi` | script | the stand-in agents, the UI tests, the docs |
| Hashes over the name | Codex's trust hash of the chat hook command | by hand | `CodexRolloutTests` (same formula, new command) |
| Environment variables | `OVVI_SESSION`, `OVVI_OC_STATE`, `OVVI_STAND_IN`, `TEST_RUNNER_OVVI_*` | script | CI, the stand-ins, the UI tests |
| The plugin API | `@ovvi/plugin-api`, `window.ovvi`, `window.ovvi_receive`, `window.ovvi_card`, the message handler `ovvi`, `ovvi.d.ts`, `web/ovvi`, `ovvi.js`, the manifest key `ovvi`, `@ovvi/explorer`, `@ovvi/git`, `ovvi-web` | script and `git mv` | `plugins/*/package.json` and their lockfiles (`npm ci` works offline), the Makefile's link `plugins/node_modules/@ovvi/plugin-api` |
| pi and opencode helpers | `Ovvi/Chat/pi-ovvi.ts`, `--ovvi <state>`, `~/.cache/ovvi/pi-ovvi-<sha8>.ts`, `ovvi-tui.js` | script and `git mv` | the Xcode resource exception for `Chat/pi-ovvi.ts`, the stand-ins |
| Throwaway names | sessions `ovvi-e2e-*`, `ovvi-dev-*`, `/tmp/ovvi-gui.lock`, `/tmp/ovvi-dd-*`, `/tmp/ovvi-shots`, `/tmp/ovvi-research`, the VM `ovvi-vm` | script | `scripts/herdr-session.sh`, the playbook |
| The skill | `skills/ovvi`, `name: ovvi`, `~/.agents/skills/ovvi`, `~/.claude/skills/ovvi` | script and `git mv` | `make install`'s links |
| The docs site | `https://ovvi.dev` (metadata base, README, skill links), package `ovvi-docs`, repo `ovvi` in the site's git config | script | anchors that come from headings (`#is-my-pane-in-ovvi`, `#the-ovvi-skill`, `#two-ovvis`, `#options-for-ovvi`) and every link to them |
| The repository | `github.com/hkandala/ovvi`, `~/code/ovvi` | script | the GitHub repository's name and the checkout's folder (one-off steps) |
| Columns after a shorter name | wrapped Swift arguments, comment and box columns in Markdown code blocks | script (`swiftformat`, a realign step) | none |
| Pictures | `resources/branding/ovvi-*.png`; the icon contact sheet's title | `git mv`; the sheet rendered by hand | `resources/branding/README.md` |
| Hex in a fixed id | This Mac's website data store `6F767669-…` | by hand | the one-off steps move the store's folder |
| The test times | `scripts/test-times.tsv` stays sorted by time, then name | script | none |
| Links to the website | the README's first lines, the `ovvi` script's header | by hand | `cli.mdx` (it holds the script) |

## Checks

- One name: `git grep -ai`, `git ls-files` and `grep -rail` over the tree (without `.git`, `node_modules` and
  build output) find no form that the rules do not produce, binary files (the project file, the plists, the PNGs)
  included.
- `make lint build build-tests test`, with npm offline. `make web` builds the plugins. `cd docs && pnpm build`.
- A key check: the app, the `ovvi` script, the plugin runtime, pi-ovvi and the patched pi-hkandala agree on every
  token, path, global and flag, and every `dropFirst(n)` after a `hasPrefix` drops exactly that prefix. It fails on
  the script's commit without the hand fixes.
- CI: the full UI suite and the on-demand suite on the branch.

## Findings

- **Cause.** A replace cannot see code that counts characters: four parsers dropped a fixed number of characters
  for a prefix, and the name sets the prefix's length. A test hash covers a command that names a folder, and a
  fixed UUID spells the app's word in hex.
- **Cause.** The test names decide how ties sort into shards, and two test bugs showed. Python's `http.server`
  looks up the host's name at bind, and macOS then asks for the local network: the prompt stayed over the window and
  failed the shard's later hovers and clicks. The scroll test left its pane scrolled up, and a later test read that
  view instead of its command's output.
- **Fix.** The test servers bind with `socketserver.ThreadingTCPServer` (as `e2e-helper.py` does), and the scroll
  test scrolls back down.
- **Decisions.** Every phase file uses the name Ovvi. Herdr's presence tokens live 30 s, so the one-off steps
  change only labels.
- **Runs.** On 1247fd2e (main d5dc44f2 plus this phase; only playbook text came after): the full run
  42038178366 and the on-demand run 42038185879, green on the first try. The name check finds nothing else;
  `make lint build build-tests test` (npm offline), the plugins and `pnpm build` pass; the key check passes, and
  fails on the script's commit alone.
- **For the user.** The one-off steps install Ovvi.app in `~/Applications`, bring the settings, folders, browser
  logins and herdr labels to it, and leave it the only build of the app there. macOS asks Ovvi for Notifications
  and the local network. Chat-view agents started before the steps keep their launch paths: relaunch them with Chat.
