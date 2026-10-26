# Phase 10: appearance and interface style

Goal: Oriel draws in light or dark (or follows the system) and in two interface styles, Glass (today's
frosted look) and Classic (an opaque window), with Rex's surface values. Every later phase draws with
the tokens this phase makes.

## Build

1. **Two settings in app storage** (`@AppStorage`, per device, design `data.mdx`):
   - `appearance`: `auto | light | dark`, default `dark` (today's look).
   - `interfaceStyle`: `glass | classic`, default `glass`.
   Menu: View ▸ Appearance ▸ Auto / Light / Dark and View ▸ Interface Style ▸ Glass / Classic, with
   checkmarks. Phase 11 adds the same pickers to Settings.
2. **Apply the appearance.** When the setting changes, set `NSApp.appearance` to `nil` (Auto),
   `NSAppearance(named: .aqua)` or `NSAppearance(named: .darkAqua)`. This covers every window, sheet,
   menu and the Settings window. Remove `.preferredColorScheme(.dark)` (`OrielApp.swift`).
3. **One token type** in `Style.swift`: a small `Look` value read from the environment
   (`@Environment(\.colorScheme)` plus the style setting). It holds only what views draw. No theme
   engine. Values (from Rex's Modern = Glass and System = Classic files; light values first measured,
   then tuned by eye against the Rex reference shots and the classic shots):

   | Token | Glass dark | Glass light | Classic dark | Classic light |
   |---|---|---|---|---|
   | Window background | behind-window blur (`Frosted`) + `#1e1e1e` at 0.5 | behind-window blur + white at 0.5 | opaque `#1e1e1e` | opaque `#f6f6f6` + white at 0.5 |
   | Card fill (no keyboard) | white 0.04 | white 0.10 | white 0.035 (`#222` on `#1e1e1e`) | white 0.6 |
   | Card fill (keyboard card) | + white 0.05 | white 0.7 | + black 0.1 | white 0.8 |
   | Card inner rim | 0.7 pt white 0.1, `plusLighter` | 0.7 pt white 0.04, `plusLighter` | none | none |
   | Card outer stroke | 1 pt black 0.5, outside | 1 pt black 0.05, outside | 0.7 pt white 0.07, outside | 0.7 pt black 0.12 |
   | Keyboard card stroke | white 0.1 | black 0.07 | 0.8 pt white 0.1 | 0.8 pt black 0.18 |
   | Card shadow | none | black 0.1, radius 5, y 2 | none | black 0.06, radius 4, y 1 |
   | Selected pill (tab marker, workspace row) | Liquid Glass capsule (today's marker) | Liquid Glass capsule | white 0.08 + white 0.2 `overlay` + inner 0.8 pt white 0.1 `plusLighter` | white fill + 1 pt black 0.1 + shadow black 0.15 r 3.5 y 1.5 |
   | Working / needs you / finished | `#58a6ff` / `#d29922` / `#3fb950` | `#0667d8` / `#9d5c00` / `#116329` | as Glass dark | as Glass light |
   | Error / behind | `#f85149` | `#cf222e` | as Glass dark | as Glass light |

   Hover fill, pressed fill and the tab track (phase 13) are the same in both styles: use
   `Color.primary.opacity(0.05)`, `0.08` and `0.05`, which follow the appearance by themselves. They are
   not tokens. The status colors can be asset-catalog color sets (Any / Dark) that `Look` names.

   Floating panels (palette, title-row menus and popovers, sheets, hover card, notices) keep
   system glass in both styles; Classic drops only the window blur and the glass selection pill. The
   8 pt gap stays the one fixed layout size. Card radius becomes **10** (continuous) everywhere a card
   is drawn (`Strip.swift`).
4. **Window background.** `Frosted` takes the style: Glass keeps the behind-window
   `NSVisualEffectView` (material `.hudWindow` in dark; in light use the material that measures closest
   to Rex's light window, likely `.underWindowBackground` or `.hudWindow` with the aqua appearance;
   record what you chose). Classic draws a plain color, no blur. Keep `state = .active`.
5. **Terminal palette per appearance.** The terminal background stays transparent (the card shows).
   The surfaces already follow the window's appearance (`AppTerminalView` calls
   `controller.setColorScheme` from `viewDidChangeEffectiveAppearance`; the default theme is
   `TerminalTheme.default`, light + dark). Only check contrast of the default prompt, `ls --color` and an
   agent TUI in both appearances. If needed, pass a `TerminalTheme(light:dark:)` to the controller.
6. **Replace hard-coded colors** in `Style.swift`, `Strip.swift`, `TitleBar.swift`, `Sidebar.swift`,
   `SessionPicker.swift` (phase 14 replaces it with the Open Session sheet), `Palette.swift` with the
   tokens. `Color.tint`, `Color.card` and `Color.hairline` go away. `IconTile` stays as it is until
   phase 12.
7. **Docs.** Make D44 and the theme section of `ui/theme-and-accessibility.mdx` match what you built.

## Findings

### Deviations

- **Glass dark has Rex's backdrop too.** The table gives the blur plus `#1e1e1e` at 0.5. On this desktop
  that measured `#606061`, far lighter than Rex's Glass (`#393939` between the cards in
  `glass-untinted.jpg`). Rex's Modern dark window also has a backdrop of black 0.6, blended `overlay`.
  With it (`Look.backdrop`, Glass dark only) the window measures `#353536`–`#393939`.
- **Classic dark card fill is white 0.018, not 0.035.** The table says white 0.035 and "`#222` on
  `#1e1e1e`", but 0.035 gives `#262626`. White 0.018 gives `#222`, as the table names and Rex shows. The
  keyboard card adds black 0.1 (Rex's System `activePane`), so it lands at `#1f1f1f`, one step from the
  window; its 0.8 pt stroke marks it.
- **Classic light window is plain `#f6f6f6`.** With the table's white 0.5 on top, the window measured
  `#fbfbfb` and the cards `#fdfdfd`–`#fefefe`, nearly flat. Plain `#f6f6f6` gives Rex's light steps
  (window `#f3f3f3`, card `#fbfbfb` in `light-mode.jpg`). The theme page says `#f6f6f6`.
- **`window.look` is a 1 × 1 pt leaf, not the root element.** SwiftUI exposes no accessibility value on
  a container (`.contain`), nor on a plain `accessibilityElement()` (role `AXUnknown`). So the value sits
  on a clear leaf with the static-text trait, in the root view's top-left corner: identifier
  `window.look`, label "Appearance", value such as `"glass dark"`, sorted last for VoiceOver.
- **Only two status tokens.** `Look` has `working` and `needsYou`, the two colors a view draws today.
  Finished and error get their tokens (the table's values) in the phases that first draw them (14, 15,
  21). The phase says `Look` holds only what views draw.
- **No dim overlay on cards without the keyboard.** The black overlay was a color literal and looked
  dirty in light. The keyboard card's fill and stroke now mark it. Phase 17 adds the content fade (D64).
- **Floating panels lost their custom look.** The palette's black tint and both panels' shadows are gone.
  Plain system glass adapts to each appearance and stays readable over terminal text in all four looks.
- **Classic dark pill has no white 0.2 `overlay` layer.** The pill sits in layers of its own (the tab
  bar's masked scroll view, the sidebar row), so the overlay blend had nothing under it and acted as a
  plain white 0.2 fill: `#6c6c6c` in the tab bar, `#4a4a4a` in the sidebar, against Rex's `#363636` (Display P3 reads).
  Without it (the table's white 0.08 and the 0.8 pt `plusLighter` rim) both measure `#303030` on the
  `#1e1e1e` window (sRGB), against Rex's `#292929`: a little brighter, kept at the table's value.
- **Card shadows are weaker than the table.** The shadow is a `ShadowStyle` on the translucent card fill,
  so its strength is multiplied by the fill's alpha: about black 0.01 in Glass light (table 0.1) and 0.036
  in Classic light (table 0.06). The light cards are separated mostly by their stroke, as in Rex's light
  shot. A full-strength shadow needs an opaque copy of the shape with the card's area cut out.

### Decisions

- **Settings and menu.** `@AppStorage("appearance")` (default `dark`) and `@AppStorage("interfaceStyle")`
  (default `glass`) hold two `String` enums in `Style.swift`. View ▸ Appearance and View ▸ Interface Style
  are SwiftUI `Picker`s in the commands; macOS draws them as submenus with checkmarks. `ContentView` sets
  `NSApp.appearance` in `onChange(of: appearance, initial: true)`.
- **Window material: `.hudWindow` in both appearances.** With the aqua appearance it draws light. Glass
  light measured window `#ececec`, keyboard card `#f9f9f9` (Rex `light-mode.jpg`: `#f3f3f3`, `#fbfbfb`).
- **Keyboard card fill is a second fill over the card fill.** Dark adds white 0.05 (Glass) or black 0.1
  (Classic). Light adds white 2/3 (Glass) and 0.5 (Classic), which end at the table's 0.7 and 0.8.
- **Card shape and edges in one view.** `CardSurface` draws the fill, the `plusLighter` rim and the
  stroke just outside the edge (`inset(by: -width / 2)`); `Pill` draws the selected tab and row (Liquid
  Glass in Glass, the raised pill in Classic). Both read `Look` from the environment.
- **Lint rule instead of a grep.** A SwiftLint custom rule, `look_colors`, fails on common color
  literals outside `Style.swift`: `Color(red:…)`, `Color(.sRGB, …)`, `Color(nsColor:)`, `Color.white`,
  `.white.opacity(…)`, `(.white)` and the other named colors. A gradient color list in a mask is not
  matched.
- **No custom terminal theme.** libghostty-spm's defaults (Alabaster light, Afterglow dark) read well:
  prompt, `ls -G`, `git log --color`, vim syntax colors.
- **Glass dark cards stay lighter than the window.** The table's white 0.04 is kept. In Rex's shot the
  cards without the keyboard are darker than the window, from Rex's per-pane backdrop; phase 17's fade
  brings that contrast.
