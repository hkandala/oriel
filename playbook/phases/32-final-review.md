# Phase 32: Final whole-repo review and cleanup

Goal: after phase 31, review every file for bugs and edge cases, clean comments and needless code, make the
docs match the app, and end with CI green twice in a row. Big changes go to the user, not into the code.

## Build

1. **Bugs and edge cases, every file.** One reviewer-fixer per code area reads every file and fixes with
   small, safe changes, and a test where one can see it.
2. **Comments.** A comment stays only when it says what the code cannot.
3. **Ponytail.** Remove dead code, leftover flags and hooks of dropped features, needless abstractions.
4. **Docs.** The design pages match the app; stale plans and research go.
5. **No big changes without the user**: a list with the reason, the cost and a recommendation.
6. **Green at the end.** Two full CI runs in a row without reruns.

Areas, files disjoint: r-herdrkit, r-remote (SSH, relay, machines), r-store, r-terminal, r-app, r-strip,
r-chrome, r-panels, r-tests (UI tests, scripts, CI), d-spec (docs), d-plan (plan and resources). Read-only
auditors (ponytail app and kit, security and accessibility) sent findings to the owners. f-e2e ran the
full suite at the end.

## Findings

- **r-panels.** A floating window's ⌘K lit a row from the main window's tab index; a tile clicked while its
  page slid away zoomed the wrong tab; float requests passed any session name to a herdr argv (now validated).
- **r-herdrkit.** A write's refresh during the 250 ms spacing waited it out (D5 says at once); session names
  starting with `-` are refused.
- **r-remote.** A master gone while its pid lived on was never dropped (every run failed); quit waited on
  `ssh -O exit` without limit; a pasted ssh answer with a newline sent its second line as a password try; the
  dialogs were not modal to VoiceOver.
- **r-tests.** The e2e helper served one request at a time, so a profile taken beside swipes measured an idle
  app; now threaded.
- **d-spec.** Pages still said "This Mac only" and had pre-relay plans; unbuilt parts are marked (the docs'
  Future work section).
- **r-terminal.** A dropped file name with a line break pasted as two lines; such paths are single-quoted.
- **r-strip.** A duplicate pane id in herdr's tree crashed the app (`Dictionary(uniqueKeysWithValues:)`); the
  missing-Perl reason now shows under Reconnecting; notices are announced to VoiceOver.
- **r-chrome.** One tab bar across pages carried a tab's announcement and rename to another session's tab with
  the same id; the tab bar is made per page. Hover panels keep the window they opened in.
- **r-store.** A refused split's stand-in waited for snapshots an idle session may never send; a closing key
  window cleared another window's looked-at tab.
- **r-app.** Any `oriel://x/` URL opened a workspace at `/` (now file URLs only); the Dock menu's New Tab did
  nothing with no window.
- **f-e2e.** A card's VoiceOver value still read "content 100%" from the dropped fade; a teardown that hovered a
  closing floating window failed a test after its body passed (it now warps the pointer). Two full runs in a
  row green on the last code commit, the on-demand suite once.

### Left (seen, not changed)

- **For the user.** Three store files sit at the 400-line limit (split when the next change needs room);
  Close Other Tabs within a round trip of ⌘T can leave the new tab open.

- **r-remote.** The sockets folder and askpass under `~/Library/Caches/oriel` are made once per launch
  (`static let`): a cache cleaner that deletes them while Oriel runs breaks remote connects until a relaunch
  (about 5 lines to make both per start). While a `dialog()` shows, the window's menu keys (⌘W, ⌘T, ⌘K)
  still act on the page under it, and Tab can leave the dialog.
- **r-herdrkit.** `TerminalStream.init` sets `onTermination` after its reader starts, so a stream that
  closes in that instant never calls `terminate` (harmless). A login shell slower than 3 s at launch finds
  no herdr until the next ask, 30 s later.
- **r-store.** `Ahead.programs` asks 8 at a time beside `HostStore.asks` (8 too): a close during the first
  snapshot's asks can make up to 16 herdr runs.
- **r-chrome.** The always-on test values (`tabs.fades`, `app.badge`, `window.look`) are VoiceOver elements
  in every window; hiding them needs a launch flag in the tests that read them. The IconButton label carries
  its shortcut glyphs because `testChromeButtonsNameTheirShortcuts` reads it. Folded Agents groups of closed
  workspaces stay in the defaults.
