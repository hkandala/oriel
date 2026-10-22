# Phase 11: Settings window and terminal options

Goal: a native Settings window (⌘,) with a few basic settings, and the terminal options Rex has that
work over herdr. Later phases add their settings to this window.

Read first: `plan/ui-polish.md`, `plan/ui-layout.md`, `resources/research/clients/rex-ui.md` (settings
window, terminal settings), `docs/content/docs/data.mdx` (per-device settings live in app storage),
`docs/content/docs/ui/theme-and-accessibility.mdx` (text size), `Oriel/Terminal/PaneTerminal.swift`,
`Oriel/Terminal/PaneSurfaceView.swift` (Option key mapping, `ponytail:` note), decision D62,
`docs/content/docs/ui/settings.mdx`.

## Build

1. **The window.** A SwiftUI `Settings` scene (macOS only) with a `TabView` of four tabs, each a
   grouped `Form` (`.formStyle(.grouped)`), about 560 pt wide:
   - **General**: Appearance (Auto / Light / Dark, segmented), Interface Style (Glass / Classic,
     segmented).
   - **Panes**: added by phase 17.
   - **Terminal**: font family (a picker of installed monospaced fonts, default the system monospaced
     font), font size (stepper 8–32, default 13), cursor style (Block / Bar / Underline), blinking
     cursor (toggle), Option key acts as Alt (toggle, both sides), copy on select (toggle). Defaults as
     in `ui/settings.mdx`.
   - **Notifications**: added by phase 15.
   Keep each setting one `@AppStorage` key. Settings that are not in this list do not exist.
2. **Font size keys.** View ▸ Bigger (⌘+ and ⌘=), Smaller (⌘-), Actual Size (⌘0) change the font
   size setting (8–32). This is the design's text size setting; the terminal follows it. SwiftUI
   Commands cannot hide a menu item, so the second shortcut (⌘=) is a zero-size, zero-opacity `Button`
   with `.keyboardShortcut` in the window's content (not `.hidden()`, whose shortcuts do not fire). The
   menu shows the first shortcut. Phase 20 uses the same trick.
3. **Apply terminal settings live.** One shared `TerminalController` built from the settings (font
   family and size, `cursor-style`, `cursor-style-blink`, `copy-on-select`). On a change, rebuild the
   `TerminalConfiguration` from the settings and call `controller.setTerminalConfiguration(_:)`; check
   that live surfaces take the new font size. Each surface's grid changes, so cards resize their PTYs
   through the existing resize path and its 100 ms settle. No extra debounce; add one only if a
   measurement shows a flood of resizes.
4. **Option as Alt.** Today Option makes characters (`ponytail:` in `PaneSurfaceView`). With the
   setting on, an Option chord on a letter or digit goes to herdr as `alt+<key>` through `sendKeys`,
   for either Option key. ⌥← / ⌥→ keep their `alt+b` / `alt+f` mapping either way.
5. **Cursor style.** herdr frames redraw the screen; check that the cursor shape set by the setting
   shows, and that a program's own cursor shape request (vim insert mode bar) still wins if herdr's
   frames carry it. Record what you find.
6. **Menu.** Oriel ▸ Settings… ⌘, opens the window (SwiftUI does this for a `Settings` scene).
7. **Docs.** Make `ui/settings.mdx` and `theme-and-accessibility.mdx` (text size, keyboard table: ⌘+,
   ⌘-, ⌘0, ⌘,) match what you built.

## e2e

- Open Settings with ⌘, ; change the font size; the terminal grid of a shown card changes (assert
  the `terminal.<pane_id>` accessibility value, "rows cols") and herdr's PTY size follows
  (`expectPTYSize`).
- ⌘+ then ⌘0 restores the size.

## Done when

- Settings screenshots of each tab in light and dark.
- The terminal follows font, size and cursor changes without reopening streams.

## Findings

### Deviations

- **Two tabs, not four.** General and Terminal exist. Panes and Notifications come with their settings in
  phases 17 and 15 (their phase files add the tabs); empty tabs would be settings that do not exist.
- **Option as Alt covers every character key, not only letters and digits.** herdr accepts `alt+<any ASCII
  character>` (tested: `alt+!`, `alt+.`, `alt+[` reach `cat -v` as `^[!`, `^[.`, `^[[`), and ⌥. (Alt+. is
  readline's last argument) is a common chord. The key is the layout's character with Shift applied
  (`charactersIgnoringModifiers`), so ⌥⇧B is `alt+B` (`^[B`); a non-ASCII character falls back to the key's
  US character, as Ctrl chords already did.
- **The default font is the system monospaced font by name.** libghostty's own default is its embedded
  JetBrains Mono. "System Monospaced" (stored as an empty string) is rendered as
  `NSFont.monospacedSystemFont(…).familyName`, `.AppleSystemUIFontMonospaced`, which CoreText (and so
  libghostty) resolves to SF Mono. Every grid got a little narrower than before phase 11.
- **The Font Size row is a `LabeledContent` with "13 pt" and a stepper.** SwiftUI's stepper with a value
  field (`Stepper(value:in:step:format:)`) needs a floating point value; the setting is an `Int`.

### Decisions

- **Keys:** `fontFamily` (`""` = system), `fontSize` (`Int`, 13), `cursorStyle` (libghostty's
  `TerminalCursorStyle` raw value, `block`), `cursorBlink` (`true`), `optionAsAlt` (`false`),
  `copyOnSelect` (`false`), next to phase 10's `appearance` and `interfaceStyle`.
- **One place applies the terminal settings: the `App`.** `OrielApp` reads the five libghostty settings,
  builds a `TerminalConfiguration` (it is `Hashable`) and applies it to the one static
  `PaneTerminal.controller` in `init` (before any surface, so none starts at libghostty's 14 pt) and in a
  scene-level `onChange(of:)`. The controller's base keeps the fixed
  options (`keybind = clear`, transparent, no padding, no scrollback); `setTerminalConfiguration` lays the
  settings on top. Several windows (phase 16) share it as they are.
- **`macos-option-as-alt = false` in the controller's base.** With it unset, libghostty sent Alt for ⌥B on
  CI's keyboard layout (U.S.) and typed ∫ on this Mac's (ABC), so "off" depended on the layout. Now off
  always types the macOS character, and on always goes through herdr's key names.
- **Option as Alt is read per key press** (`UserDefaults.standard.bool(forKey: "optionAsAlt")` in
  `PaneSurfaceView.herdrKey`): no state to keep in sync, and it is cheap.
- **`copy-on-select = clipboard`.** libghostty-spm advertises a selection clipboard and drops writes to it,
  so Ghostty's `true` would copy nowhere; `clipboard` writes both, so the pasteboard gets the text.
- **Menu: View ▸ Bigger (⌘+), Smaller (⌘-), Actual Size (⌘0)**, after the appearance pickers, each disabled
  at its end of 8–32 (Actual Size at 13). ⌘= is a zero-size, zero-opacity, accessibility-hidden button in
  `ContentView`'s background.
- **One `LookPickers` view** holds the Appearance and Interface Style pickers for both View (submenus) and
  Settings ▸ General (`.pickerStyle(.segmented)` at the call site).
- **⌘W in a window without a store closes it.** File ▸ Close Pane replaces the system Close item; in the
  Settings window (no focused store) it reads "Close" and closes the window.
- **⌘= works only in the main window.** The invisible button lives in its content; in the Settings window
  ⌘+, ⌘- and ⌘0 (menu items) still work.
- **Settings tabs are found by label in tests.** SwiftUI's Settings tabs take no accessibility identifier;
  `testSettingsFontAndSizeResizeTheGrid` clicks the toolbar button "Terminal".
- **A stored font size outside 8–32** (`defaults write`, a launch argument) is clamped before it reaches
  libghostty.
- **Tests write the user's defaults and put them back.** The UI tests share the app's defaults (same bundle
  id, and the sandboxed runner cannot delete keys). Teardown blocks put the font size back with ⌘0 and the
  font test picks System Monospaced again; only a crash mid-test leaves a change behind, as in phase 10.
- **The font picker lists `NSFontManager.availableFontFamilies` whose regular face is fixed pitch** (on this
  Mac: Andale Mono, Anonymous Pro, Courier New, Fira Code, JetBrains Mono, Menlo, Monaco, PT Mono).
- **`Commands.swift`.** `OrielApp.swift` passed SwiftLint's 400-line limit, so the menu commands and their
  focused values moved to their own file (a pure move, its own commit).

### Assumptions

- **A config reload resizes surfaces that never changed their own size.** Ours never do (`keybind = clear`
  removed Ghostty's own ⌘+/⌘-), so the config's font size always wins. The e2e tests show it.
- **Settings stay per device.** `@AppStorage` writes the app's defaults (design: data).
- **The menu's "+" matches ⌘⇧= on a US layout.** It does here (`typeKey("+", .command)` and a real key
  press); other layouts were not tried.

### Learned

- **The terminal follows without a new stream.** A font size step changed `w1:p1`'s grid and its PTY
  (`stty size`), and the pid of its `terminal session` run stayed the same (`testSettingsFontAndSizeResizeTheGrid`, which also switches the font to Menlo and back).
  One step is one resize per surface through the existing 100 ms settle; no flood, so no extra debounce.
- **Cursor shape.** The setting's shape shows (bar and underline seen in screenshots). herdr's frames carry a
  program's DECSCUSR: `printf '\e[4 q'` turned the block cursor into an underline, and `\e[0 q` brought back
  the setting's block. So vim's insert-mode bar wins over the setting.
- **Copy on select works through the pasteboard.** A drag over `copyme-oriel` put it on the pasteboard with
  the setting on, and left the pasteboard alone with it off (checked by hand with `pbpaste`).
- **Global hotkeys eat test keys.** On this Mac Raycast takes ⌥⇧B and a scratchpad takes ⌥.; synthesized
  keys then land in another app and the test fails far from the cause. `testOptionKeyActsAsAlt` uses ⌥B
  and ⌥1 only. Before any synthesized key in a manual check, make Oriel frontmost first.
- **SwiftUI keeps a keyboard shortcut's first action.** The invisible ⌘= button's action kept its first
  `@AppStorage` copy, so after another key changed the size ⌘= added 1 to the size it last set itself (13 →
  17). `.id(fontSize)` makes a new button per size. `testFontSizeKeys` presses ⌘= after ⌘0 to catch it.
  Phase 20's second shortcuts need the same `.id`.
- **Screenshots** of both tabs in light and dark: `/tmp/oriel-shots/11/settings-{general,terminal}-{light,dark}.png`.
- **The Settings scene remembers its tab** (`com_apple_SwiftUI_Settings_selectedTabIndex`) and its frame, so
  a test clicks the tab it needs rather than assuming General.
- **⌥Space with Option as Alt** maps to `alt+space` (herdr gives ESC SPC). It did not reach the pane on
  this Mac in a manual check, likely a global hotkey; not covered by a test for the same reason.
- **Launch arguments pin a setting without persisting it.** `testOptionKeyActsAsAlt` relaunches with
  `-optionAsAlt YES` / `NO`; the font size tests change the persistent value and put it back with ⌘0 in a
  teardown block.
