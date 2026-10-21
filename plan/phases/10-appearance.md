# Phase 10: appearance and interface style

Goal: Oriel draws in light or dark (or follows the system) and in two interface styles, Glass (today's
frosted look) and Classic (an opaque window), with Rex's surface values. Every later phase draws with
the tokens this phase makes.

Read first: `plan/ui-polish.md`, `resources/research/clients/rex-ui.md` (interface styles and
materials, pane fade), `docs/content/docs/ui/theme-and-accessibility.mdx`, decisions D44, D45,
`Oriel/Views/Style.swift`, `Oriel/App/OrielApp.swift` (`Frosted`, `.preferredColorScheme`),
`Oriel/Terminal/PaneTerminal.swift` (the static `TerminalController`).

## Build

1. **Two settings in app storage** (`@AppStorage`, per device, design `data.mdx`):
   - `appearance`: `auto | light | dark`, default `dark` (today's look).
   - `interfaceStyle`: `glass | classic`, default `glass`.
   Menu: View ▸ Appearance ▸ Auto / Light / Dark and View ▸ Interface Style ▸ Glass / Classic, with
   checkmarks. Phase 11 adds the same pickers to Settings.
2. **Apply the appearance.** `.preferredColorScheme(nil | .light | .dark)` on the window (Auto = nil).
   Palette, session list and notices follow, because they use system glass.
3. **One token type** in `Style.swift`: a small `Look` value read from the environment
   (`@Environment(\.colorScheme)` plus the style setting). It holds only what views draw. No theme
   engine. Values (from Rex's Modern = Glass and System = Classic files; light values first measured,
   then tuned by eye against `resources/inspirations/rex-app/light-mode.jpg` and the classic shots):

   | Token | Glass dark | Glass light | Classic dark | Classic light |
   |---|---|---|---|---|
   | Window background | behind-window blur (`Frosted`) + `#1e1e1e` at 0.5 | behind-window blur + white at 0.5 | opaque `#1e1e1e` | opaque `#f6f6f6` + white at 0.5 |
   | Card fill (no keyboard) | white 0.04 | white 0.10 | white 0.035 (`#222` on `#1e1e1e`) | white 0.6 |
   | Card fill (keyboard card) | + white 0.05 | white 0.7 | + black 0.1 | white 0.8 |
   | Card inner rim | 0.7 pt white 0.1, `plusLighter` | 0.7 pt white 0.04, `plusLighter` | none | none |
   | Card outer stroke | 1 pt black 0.5, outside | 1 pt black 0.05, outside | 0.7 pt white 0.07, outside | 0.7 pt black 0.12 |
   | Keyboard card stroke | white 0.1 | black 0.07 | 0.8 pt white 0.1 | 0.8 pt black 0.18 |
   | Card shadow | none | black 0.1, radius 5, y 2 | none | black 0.06, radius 4, y 1 |
   | Hover fill (rows, tabs, buttons) | white 0.05 | black 0.05 | white 0.05 | black 0.05 |
   | Pressed fill | white 0.08 | black 0.08 | white 0.08 | black 0.08 |
   | Tab track (phase 13) | white 0.05 | black 0.05 | white 0.05 | black 0.05 |
   | Selected pill (tab marker, sidebar row) | Liquid Glass capsule (today's marker) | Liquid Glass capsule | white 0.08 + white 0.2 `overlay` + inner 0.8 pt white 0.1 `plusLighter` | white fill + 1 pt black 0.1 + shadow black 0.15 r 3.5 y 1.5 |
   | Working / needs you / finished | `#58a6ff` / `#d29922` / `#3fb950` | `#0667d8` / `#9d5c00` / `#116329` | as Glass dark | as Glass light |

   Floating panels (palette, session list, popups, hover card, notices, tooltips) keep system glass
   in both styles; Classic drops only the window blur and the glass selection pill.
   The 8 pt gap stays the one fixed layout size. Card radius becomes **10** (continuous) everywhere a
   card is drawn (`Strip.swift`).
4. **Window background.** `Frosted` takes the style: Glass keeps the behind-window
   `NSVisualEffectView` (material `.hudWindow` in dark; in light use the material that measures closest
   to Rex's light window, likely `.underWindowBackground` or `.hudWindow` with the aqua appearance;
   record what you chose). Classic draws a plain color, no blur. Keep `state = .active`.
5. **Terminal palette per appearance.** The terminal background stays transparent (the card shows).
   Use libghostty-spm's `TerminalTheme` (light + dark configurations; its default is Alabaster and
   Afterglow) and follow the window's appearance, so text stays readable on a light card. A change of
   appearance updates every live surface without reopening streams (`TerminalController` reconfigures
   at runtime: `updateConfigSource` / theme). Check contrast of the default prompt, `ls --color` and an
   agent TUI in both appearances; adjust the light foreground if needed.
6. **Replace hard-coded colors** in `Style.swift`, `Strip.swift`, `TitleBar.swift`, `Sidebar.swift`,
   `SessionPicker.swift`, `Palette.swift` with the tokens. `Color.tint`, `Color.card` and
   `Color.hairline` go away. `IconTile` stays as it is until phase 12.
7. **Docs.** Rewrite D44 (Auto, Light, Dark; Glass and Classic; no glass on cards; no themes) and the
   Theme section of `ui/theme-and-accessibility.mdx`. Update `plan/standards.md` ("Dark theme only"
   becomes the new rule). Status colors table: add the light values.

## e2e

- A test switches View ▸ Appearance and View ▸ Interface Style through the menu bar and keeps a
  screenshot of each of the four looks (attachments). Expose the current look on the window's root
  element (`accessibilityValue` like `"glass dark"`, id `window.look`) and assert it.
- The existing suite passes in all four looks (run it once with each default set by a launch
  argument `-appearance light -interfaceStyle classic`; the e2e run keeps the default).

## Done when

- Four screenshots (Glass and Classic, light and dark) side by side with the Rex references, and the
  orchestrator agrees they match in spirit: same contrast steps, same card edges, readable terminals.
- No color literal left outside `Style.swift` (`grep -rn 'Color(red:\|Color.white\|Color.black' Oriel/`
  finds only `Style.swift`).
