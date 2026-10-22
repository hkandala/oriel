# Phase 10: appearance and interface style

Goal: Oriel draws in light or dark (or follows the system) and in two interface styles, Glass (today's
frosted look) and Classic (an opaque window), with Rex's surface values. Every later phase draws with
the tokens this phase makes.

Read first: `plan/ui-polish.md`, `plan/ui-layout.md`, `resources/research/clients/rex-ui.md`
(interface styles and materials, pane fade), `docs/content/docs/ui/theme-and-accessibility.mdx`,
decisions D44, D45, `Oriel/Views/Style.swift`, `Oriel/App/OrielApp.swift` (`Frosted`,
`.preferredColorScheme`), `Oriel/Terminal/PaneTerminal.swift` (the static `TerminalController`).

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

## e2e

- A test switches View ▸ Appearance and View ▸ Interface Style through the menu bar and keeps a
  screenshot of each of the four looks (attachments). Expose the current look on the window's root
  element (`accessibilityValue` like `"glass dark"`, id `window.look`) and assert it.
- One test launches in each of the four looks (launch arguments such as `-appearance light
  -interfaceStyle classic`) and asserts `window.look` and that a card's terminal draws. No parsing code:
  launch arguments land in UserDefaults' argument domain, which `@AppStorage` reads.

## Done when

- Four screenshots (Glass and Classic, light and dark) side by side with the Rex references, and the
  orchestrator agrees they match in spirit: same contrast steps, same card edges, readable terminals.
- No color literal left outside `Style.swift` (`grep -rn 'Color(red:\|Color.white\|Color.black' Oriel/`
  finds only `Style.swift`).

## Findings

### Deviations

- **Glass dark has Rex's backdrop too.** The table gives the blur plus `#1e1e1e` at 0.5. On this desktop
  that measured `#606061`, far lighter than Rex's Glass (`#393939` between the cards in
  `glass-untinted.jpg`). Rex's Modern dark window also has a backdrop of black 0.6, blended `overlay`.
  With it (`Look.backdrop`, Glass dark only) the window measures `#353536`–`#393939`.
- **Classic dark card fill is white 0.018, not 0.035.** The table says white 0.035 and "`#222` on
  `#1e1e1e`", but 0.035 gives `#262626`. White 0.018 gives `#222`, as the table names and Rex shows.
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

### Assumptions

- **The window's `colorScheme` is the truth.** `window.look` and `Look` derive dark or light from the
  environment's `colorScheme`, which follows `NSApp.appearance` and, in Auto, the system.
- **No launch flash.** `NSApp.appearance` is set in the first `onChange(initial:)`, not in `App.init`. No
  flash was seen launching light on this dark Mac; a light Mac launching dark was not tried.
- **Glass colors depend on the desktop.** All Glass measurements are on one wallpaper; another
  wallpaper (or the e2e runner's) gives other numbers. Compare Glass looks on the same desktop.

### Learned

- **Scroll views clip.** The strip and the title-bar tabs are scroll views. The 4 pt above the cards
  now sits inside each page, and the tab row has 5 pt above and below the capsules (the pill shadow's
  radius 3.5 plus its offset 1.5). Otherwise the top cards' outer stroke and the Classic pill's shadow are
  cut.
- **A full-size accessibility leaf hides everything under it.** At window size the `window.look` leaf
  answered every accessibility hit test, so XCUITest found no hit point for the strip and half the suite
  failed. Run the whole `make e2e` after an accessibility change, not only the new tests.
- **Shadows on translucent fills are faint.** A `ShadowStyle` on a white 0.1 fill casts a 0.1-strength
  shadow, so light cards are separated mostly by their stroke, as in Rex's light shot.
- **Terminals follow without a reopen.** `AppTerminalView` updates its scheme in
  `viewDidChangeEffectiveAppearance` and when it joins a window, so a terminal in a hidden tab shows the
  new palette when it comes back, with no new stream. ANSI white (7, 15) nearly disappears on light cards
  and black (0) on dark ones, as in most terminals.
- **Measuring colors.** `screencapture` writes Display P3; read pixels converted to sRGB (an `NSBitmapImageRep`
  helper). Classic dark: window `#282828`, card `#2d2d2d` in such a shot, the same pixels as Rex's
  screenshot. SwiftUI's `.overlay` blend needs `BlendMode.overlay` spelled out next to `.overlay(_:)`.
- **Settings persist across test runs.** The menu writes the app's persistent defaults, which the UI
  tests share with the user's own Oriel (same bundle id; the sandboxed runner cannot read them back).
  `testMenuSwitchesTheLook` starts on Glass, and a teardown block goes back to Glass Dark even after a
  failure. Launch arguments pin a setting: the argument domain hides what the menu writes.
- **e2e.** `testMenuSwitchesTheLook` picks the other appearance before Auto, so an Auto that does nothing
  fails. The menu checkmarks were checked by hand (`AXMenuItemMarkChar`). `testLaunchesInEachLook`
  relaunches in each look and checks that `stty size` matches the card's grid.
- **Other stopped sessions break an old test.** Many stopped sessions on this Mac pushed the e2e stopped
  session out of the session list's 320 pt scroll view, so its click landed outside the panel.
  `testShowStoppedRevealsStoppedSessionsAndPickingOneStartsIt` now types its name into the filter first.
