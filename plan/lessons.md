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
- **Prove a new test is red on the old code before you trust the fix.** Build the old code from a throwaway
  tag. Several guards passed on the bug they were meant to catch.
- **Before a click, wait for what is drawn, not for herdr's or the model's state.** Otherwise the click
  lands on the old frame (a sliding button, a moved card, a menu still loading).
- **Accessibility identifiers go on leaf elements, before any `.overlay`.** A container's or overlay's
  identifier leaks onto its children and gives duplicate matches. After any accessibility or overlay
  change, run the whole suite: a view laid over content takes every hit test.
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
- **Tests undo the herdr state they change**, so the next test starts from the known layout.

## CI

- **A flake is a bug.** Fix it at its cause and prove it with two full runs in a row green on the first
  try. "Taken as a flake" came back every time.
- **Run `make lint` on the rebased tree and check exit codes; never pipe a check through `grep`.** Main went
  red from a rebase that pushed a file over the length limit, and from a piped command that hid a failure.

## herdr

- **Spike each herdr call in the exact shape the code sends, and check its side effects** on focus, folders
  and defaults. `pane.swap` moves focus despite `focus:false`; `pane.move` without a target splits the
  focused pane; some calls write outside the throwaway session. The design pages were wrong about herdr
  more than once.

## SwiftUI and AppKit

- **A new or lazy scroll view's first layout lies.** The first scroll position gets dropped,
  `containerRelativeFrame` resolves to the window, `.task` in a lazy stack is cancelled, and overlays get
  clipped. Use `defaultScrollAnchor(_:for: .initialOffset)`, a GeometryReader, or `onAppear` plus a Task.
- **SwiftUI keeps the first closure, and a first responder set during an update is undone.** Read the
  current state inside actions; take focus on the next run-loop turn.
- **Measure what redraws before you optimize.** Observation notifies on in-place edits that change
  nothing; `allowsHitTesting` and per-move `@State` re-run whole subtrees; hidden views still lay out. One
  log line or a small probe answers in one run.
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
- **Automated rewrites change meaning.** Formatter rules and scripted replaces have flipped logic or
  matched nothing. Read the diff; make every scripted edit fail loudly when it matches nothing.
- **Never `git checkout <file>` to drop debug lines in a dirty tree:** it reverts the phase's other work in
  that file. Remove them with an edit.
- **Driving the real app by hand finds what the suite misses** (keys typing characters, a cold Dock drop).
  Write the test after the bug is found.
