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
