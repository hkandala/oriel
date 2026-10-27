# Phase 11: Font size and menus

Goal: the text size setting in the menu bar, applied live to every terminal, and the terminal defaults of
`ui/settings.mdx`. No Settings window: the user dropped it during this phase; it comes after its
mock-ups, once phases 10–21 are done (D62, future work).

## Build

1. **Font size keys.** View ▸ Bigger (⌘+ and ⌘=), Smaller (⌘-), Actual Size (⌘0) change the font size
   setting (one `@AppStorage` key, 8–32, default 13). This is the design's text size setting; the
   terminal follows it. SwiftUI Commands cannot hide a menu item, so the menu shows ⌘+ and an
   `NSEvent` key monitor takes ⌘= (see Findings).
2. **Apply the size live.** One shared `TerminalController`; on a change, call
   `controller.setTerminalConfiguration(_:)` with the new size; live surfaces take it. Each surface's grid
   changes, so cards resize their PTYs through the existing resize path and its 100 ms settle. No extra
   debounce; add one only if a measurement shows a flood of resizes.
3. **Terminal defaults** (`ui/settings.mdx`, fixed defaults): the system monospaced font (SF Mono), a
   blinking block cursor, Option types characters on every keyboard layout, no copy on select.
4. **Cursor shape.** herdr frames redraw the screen; check that the default block shows, and that a
   program's own cursor shape request (vim insert mode bar) wins if herdr's frames carry it. Record what
   you find.
5. **Docs.** `ui/settings.mdx` (what the menu bar covers, the fixed defaults, the window later),
   `theme-and-accessibility.mdx` (text size, keyboard table: ⌘+, ⌘-, ⌘0), D62, future work, and the
   later phase files: a setting they add goes in the menu bar only if they need a switch.

## Findings

### Deviations

- **No Settings window (user request, mid-phase).** Round 1 built the phase as written: a `Settings` scene
  with General and Terminal tabs of grouped `Form`s (font family, size, cursor style and blink, Option as
  Alt, copy on select). The user found it too plain and old-school; a Rex-style redesign was started, then
  the user chose to skip the window until it has mock-ups (after phases 10–21). The window, its views, its
  tests and the settings only it could change (font family, cursor style, blink, Option as Alt, copy on
  select) were removed with their keys and plumbing; terminals use the fixed defaults of `ui/settings.mdx`.
  The font size and the View menu stay. Later phase files were edited: phase 15 has no notification
  settings (fixed defaults, no sounds), phase 17's Fade Inactive Panes and Focus Follows Mouse are View
  menu toggles, phase 20 has no Cursor Style sub-page.
- **The default font is the system monospaced font by name.** libghostty's own default is its embedded
  JetBrains Mono. The controller's base sets `NSFont.monospacedSystemFont(…).familyName`
  (`.AppleSystemUIFontMonospaced`), which CoreText (and so libghostty) resolves to SF Mono. Every grid got
  a little narrower than before phase 11.
- **⌘= is an `NSEvent` local key monitor, not the phase's invisible button.** The button's shortcut kept its
  first action ([lessons.md](../lessons.md), SwiftUI lifecycle traps); the monitor (in `OrielApp.init`) takes
  ⌘ (Shift allowed) plus "=" below 32 and calls `stepFontSize(1)` before any view sees the key; at 32 the key
  goes on and beeps like the disabled Bigger. **⌘= is not tested on CI; checked by hand** (this Mac, and the round 3 E2E reviewer: key 24 steps,
  Caps Lock and keypad too). On CI, `testFontSizeKeys` failed at the ⌘= step in every run: CI's display is 1x,
  where 14 and 15 pt have the same cell width (48 columns), so the test's "both sides shrink" never held.
  Several fixes chased the wrong cause first (a stale button, a German layout, ⌘+ arriving as ⇧⌘=; a debug PR
  logged CI's key events and was closed). The orchestrator stopped the chase: the test checks ⌘+, ⌘0 and ⌘-,
  and accepts one side staying on a 1x display.

### Decisions

- **Key:** `fontSize` (`Int`, 13), next to phase 10's `appearance` and `interfaceStyle`.
- **The `App` applies the size**, in `init` (before any surface, so none starts at libghostty's 14 pt) and
  in a scene-level `onChange(of: fontSize)`, through `PaneTerminal.setFontSize`, which clamps to 8–32 and
  lays a one-line `TerminalConfiguration` over the controller's fixed base (`keybind = clear`, the font,
  transparent, no padding, no scrollback, `macos-option-as-alt = false`). Several windows (phase 16) share
  it as they are.
- **`macos-option-as-alt = false`.** With it unset, libghostty sent Alt for ⌥B on CI's keyboard layout and
  typed ∫ on this Mac's (ABC), so Option depended on the layout. The `ponytail:` note in `herdrKey` keeps
  the Option-as-Alt idea for the Settings window (herdr takes `alt+<any ASCII character>`, tested).
- **Menu: View ▸ Bigger (⌘+), Smaller (⌘-), Actual Size (⌘0)** after the appearance pickers, each disabled
  at its end of 8–32 (Actual Size at 13). Bigger and Smaller go through `PaneTerminal.stepFontSize`, which
  reads the stored value and clamps (SwiftUI keeps a shortcut's first action).
- **`Commands.swift`.** `OrielApp.swift` passed SwiftLint's 400-line limit during the phase, so the menu
  commands and their focused values moved to their own file (a pure move, its own commit).
- **The test writes the user's defaults and puts them back.** The UI tests share the app's defaults (same
  bundle id; the sandboxed runner cannot delete keys). A teardown block puts the size back with ⌘0; only a
  crash mid-test leaves a change behind, as in phase 10.
