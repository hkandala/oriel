# Lessons

Problems that came back across phases, and the rule that stops them. Each one cost real time more than once.
How we work is in [workflow.md](workflow.md); this file is what to watch out for while doing it.

## Testing the UI

- **Wait on conditions with 100 ms polls; never sleep or use XCTest's waits.** XCTest's waits poll about
  once a second and were a third of the suite's time; sleeps flake.
- **Read the failing step and its screen recording before you rerun or guess.** Guessing at one CI-only
  failure cost two hours and ten runs; the recording showed most causes in one look.
- **Write tests for CI's machine:** a 1x display, a small window where windows overlap and only about three
  tabs fit, the US layout, Reduce Motion on. Pick windows by identifier, select far tabs by key, launch
  motion tests with `-forceMotion YES`. Each of these broke tests that were green locally.
- **Make every assertion fail without the feature, and prove it on the old code** (a throwaway tag, put
  both run ids in Findings). "Tests that cannot fail" was the reviewers' most repeated catch: an absence
  checked before the menu opened, a wait already true, a check a fallback also satisfies.
- **Before a click, wait for what is drawn, not for herdr's or the model's state.** Otherwise the click
  lands on the old frame (a sliding button, a moved card, a menu still loading).
- **The accessibility tree misleads.** A container's or overlay's identifier leaks onto its children (put
  ids on leaf elements, before any `.overlay`); a hidden but kept view still has its ids (duplicates); a
  window-sized element takes every hit test; a plain `Text` has an empty label (read its value); lazy
  stacks build only visible rows. After a change to a shared surface (ids, keys, menu order, the chrome),
  grep the UI tests for it and run the whole suite.
- **Scope every query.** `app.windows.firstMatch` can be a tooltip, a hover card or a floating pane, and
  menu bar items share names with context menu items. Use `app.windows[id]` and the menu's own items.
- **An accessibility client changes the app it watches.** It hides lazy-layout bugs and slows large UIs.
  Check rendering and speed once with no client (`make strip-check`, a Release build).
- **Know XCUITest's input gaps on macOS.** Drags need `click(forDuration:thenDragTo:)`; scroll is a wheel
  with no phases; a ⌘ key whose menu item is disabled is never delivered. Real trackpad gestures go
  through the e2e helper as HID events.
- **Keep tearDown safe:** synchronous, async helpers fail by throwing, the pointer moved off the chrome,
  state restored before the tabs it lives in close. A bad teardown hangs two minutes and loses the
  recording.
- **Tests share defaults and saved windows with the user's Oriel (same bundle id).** Pin settings with
  launch arguments, reset them in teardown, launch with `-ApplePersistenceIgnoreState`.
- **Each test restores what it changes** (defaults, herdr focus, the pointer, leftover sessions) and reads
  fixture ids from herdr instead of assuming them. A test that passes alone fails in its shard.
- **Never assert wall-clock time.** CI's VMs are slower and uneven; in unit tests compare against a ten
  times larger input or count the work.

## CI

- **A flake is a bug.** Fix it at its cause and prove it with two full runs in a row green on the first
  try. "Taken as a flake" came back every time.
- **Run `make lint` on the rebased tree and check exit codes; never pipe a check through `grep`.** Main went
  red from a rebase that pushed a file over the length limit, and from a piped command that hid a failure.
- **The 400-line file limit is a shared budget.** Several lanes add to the same big files: check `wc -l`
  after each rebase and split a file that is close to the limit before adding to it.

## herdr

- **Spike each herdr call in the exact shape the code sends, and check its side effects** on focus, folders
  and defaults. `pane.swap` moves focus despite `focus:false`; `pane.move` without a target splits the
  focused pane; some calls write outside the throwaway session. The design pages were wrong about herdr
  more than once.
- **herdr ids repeat:** tab ids (`w1:t1`) across sessions, session names across machines. Key state by
  (machine, session, id).
- **Remote machines get one multiplexed SSH connection each:** hosts with one-time passcodes or a low
  `MaxSessions` refuse more. CI's sshd runs with `MaxSessions 2` to catch it.
- **Validate outside input before it reaches argv or a shell:** `oriel://` URLs, herdr metadata, dropped
  file names. Reject names that start with `-`.
- **Machine-wide resources have a budget too:** ptys (`kern.tty.ptmx_max`), herdr sessions. A stress session
  with hundreds of panes starved other agents and the user's terminals: make it inside a GUI-lock hold and
  delete it in the same command.

## SwiftUI and AppKit

- **Re-check state after every `await` and before every delayed effect.** The same races came back in
  every phase: state read before an await, late drop or hover events after the action ended, an older
  write winning over a newer one, a double click starting two connects. Use generation counters and
  structured `.task`.
- **Design for the user's scale from the start:** hundreds of panes and tabs, remote machines, several
  windows. Anything built per tab costs at 300 tabs (build lists when a menu opens, no `@State` writes per
  frame, test hooks read once into a `static let`). Keep-everything-live designs were redone twice.
- **Never hide and fade to mask a flicker.** It caused blank panes. Keep the old frame shown until the new
  one has drawn.
- **View identity cuts both ways.** A view shared by all workspaces carries stale scroll and lazy state; an
  `.id` per page makes a fresh view that flickers at offset 0.
- **An overlay blocks every input path to the page below:** swipes, the wheel, menu shortcuts and clicks.
  Check all of them when you add one.

- **A new or lazy scroll view's first layout lies.** The first scroll position gets dropped,
  `containerRelativeFrame` resolves to the window, `.task` in a lazy stack is cancelled, and overlays get
  clipped. Use `defaultScrollAnchor(_:for: .initialOffset)`, a GeometryReader, or `onAppear` plus a Task.
- **SwiftUI lifecycle traps:** it keeps the first closure (read current state inside actions); a first
  responder set during an update is undone (take focus on the next run-loop turn); a `@State` initializer
  runs again on every parent rebuild (no side effects in it); the menu bar refreshes only when the focused
  value changes.
- **Measure before you optimize.** Observation notifies on in-place edits that change nothing;
  `allowsHitTesting` and per-move `@State` re-run whole subtrees; hidden views still lay out. What worked:
  one log line, an in-app frame probe, `sample` on the running app, xctrace Animation Hitches on a Release
  build, a tiny probe app for one SwiftUI behavior, and the user's capture read frame by frame.
- **Hover state is unreliable.** A view removed under the pointer gets no hover end, and a busy app runs
  hover late. Decide from the pointer's location when it matters.
- **Every key has three possible owners: the menu, SwiftUI and libghostty.** libghostty takes every key it
  gets and `NSMenu` swallows a disabled item's key. Log the menu action and `keyDown` in the first run
  before guessing.
- **Don't block Swift's cooperative pool** (`Process.waitUntilExit` in async code): with tests in parallel
  on a small machine, other tasks starve. Await the exit through `terminationHandler`.

## Working with agents

- **Show a rough screenshot of a new view before polishing it.** A whole Settings window was built, then
  dropped.
- **Hold every surface to the design bar** (workflow, Code). The user had to ask again and again for the
  About panel, the remote machine dialogs and glass contrast: stock panels and text dumps shipped because
  nobody compared a screenshot with the glass surfaces.
- **Automated rewrites change meaning.** Formatter rules and scripted replaces have flipped logic or
  matched nothing. Read the diff; make every scripted edit fail loudly when it matches nothing.
- **Never `git checkout <file>` to drop debug lines in a dirty tree:** it reverts the phase's other work in
  that file. Remove them with an edit.
- **Driving the real app by hand finds what the suite misses** (keys typing characters, a cold Dock drop).
  Write the test after the bug is found.
