# Phase 11: Settings window and terminal options

Goal: a native Settings window (⌘,) with a few basic settings, and the terminal options Rex has that
work over herdr. Later phases add their settings to this window.

Read first: `plan/ui-polish.md`, `plan/ui-layout.md`, `resources/research/clients/rex-ui.md` (settings
window, terminal settings), `docs/content/docs/data.mdx` (per-device settings live in app storage),
`docs/content/docs/ui/theme-and-accessibility.mdx` (text size), `Oriel/Terminal/PaneTerminal.swift`,
`Oriel/Terminal/PaneSurfaceView.swift` (Option key mapping, `ponytail:` note).

## Build

1. **The window.** A SwiftUI `Settings` scene (macOS only) with a `TabView` of four tabs, each a
   grouped `Form` (`.formStyle(.grouped)`), about 560 pt wide:
   - **General**: Appearance (Auto / Light / Dark, segmented), Interface Style (Glass / Classic, two
     cards with a small picture each, like Rex's interface cards; SF Symbols or a drawn mini window are
     fine). Later phases add tab settings here.
   - **Panes**: empty in this phase except a caption; phase 17 fills it. Do not show an empty tab: add
     the tab in phase 17 instead.
   - **Terminal**: font family (a picker of installed monospaced fonts, default the system monospaced
     font), font size (stepper 8–32, default 13), cursor style (Block / Bar / Underline), blinking
     cursor (toggle), Option key acts as Alt (Off / Both / Left / Right), copy on select (toggle).
   - **Notifications**: added by phase 15.
   Keep each setting one `@AppStorage` key. Settings that are not in this list do not exist.
2. **Font size keys.** View ▸ Bigger (⌘+ and ⌘=), Smaller (⌘-), Actual Size (⌘0) change the font
   size setting (8–32). This is the design's text size setting; the terminal follows it.
3. **Apply terminal settings live.** One shared `TerminalController` built from the settings (font
   family and size, `cursor-style`, `cursor-style-blink`, `copy-on-select`). A change reconfigures it at
   runtime (`updateConfigSource`); each surface's grid changes, so cards resize their PTYs through the
   existing resize path. Check that a font change resizes every shown PTY once, not once per keypress
   of the stepper (debounce 0.3 s).
4. **Option as Alt.** Today Option makes characters (`ponytail:` in `PaneSurfaceView`). With the
   setting on, an Option chord on a letter or digit goes to herdr as `alt+<key>` through `sendKeys`,
   for the chosen side(s). ⌥← / ⌥→ keep their `alt+b` / `alt+f` mapping either way.
5. **Cursor style.** herdr frames redraw the screen; check that the cursor shape set by the setting
   shows, and that a program's own cursor shape request (vim insert mode bar) still wins if herdr's
   frames carry it. Record what you find.
6. **Menu.** Oriel ▸ Settings… ⌘, opens the window (SwiftUI does this for a `Settings` scene).
7. **Docs.** A new design page `docs/content/docs/ui/settings.mdx` listing every setting, its default
   and which phase adds it (General, Panes, Terminal, Notifications). Add it to `ui/meta.json`. Update
   `theme-and-accessibility.mdx` (text size, keyboard table: ⌘+, ⌘-, ⌘0, ⌘,).

## e2e

- Open Settings with ⌘, ; change the font size; the terminal grid of a shown card changes (assert
  the `terminal.<pane_id>` accessibility value, "rows cols") and herdr's PTY size follows
  (`expectPTYSize`).
- ⌘+ then ⌘0 restores the size.
- Switch Appearance in Settings and assert `window.look`.

## Done when

- Settings screenshots of each tab in light and dark.
- The terminal follows font, size and cursor changes without reopening streams.
