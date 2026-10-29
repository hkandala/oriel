# Lessons

Problems that came back across phases, and the rule that stops each. How we work is in
[workflow.md](workflow.md); this file is what to watch out for while doing it.

## Testing the UI

- **Read the failing step and its screen recording before you rerun or guess** ([ci.md](ci.md#a-test-fails-only-on-ci)).
- **Write tests for CI's machine** ([ci.md](ci.md#layout)): pick windows by identifier, select far tabs by
  key, launch motion tests with `-forceMotion YES`.
- **Make every assertion fail without the feature, and see it fail on the old code** when that is cheap
  (locally, or a throwaway tag on CI). Typical blind checks: an absence checked before the menu opened, a wait already true, a
  check a fallback also satisfies.
- **Before a click, wait for what is drawn, not for herdr's or the model's state**, or the click lands on the
  old frame (a sliding button, a moved card, a menu still loading).
- **The accessibility tree misleads.** A container's or overlay's identifier leaks onto its children (put
  ids on leaf elements, before any `.overlay`); a hidden but kept view still has its ids; a window-sized
  element takes every hit test; a plain `Text` has an empty label (read its value); lazy stacks build only
  visible rows; a container's frame is the union of its children, and `.offset` or an overflowing child moves
  a frame away from what is drawn (place with padding); `.accessibilityElement(children: .ignore)` needs
  `.isStaticText` for its value to reach XCUITest. After a change to a shared surface (ids, keys, menu order,
  the chrome), grep the UI tests for it and run the ones that use it.
- **A query can wait out the accessibility timeout (6 s).** One that reaches a web view as its page starts (a
  popup) waited 6.1 s on CI, and the app drew nothing meanwhile: wait for a new web view's element for over 6 s.
- **Scope every query.** `app.windows.firstMatch` can be a tooltip, a hover card or a floating pane, and
  menu bar items share names with context menu items. Use `app.windows[id]` and the menu's own items.
- **An accessibility client changes the app it watches**: it hides lazy-layout bugs and slows large UIs.
  Check rendering once with no client (`make strip-check`) and speed on a Release build.
- **Trackpad touches can be synthesized.** An `IOHIDEvent` digitizer collection (its finger events as paths, plus
  a vendor child 0xff00/0x1777 holding the pad's `mthid` device id) on a gesture `CGEvent` (`SLEventSetIOHIDEvent`,
  field 87 the pad's registry id) reaches `NSEvent.allTouches()` as real touches, through the HID tap or a pid.
  AppKit builds touches lazily per event against app-wide state: reused finger ids after an unseen lift come as
  `.moved`.
- **Never post synthetic key events.** A key event posted with modifier flags but no modifier key-up leaves the
  session's modifiers down for every app. Keys reach the app only through XCUITest.
- **Know XCUITest's input gaps on macOS.** Drags need `click(forDuration:thenDragTo:)`; scroll is a wheel
  with no phases; a ⌘ key whose menu item is disabled is never delivered. Real trackpad gestures go
  through the e2e helper as HID events. It cannot read a menu checkmark (`isSelected` is false), hear an
  announcement or drive the Dock menu: check those by hand (`AXMenuItemMarkChar`, a screenshot).
- **Tests share defaults and saved windows with the user's Oriel (same bundle id).** Pin settings with
  launch arguments, reset them in teardown, launch with `-ApplePersistenceIgnoreState`. Saved windows live in
  `$TMPDIR/dev.hkandala.oriel.savedState` (not `~/Library/Saved Application State`): a restore check starts
  the app with `open`, attaches with `XCUIApplication(bundleIdentifier:)`, and deletes that folder after.
- **Each test restores what it changes** (defaults, herdr focus, the pointer, leftover sessions) and reads
  fixture ids from herdr instead of assuming them; otherwise it passes alone and fails in its shard.
- **Convert a screenshot to sRGB before you read its pixels.** Screenshots come in the display's profile
  (Display P3, "Color LCD"):
  `sips -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc" in.png --out out.png`. A screenshot's size is
  in pixels (divide by `backingScaleFactor`). Glass colors depend on the wallpaper: compare Glass looks on one
  desktop. `ImageRenderer` in a `swiftc` script measures a view's pixels without the app.
- **Never assert wall-clock time.** In unit tests compare against a ten times larger input or count the
  work.

## CI and git

- **A flake is a bug** ([ci.md](ci.md#a-test-fails-only-on-ci)).
- **Check exit codes; never pipe a check through `grep`.**
- **The 400-line file limit is a shared budget.** Several tracks add to the same big files: split a file that
  is close to the limit before adding to it, and check it after each rebase.
- **Automated rewrites change meaning.** Formatter rules and scripted replaces have flipped logic or matched
  nothing. Read the diff; make every scripted edit fail loudly when it matches nothing.

## herdr

- **Spike each herdr call in the exact shape the code sends, and check its side effects** on focus, folders
  and defaults: `pane.swap` moves focus despite `focus:false`; `pane.move` without a target splits the
  focused pane; some calls write outside the throwaway session (`worktree.create` writes to
  `~/.herdr/worktrees/`, so tests never call it). Trust the spike over the design pages.
- **`agent.prompt` needs a foreground process with the agent's name** (`claude`), also for an agent reported with
  `report-agent`: a stand-in agent runs under that name.
- **herdr ids repeat:** tab ids (`w1:t1`) across sessions, session names across machines. Key state by
  (machine, session, id).
- **Validate outside input before it reaches argv or a shell:** `oriel://` URLs, herdr metadata, dropped
  file names. Reject names that start with `-`.
- **Machine-wide resources have a budget too:** ptys (`kern.tty.ptmx_max`), herdr sessions. Make a stress
  session inside a GUI-lock hold and delete it in the same command.

## SwiftUI and AppKit

- **Inside a sideways scroll view (the strip), a SwiftUI scroll view of both axes gets no vertical wheel**: only its
  scroll bar moves it. Nest one scroll view per axis. A probe window that sends wheel events to itself
  (`window.sendEvent`) shows it without the GUI.
- **Re-check state after every `await` and before every delayed effect**: state read before an await, late
  drop or hover events after the action ended, an older write winning over a newer one, a double click
  starting two connects. Use generation counters and structured `.task`.
- **Design for the user's scale from the start:** hundreds of panes and tabs, remote machines, several
  windows. Anything built per tab costs at 300 tabs: build lists when a menu opens, no `@State` writes per
  frame, test hooks read once into a `static let`.
- **Never hide and fade to mask a flicker.** Keep the old frame shown until the new one has drawn.
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
  `allowsHitTesting` and per-move `@State` re-run whole subtrees; hidden views still lay out. Tools: one log
  line, an in-app frame probe or scroll meter, `sample` on the running app, a tiny probe app, the user's
  capture read frame by frame; memory and CPU with `footprint <pid>` (it leaves purgeable IOSurfaces out) and
  `top -l 2 -s 10 -pid <pid>`; xctrace's Animation Hitches crashes on attach. Measure keys and speed on a
  Release build launched by hand (`open -n`), with Quartz events: `sample` triples a key's time and
  XCUITest's accessibility snapshots dominate at scale.
- **Hover state is unreliable.** A view removed under the pointer gets no hover end, and a busy app runs
  hover late. Decide from the pointer's location when it matters.
- **Every key has three possible owners: the menu, SwiftUI and libghostty.** libghostty takes every key it
  gets and `NSMenu` swallows a disabled item's key. Log the menu action and `keyDown` in the first run
  before guessing.
- **Don't block Swift's cooperative pool** (`Process.waitUntilExit` in async code): await the exit through
  `terminationHandler`.

## The real app

- **Driving the real app by hand finds what the suite misses** (keys typing characters, a cold Dock drop).
  Write the test after the bug is found.
