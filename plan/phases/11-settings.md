# Phase 11: Font size and menus

Goal: the text size setting in the menu bar, applied live to every terminal, and the terminal defaults of
`ui/settings.mdx`. No Settings window: the user dropped it during this phase; it comes after its
mock-ups, once phases 10–21 are done (D62, future work).

Read first: `plan/ui-polish.md`, `plan/ui-layout.md`, `docs/content/docs/data.mdx` (per-device settings
live in app storage), `docs/content/docs/ui/theme-and-accessibility.mdx` (text size),
`docs/content/docs/ui/settings.mdx`, decision D62, `Oriel/Terminal/PaneTerminal.swift`,
`Oriel/Terminal/PaneSurfaceView.swift` (Option key mapping, `ponytail:` note).

## Build

1. **Font size keys.** View ▸ Bigger (⌘+ and ⌘=), Smaller (⌘-), Actual Size (⌘0) change the font size
   setting (one `@AppStorage` key, 8–32, default 13). This is the design's text size setting; the
   terminal follows it. SwiftUI Commands cannot hide a menu item, so the second shortcut (⌘=) is a
   zero-size, zero-opacity `Button` with `.keyboardShortcut` in the window's content (not `.hidden()`,
   whose shortcuts do not fire). The menu shows the first shortcut. Phase 20 uses the same trick.
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

## e2e

- ⌘+ and ⌘= make the grid of a shown card smaller (the `terminal.<pane_id>` accessibility value,
  "rows cols"), herdr's PTY size follows (`expectPTYSize`), the stream is not opened again; ⌘0 restores
  the size, ⌘= after ⌘0 is one step bigger, ⌘- goes back.

## Done when

- The terminal follows size changes without reopening streams.

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
  at its end of 8–32 (Actual Size at 13). ⌘= is a zero-size, zero-opacity, accessibility-hidden button in
  `ContentView`'s background. Bigger and Smaller (both keys) go through `PaneTerminal.stepFontSize`, which
  reads the stored value (see Learned).
- **`Commands.swift`.** `OrielApp.swift` passed SwiftLint's 400-line limit during the phase, so the menu
  commands and their focused values moved to their own file (a pure move, its own commit).
- **The test writes the user's defaults and puts them back.** The UI tests share the app's defaults (same
  bundle id; the sandboxed runner cannot delete keys). A teardown block puts the size back with ⌘0; only a
  crash mid-test leaves a change behind, as in phase 10.

### Assumptions

- **A config reload resizes surfaces that never changed their own size.** Ours never do (`keybind = clear`
  removed Ghostty's own ⌘+/⌘-), so the config's size always wins. The e2e test shows it.
- **The menu's "+" matches ⌘⇧= on a US or ABC layout.** It does here and on CI; other layouts were not
  tried.

### Learned

- **The terminal follows without a new stream.** A size step changes `w1:p1`'s grid and its PTY
  (`stty size`), and the pid of its `terminal session` run stays the same (`testFontSizeKeys`). One step is
  one resize per surface through the existing 100 ms settle; no flood, so no extra debounce.
- **Cursor shape.** herdr's frames carry a program's DECSCUSR: `printf '\e[4 q'` turned the block cursor
  into an underline, `\e[0 q` brought back the block, and vim's insert-mode bar shows.
- **SwiftUI keeps a keyboard shortcut's first action.** The invisible ⌘= button's action kept its first
  `@AppStorage` copy: after another key changed the size, ⌘= added 1 to the size it last set itself
  (13 → 17). `.id(fontSize)` on the button fixed it locally but not on CI, where ⌘= came right after ⌘+,
  before the view rebuilt. Reading `UserDefaults` in the action fixes it. `testFontSizeKeys` presses ⌘=
  right after ⌘+ and again after ⌘0. Phase 20's second shortcuts must read current state too.
- **libghostty-spm drops selection-clipboard writes**, so Ghostty's `copy-on-select = true` copies nowhere;
  a future switch needs `clipboard` (checked by hand: a drag then put the text on the pasteboard).
- **Global hotkeys eat test keys.** On this Mac Raycast takes ⌥⇧B and a scratchpad takes ⌥.; synthesized
  keys then land in another app. Make Oriel frontmost before any synthesized key in a manual check.
- **The user may step in.** Mid-phase the user asked a reviewer to stop driving the Mac; the phase ran
  e2e on CI only for a while (CI runs the whole suite on every push) until the user allowed local runs
  again.
