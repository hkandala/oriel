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

- **Settings and menu.** `@AppStorage("appearance")` (default `dark`) and `@AppStorage("interfaceStyle")`
  (default `glass`) hold two `String` enums in `Style.swift`. View ▸ Appearance and View ▸ Interface Style
  are SwiftUI `Picker`s in the commands, which macOS draws as submenus with checkmarks. `ContentView` sets
  `NSApp.appearance` in `onChange(of: appearance, initial: true)`. Launch arguments (`-appearance light
  -interfaceStyle classic`) override the stored values without any parsing code.
- **`window.look`.** SwiftUI exposes no accessibility value on a container (`.contain`) or on a plain
  `accessibilityElement()` (role `AXUnknown`). So the value sits on a clear 1 × 1 pt leaf with the
  static-text trait, in the root view's top-left corner. At full size it took every accessibility hit test,
  and half the e2e suite failed. It has the identifier `window.look`, the label "Appearance" and a value
  such as `"glass dark"`. The value comes from the window's real `colorScheme` and the style setting, so
  Auto reports what the window draws.
- **Window material.** `.hudWindow` in both appearances. With the aqua appearance it draws light. Measured
  in Display P3 screenshots on the same desktop: Glass light window `#ececec`, keyboard card `#f9f9f9`
  (Rex `light-mode.jpg`: window `#f3f3f3`, card `#fbfbfb`).
- **Glass dark needed Rex's backdrop.** The blur with `#1e1e1e` at 0.5 alone measured `#606061`, much
  lighter than Rex's Glass (`#393939` between the cards in `glass-untinted.jpg`). Rex's Modern dark window
  also has a backdrop of black 0.6, blended `overlay`. Adding it (`Look.backdrop`, Glass dark only) gives
  `#353536`–`#393939`.
- **Classic dark card fill is white 0.018.** The table's white 0.035 gives `#262626`, not the `#222` on
  `#1e1e1e` it names (and Rex shows in `classic-untinted.jpg`). White 0.018 gives `#222`. The window is
  `#1e1e1e` (`#282828` in a Display P3 screenshot, the same pixels as Rex's).
- **Classic light window is plain `#f6f6f6`.** With white 0.5 over it (the table's value) the window
  measured `#fbfbfb` and the cards `#fdfdfd`–`#fefefe`, nearly flat. Plain `#f6f6f6` gives Rex's light
  steps (window `#f3f3f3`, card `#fbfbfb` in `light-mode.jpg`).
- **Keyboard card fill.** Drawn as a second fill over the card fill. Dark adds white 0.05 (Glass) or
  black 0.1 (Classic). Light uses white 2/3 (Glass) and 0.5 (Classic), which end at 0.7 and 0.8.
- **No black overlay on other cards.** The keyboard card's fill and stroke now mark it. Phase 17 adds the
  content fade (D64).
- **Card shadow.** A `ShadowStyle` on the card fill. On a translucent fill it comes out faint, so the light
  cards are separated mostly by their stroke, as in Rex's light shot.
- **Floating panels.** The palette lost its black tint, and both panels lost their custom shadows. Plain
  system glass adapts to each appearance and stays readable over terminal text in both.
- **Terminal palettes.** libghostty-spm's defaults (Alabaster light, Afterglow dark) read well in both
  appearances: prompt, `ls -G`, `git log --color`, vim syntax colors. As in most terminals, ANSI white
  (7, 15) nearly disappears on light cards and black (0) on dark ones. So no custom theme. Terminals in hidden tabs switch too: after a switch, going back to a hidden tab showed the new
  palette, and no stream reopened.
- **Status tokens.** `Look` has `working` and `needsYou`, the two colors a view draws today. Finished and
  error get their tokens (the values in the table above) in the phases that first draw them (14, 15, 21).
- **Lint.** A SwiftLint custom rule, `look_colors`, fails the build on the common color literals outside
  `Style.swift`: `Color(red:…)`, `Color.white`, `.white.opacity(…)`, `(.white)` and the other named
  colors. It covers the "Done when" grep on every commit. A gradient color list in a mask is not matched.
- **Clipping.** The strip and the title-bar tabs are scroll views, which clip. The 4 pt above the cards
  now sits inside each page, and the tab row has 5 pt above and below the capsules (the shadow's radius
  3.5 plus its offset 1.5). Otherwise the cards'
  outer stroke and the Classic pill's shadow get cut.
- **e2e.** `testMenuSwitchesTheLook` also checks that Auto follows the system's `AppleInterfaceStyle`: it
  first picks the other appearance, so an Auto that does nothing fails. The
  menu checkmarks were checked by hand (`AXMenuItemMarkChar`). The test starts on Glass, and a teardown block goes back to Glass Dark even
  after a failure, because the menu writes to the app's persistent defaults. The UI tests share those
  defaults with the user's own Oriel (same bundle id), so a run leaves the look at Glass Dark. `testLaunchesInEachLook` relaunches with the arguments for each look and checks that
  `stty size` matches the card's grid. Screenshots: `/tmp/oriel-shots/10/`.
