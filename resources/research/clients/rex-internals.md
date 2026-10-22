# Rex internals: how Rex builds its UI (facts for implementers)

From a static look at Rex Beta build 1327 (`com.superlogical.rex`): type names, settings keys, constants
and timings found in the binary. No decompiled code is here, and none may be copied: use this file for
structure and numbers, and write Oriel's own code. Behavior, geometry and colors seen on screen are in
[rex-ui.md](rex-ui.md); that file wins where the two differ. Marks: [F] found in the binary, [I] inferred.

## 1. Modules and packages [F]

Swift modules compiled into the one executable (from type metadata and `#file` strings; count = source files seen):

| Module | Files | Role |
|---|---|---|
| `RexMacOS` (SwiftPM target in package `RexApp`, resources in `RexApp_RexMacOS.bundle`) | 281 | All macOS UI. Most view types are nested as `extension RexShared.Workspace { class X }`, so ObjC names look like `_TtCE8RexMacOSO9RexShared9Workspace20HorizontalTabBarView`. |
| `Rex` | 1 | App entry (`ResourceBundleClass` only). |
| `RexShared` | 26 | Platform-neutral workspace model shared with iOS: actions (`RexAction`), program activity, themes (`ThemeSettings`, `CustomThemeStore`, Ghostty/iTerm importers, OKLCH color math), shortcut editor, remote hosts, titles, `PaneMinimap`, `LaunchReveal`, `RexNotice`. |
| `RexSync` | 16 | Client-side sync engine: `Hub`, `Server`, `Session`, `Window`, `WindowPresentation`, mutations, snapshots, block ownership, checkpoints. |
| `RexAPI` | 3 (+generated) | Wire types for the server control API (484 types: `session.*`, `block.*`, `client.*`, `hosts.*`, `server.*`), control/data WebSocket + pipe transports, API-revision translation. |
| `RexCompat` | 2 | API history registry, JSON-pointer rewrites between API revisions. |
| `RexActions` | 2 | `ActionCenter`, `KeyRouter` (key sequences, modes, pending keys), `ShortcutTable`, Lua value bridge. |
| `RexTerminal`, `RexSyncTerminal` | 1+2 | Terminal data stream (`rex.data.terminal.v1`, `com.superlogical.rex.terminal-v1`), live terminal, input. |
| `SuperSplit` | 17 | Pane split layout engine (AppKit + SwiftUI): dividers, drag/drop of panes, glass, motion, accessibility. |
| `SuperDesignTokens` (bundle `SuperUI_SuperDesignTokens`) | 1 | Themes (`themes.json`), color roles (`accent-container`, `content-secondary`, `terminal-ansi-*`, ...), `SuperTheme`, `SuperCubicBezier`. `themes.json` holds 41 built-in themes (e.g. Merino Light/Dark = current defaults, Abyssal Trench, Alpine Milk, Cathode Amber, Neon Arcade, Static Noir, Whitby Bay …), each `{id, name, appearance, source, palette, semantic, cssVariables}`. |
| `SuperBlockIcons` | 10 | Per-program icon catalog ("block icons": glyph + gradient + mesh backgrounds), `BlockGroupIconView` (stack of pane icons in a tab, attention/swap/reorder animations), icon package editor. Recognizes e.g. `pi-coding-agent/dist/cli.js`, `copilot/npm-loader.js`, jupyter, `Shell - caffeinate`. |
| `GhosttyVT`, `GhosttyTerminal`, `GhosttyRender` (package `swift-ghostty`, bundle `swift-ghostty_GhosttyRender`) | 9 | libghostty-vt terminal core (`0.1.0-dev`), AppKit `SurfaceView`, Metal renderer, Symbols Nerd Font. Embedded C ABI JSON lists `GHOSTTY_PROGRAM_STATUS_STATE_{IDLE,WORKING,DONE,BLOCKED,ERROR,CLEAR}`, `..._KIND_{NONE,PERMISSION,QUESTION,AUTH}`, OSC `PROGRAM_STATUS`(28), ConEmu progress, Kitty notifications. |
| `Monoh` | — | 24 types; `monoh.engine` (unclear; diagnostics/engine). |
| swift-nio (NIOCore/Posix/HTTP1/WebSocket/TransportServices/TLS), swift-atomics, swift-collections (DequeModule) | — | Networking. |

Frameworks linked: Sparkle 2.9.6, SwiftUI, AppKit, Charts (GPU diagnostics), ScreenCaptureKit (tab tear-off
snapshot), UserNotifications, AVFAudio (sounds), Metal, Symbols, Network, CryptoKit, Carbon (keyboard layout),
Accessibility. No `.sdef` (no AppleScript dictionary), no App Intents, no NSUserActivity. [F]

## 3. Feature inventory (grouped)

### 3.1 App shell, windows, launch [F]
- Delegate selectors: `applicationDidFinishLaunching:`, `applicationShouldHandleReopen:hasVisibleWindows:`,
  `applicationDockMenu:` (Dock menu lists sessions → tabs with activity, `DockMenu.Row{sessionTitle, tabID, blockID, title}`),
  `newWindowFromDock:`, `application:openURLs:` (Finder drops: "Routing Dock directory drop count=%ld"; opens
  directories as new sessions via `InitialPresentation.openDirectories`), `applicationShouldTerminate:`.
- `CFBundleDocumentTypes` = `public.item` Viewer/Alternate → dropping folders on the Dock icon opens them.
- Window model: SwiftUI `WindowGroup` (`session-AppWindow-1` autosave) hosting AppKit chrome. `NewWindowRequest{id,
  initialPresentation, restoredFrameDescriptor, restoredSidebarWidth, tearOffPreviewFrameDescriptor}`;
  `InitialPresentation` = `createSession(name?, serverID?)` | `openDirectories([String])` | `showSession(sessionID)` |
  `showTornOffTab(sessionID, windowID)` | `restoreLastFocusedSession`.
- Restoration: `OpenWindowsStore` (`Workspace.openWindows`), `LastFocusedSessionStore`, `SessionOrderStore`.
- Startup cover/"LaunchReveal": a startup surface + optional indicator until first terminal frame
  (os_log "Initial workspace cover resolved in %lld ms", "First terminal surface appeared ..."); `LaunchReveal.Frame{time,
  reducesMotion}` drives a reveal animation; `RexSyncLaunchPrewarm` prewarms the last session.
- Empty/loading states (WorkspaceWindowView): "Opening Rex", "Creating Session…", "Preparing a new session for this window.",
  "Session Creation Failed" + Retry, "Loading Sessions on <host>", "Connecting to <host> and reading its sessions.",
  "Reconnecting to <host>" (`arrow.trianglehead.2.clockwise`), "Connection attempt N failed. Trying again automatically.",
  "Open Diagnostics…", "No Sessions" + "Create Session", "Rex Server Is Stopped/Exited/Failed/Unavailable/Restart Required",
  "Start the local Rex server to list and create sessions." + "Start Again", "Couldn’t Connect to the Rex Server".
  PaneView: "Session View Failed"/"Try Again", "Loading the window's blocks…", "Empty session" — "Open a new tab to start a
  terminal." + "New Tab" button with "Keyboard shortcut: …" (`NoTabsView`).
- Traffic lights: `TrafficLightPlacement.swift` calls private NSWindow API `setCustomTitlebarHeight:` and
  `setStandardWindowButtonGroupOffset:` to move the traffic lights into the tab bar / pane header. Panes reserve space
  (`PaneTrafficLightSpacer`, `PaneCell.reservesTrafficLightSpace`, `reservesBaseSidebarToggleInset`) and the pane title
  slides around them (`PaneTrafficLightTitleTransition`). Pictogram assets `InterfaceTrafficLights`, `...Legacy` (Sequoia).
- Window drag: `PaneHeaderWindowDragView` (`mouseDownCanMoveWindow`, `acceptsFirstMouse:`); double-click honours
  `AppleActionOnDoubleClick` (Minimize/zoom) [F string in FloatingNotice region].
- Window materials: `WindowMaterialBackdrop` (NSVisualEffectView material per style, see §3.9), `SolidWindowAppearance`,
  `ThemedWindowAppearance` (settings windows themed with the terminal theme background).
- Tab tear-off into a new window with a native "spawn" transition (§3.4). `WindowPlacement` cascades/places new windows,
  watches `didMove/didResize/didEndLiveResize/screenParametersDidChange/willClose`.
- `RexDockIconVisibilityController` + `RexMenuBar` (status item) per `appIconVisibility`.

### 3.2 Horizontal tab bar (`HorizontalTabBarView`, NSView) [F]
- Layout result `HorizontalTabBarLayout.Result{pickerFrame, commandPaletteButtonFrame, activityButtonFrame?,
  newTabButtonFrame, tabsLeadingEdge, tabWidth, tabFrames[], trackFrame?, scrollOffset}` → order is
  **[session picker] [tabs …] [activity] [command palette] [new tab]** (all three chrome buttons hideable via
  right-click "Customize View" → `hiddenChromeButtons`).
- All tabs share one `tabWidth` (equal-width tabs). When `fillsAvailableSpace` they expand to fill the bar; otherwise fixed
  width. Overflow → horizontal scrolling inside `TabScrollView` (custom `scrollWheel:`, `reflectScrolledClipView:`), with
  edge fades: `HorizontalOverflowMask` gradient layers named `tab-overflow-fade`, `fadesLeadingOverflow/
  fadesTrailingOverflow`. `revealsSelectedTab` auto-scrolls selected tab into view. Drag near edges autoscrolls via
  `scrollDuringDrag:` + `dragScrollDisplayLink`.
- Selection: a single sliding `TabSelectionSurfaceView` ("track") animated by CADisplayLink (`advanceGeometry:`), clipped by
  `TabSelectionClipView` (`sampleClip:`); hover = separate surface (`tab-hover`, `tab-hover-surface`). With a single tab the
  background is hidden (`singleTabFadeStartFrame`; "showing backgrounds only for two or more tabs").
- Dividers between tabs (`tab-divider` layer), animated with `TabAnimationSettings.divider`.
- Animations named in layers: `insert`, `return-scale`, `fadeIn`, `slide`; session handover animation when switching
  sessions (`SessionHandover{departing, arriving, selectedTabID}`, `sessionDeparture/sessionArrival/sessionLabel` timings).
- Context menu (tab): Rename Tab, Move Tab Left/Right (`arrow.left.square`/`arrow.right.square`), Close Tab; session:
  Rename Session…, Close Session, New Session, Add Remote Host…, Customize View.
- Drag & drop: reorder tabs (`dragOrder`, `dragLiftRevision`), drag out to tear off (`onTearOffTab(tabID, point, frame)`),
  drop a *pane* onto the tab bar to make a new tab (`PaneDropPlaceholderView`, `PaneDragNewTabLane`, spring-loaded tab
  switching while dragging a pane over a tab: `PaneDragTabSpringLoader`, `pane-drag-spring-loading-pulse`,
  `tab-spring-loading-tint`).
- Session picker on the left (`SessionPickerView`): shows session title (+ host subtitle/symbol for remote),
  attention badge when another session needs attention, slide title transition (`slide` mask), opens `SessionPopup`
  (filterable list "Filter or create...", items: sessions, New Session, New Session on Host, Reconnect host, Add Remote Host;
  right-click/alternate = open in new window). Tooltip "Change Session" with shortcut.

### 3.3 Vertical tabs / sidebar (`SidebarView`) [F]
- Rows per host → session → tab: `HostHeaderView` (host icon/symbol, connection progress spinner, warning button →
  `HostConnectionWarningPopover` with Retry, "New Session" button, collapse chevron), `SessionHeaderView` (inline rename,
  "+" new tab, collapse chevron with `chevron-rotation`), `TabItemView` rows, `NewSessionRowView` per host.
  Host headers only when more than one host (`showsHostHeaders`).
- Sticky/"tucked" headers while scrolling (`tuckedHeaderFrames`, `tuckedRowFrames`, `isTucked`), top/bottom scroll fade
  (`scrollMask` CAGradientLayer).
- Resize: `SidebarResizeHandle` (drag, cursor rects) → `Workspace.sidebarWidth`; toggle sidebar button (`sidebar.leading`/
  `sidebar.trailing`, "Hide Sidebar"/"Show Sidebar"), two-finger swipe to collapse/expand (`SidebarSwipeRecognizer`), animated
  fold that can shrink the window instead of panes (`preservesWindowWidthOnSidebarToggle`, `ChromeGeometry.CollapseTravel`,
  `windowFoldTargetFrame`, `PaneTravel` display-link animation).
- Footer (`SidebarFooterView`): expanding filter field (`line.3.horizontal.decrease.circle`, "Filter", "Clear Filter"),
  host filter popover ("All hosts", "Filter Hosts"), "Show idle processes" (moon.zzz) toggle, New Session, Add Remote Host.
- Drag: reorder tabs within/between sessions; reorder sessions with a *tilting* lifted card (`SessionDragTilt{angle,
  angularVelocity, pointerVelocity}`, `SessionDragLiftView`, `SessionDragBackdropView`).
- Context menus: New Tab in Session, New Local Session, New Session on Host, Edit Host, Remove Host, Move Session Up/Down,
  Rename/Close Session, Rename/Move/Close Tab, "Show Activity"/"Show All Tabs", "Show Buttons".
- Same `SidebarView` class is reused (with `isActivityPopover=true`) as the content of the floating Activity popup.

### 3.4 Tab item (`TabItemView`) — status, icons, peek, hints [F]
- Contents: `BlockGroupIconView` (stack of up to N pane icons; 3 vertical / 5 horizontal), `AnimatedTitleField` (title with
  directory part range `titleDirectoryRange` styled separately; `titleFadeMask` gradient when truncated), close button
  (`xmark`, hidden unless hover/selected; `HorizontalTabCloseLayout` keeps tab geometry frozen while the pointer stays in
  the bar after closing a tab — Safari-style), `TabStatusIndicatorView`, `TabShortcutHintView`, `TitleTickerView`
  (announcement ticker), `detailField` + `ageField` + `TabStateCapsuleView` (activity detail line in vertical tabs:
  message, "Working/Waiting/Failed" capsule, relative age), divider layer, spring-loading pulse layer.
- **Status indicator**: `TabStatusIndicatorView` = three dots (`dotLayers`) that travel while working (`dotsAreTraveling`,
  phase locked to clock so all tabs animate in sync, reduce-motion aware). `TabStatus.Kind` = `working(progress:Int?)` |
  `blocked(reason)` (permission / question / auth: "Waiting for permission / an answer / a password") | `error` |
  `finished`. Status badge artwork drawn in `StatusBadgeDrawing` (`status-badge-artwork`).
- **Announcements**: `TabAnnouncement{identity, icon}`; when a program finishes etc. the tab title is replaced briefly by a
  ticker with the program icon (`announcementTicker`, `announcementTurn` task).
- **Icon behaviour**: `iconColorMode` (always / active panes / active tabs / never), `iconTintMode` (off/accent/terminal),
  `bouncesTabIcons` (icon bounce on attention), focused pane icon emphasized (`focusedBlockID`), icon transitions via
  display link.
- **Hover card ("peek")**: `HoverCard{title, titleDirectoryRange, titleActivity, details[directory|message], panes[],
  hiddenPaneCount, tree: ProgramStatusTree, icon}`; `HoverCardView` lists panes (`HoverCardPaneButton`: icon, name,
  directory, activity message, progress pie `ProgressPieView`, working dots `WorkingStateView`, indentation guides for the
  process tree, "+N more"), clicking a pane focuses it (`onSelectPane`). Shown via `HoverCardTip` (SuperTip-style
  popover anchored to the tab). No screenshot thumbnails of terminals are used for hover; a **`PaneMinimap`** (tiles =
  pane rects, highlight rect animated) exists in RexShared [I: used in hover card / palette for layout preview].
- **Shortcut hints**: holding the modifier shows keycaps on tabs (`TabShortcutHintMonitor` reveals after a delay per
  window, `TabShortcutHintView` draws `SuperTip.ContentView.Piece` keycaps).
- **Tear-off**: dragging a tab out shows `TabTearOffPanel` with a ScreenCaptureKit snapshot of the tab content
  (`TabTearOffPreview.captureContent`, "The tab's window is unavailable for capture."), morphs (`morphFrame:`, `morphDuration`)
  into a window-shaped preview (`TabTearOffWindowPreviewView`, header strip `tearOffHeaderView`), then
  `TabTearOffWindowTransition` + `TabTearOffNativeEntrance` animate the real new window into place (3D transform on
  root layer); `TabTearOffWindowClose` animates closing; drop back onto a window re-attaches (`reattachmentFrame`).

### 3.5 Program activity (agent/process status) [F]
- Sources: OSC program-status from libghostty (`GHOSTTY_TERMINAL_OPT_PROGRAM_STATUS`, states idle/working/done/blocked/error,
  kinds permission/question/auth, progress %), ConEmu progress OSC 9;4, plus server hub reports
  (`ProgramActivity.HubReportSource`). Statuses in UI: `working`, `blocked`, `error`, `done` (+ `idle`).
- Per-status preferences (Settings ▸ Notifications ▸ Program Activity ▸ Working/Waiting for you/Errors/Finished): tab
  indicator, macOS notification (only when Rex is in background; click opens the tab), Dock badge count (blocked, failed,
  finished not yet seen), sound (`attention, warning, error, success, ready, loading, tap`).
  Descriptions: "Shown when a program is busy or reports progress / needs you to respond / reports that something went
  wrong / finishes a task".
- Seen-tracking: `SeenLedger` (`Workspace.programActivitySeen`) records receipts so finished/failed dots clear once viewed.
- Activity filter (`ActivityFilter{isOn, hidesSelection, shownTabIDs, sweptTabs, followsSelection}`): sidebar filter
  showing only tabs with activity ("No processes are reporting activity"), "Include idle processes in activity".
- Activity button in tab bar (`ActivityButton`, badge layer, `wantsAttention`) → floating `ActivityPopup` panel
  (draggable/detachable: `isDetached`, `isDraggingPopup`, morph animation `morph`/`morphFade`).
- Dock: `DockBadge`, dock menu "Activity" section; Alerts engine `Alerts.Pass{arrivals, inView, seen}` decides what to
  notify.
- Terminal notifications OSC 9 / OSC 777 → native notifications (`rex.terminal-notification.<id>`), program-activity
  notifications id prefix `rex.program-activity.`; `RexUserNotificationRouter` routes clicks by prefix.

### 3.6 Panes (SuperSplit) [F]
- `SuperSplitConfiguration{showsDividers, allowsDividerDragging, allowsPaneMovement, clipsContentOverflow,
  dropIndicatorCornerRadius, paneTransitionDuration?, layoutTransitionDuration?, paneMoveDuration?,
  focusIndicatorMotionDuration?, minimumPaneSize?, paneContentSizing(followsSurface|pinnedDuringMotion), liquidGlass,
  divider}`; `SuperSplitDividerConfiguration{layoutLength, interactionLength, lineThickness(.pixels(Int)|.points),
  color?, blendMode, outerLineInsets}`; `SuperSplitLiquidGlassConfiguration{isEnabled, style(regular|clear), tintColor?,
  cornerRadius, outerRimColor?, outerRimWidth, outerRimBlendMode, shadows[{color, opacity, radius, offset}]}`.
- Divider interaction view is a real accessibility slider (`accessibilityPerformIncrement/Decrement`, value description);
  "Swipe up or down to resize panes."; adjustment step `.fraction` or `.points`.
- Pane drag: drag by header to move (drop zones center/left/right/top/bottom with `SuperSplitPaneDropIndicatorNSView`),
  drop on tab bar → new tab, tear out → `SuperSplitPaneTearOutRequest`.
- Motion: `SuperSplitLayout.Presentation` with `MotionKind`, `StructuralGrowth` (new pane grows from the split edge),
  `VisibilityFade`, `PaneOverlayMotionState`.
- Pane header (SwiftUI `PaneCell`): icon + `PaneTitleLabel` (+ move icon when dragging), buttons `splitRight`
  (`rectangle.split.2x1` / custom `custom.rectangle.split.2x1.righthalf.filled`), `splitDown`
  (`rectangle.split.1x2`…bottomhalf.filled), `zoom`, `close`; header hideable (`showsPaneHeaders`); per-button hiding
  (`hiddenPaneButtons`). Header tinted with program background when `tintsPanesWithProgramBackground`.
- Zoom: `WindowLayoutModel._zoomedPaneID`, `unzoomedLayouts`, covered panes (`isCoveredByZoom`) — zoom is a server
  operation (`session.zoom_block`).
- Inactive pane fade: `PaneContentFade` environment `paneContentFadeOpacity`; `InactivePaneFadeMode` applies to surface
  (`styling`), terminal content (`text`), or both. Material JSON: pane `contentOpacity` 0.7 for inactive vs activePane 1.0
  (Modern dark comfortable).
- Find bar: `PaneFindBar` floating panel per pane ("Find in Scrollback", Find Previous/Next chevrons, xmark), nudged to avoid
  the selected match (`findBarRestingFrame`, `appliedFindBarNudge`); search via libghostty `terminal-search`.
- Terminal overlays: "Reconnecting… Content preserved.", "Sized by another client · <cols×rows>" ("Click to resize it to fit
  this window."), "Raised text contrast for a device in <mode> mode" notice, "Paste Unsafe Text?" alert, link confirmation.
- Focus follows mouse; autobalance; `PaneScrollbarSuppression`; terminal scrollbar hidden when needed.

### 3.7 Command palette [F]
- AppKit `CommandPalettePanel` (NSPanel, key, `flagsChanged:` to update shortcut hints), stacked pages
  (`CommandPalette.PageState` stack, `CommandPaletteOutcome.push/dismiss/stay`), custom-drawn list (`drawRect:`),
  inline completion, loading indicator after a delay, preview on highlight (`previewedItemID`, e.g. live theme preview),
  inline shortcut recorder footer ("Change Keybinding", "Press a shortcut for …").
- Item: `{title, subtitle, subtitlePrefix{icon,text}, shortcut, value, isCurrent, isEmphasized, needsAttention,
  fileIconPath, iconSystemName, tabIcons, keywords, completionText, alternate{hint, perform}, shortcutPage, presentsPage}`.
- Placeholders: "Search commands…", "Search commands, sessions, and tabs…"; sections include sessions and tabs
  (`FinderRowIDs.Subject.session/tab`), activity heading indicator; "No Results".
- Sub-pages: Change Session, Go to Directory… (folder browser), Insert Path, Move Pane to Tab…, Select Interface Style…,
  Select Terminal Font… (Monospaced Fonts / Other Fonts), Terminal Font Size, Cursor Style, Cursor Blink Interval, Option Key
  Behavior, Terminal Padding Color, Selection colors, Update Channel (Preview "Tagged builds for testers." / Bleeding Edge
  "Every commit that passes CI. Expect some instability."), Custom Themes (filter, import, delete), Host pages (add/switch/
  remove), Shortcuts ("Search actions…", "Choose a Key to Remove It", "Reset to Default"), Modes.
- Matching: `CommandPaletteMatch` with prepared haystacks + per-item keyword strings (examples quoted in §4).

### 3.8 Notices, tooltips, key hints [F]
- `RexNotice.Presentation{id, title, scrollingText?, description?, progressFraction?, indicator(symbol|determinateProgress|
  progress), tone(accent|success|standard|warning|error), tintsGlass, isDismissible, dismissShortcutHint?, activation?,
  actions[{id, role(standard|primary|destructive)}]}`; ids `updates`, `serverRestart`, `raisedTextContrast`, posted UUIDs.
- `FloatingNotice` (SwiftUI in `NoticeHostingView`) placed per `notificationPosition` (6 positions, picker is a window
  diagram), expandable message ("Show full message"/"Collapse message"), progress ring, title ticker, dismiss "xmark".
  Configuration struct has all layout constants (see §5).
- `SuperTip` — custom tooltip with label + keycaps (`SuperTip.Content{label, keys}`), placements below / belowLeading /
  trailing, interactive variant; `ShortcutToolTip` wraps chrome buttons.
- `PendingKeysIndicator` — which-key style panel: after the first key of a sequence (tmux-style prefix) shows a pill with
  pressed keycaps, then expands into a grid of next keys (`Row{keyLabels, title, kind(action|sequence|mode), leavesMode}`),
  mode badge/bar for active modes, escape hint, "Show Keys", "+N more". Toggle `showsKeySequenceHints`.

### 3.9 Interface styles, materials, glass [F]
- Settings ▸ Interface: Color scheme (Auto/Light/Dark live material previews), Interface style cards **Glass** / **Classic**
  + toggle **Tint with theme** ("Apply the selected theme's colors to interface surfaces"), "Use glass for panes".
  Command palette: "Change Interface Style" (keywords "interface style surface material glass classic system modern"),
  "interface tint theme colors … themed blended".
  Mapping [I, consistent with names + JSON]: Glass+no tint = `modern`, Classic+no tint = `system`,
  Classic+tint = `useTheme`, Glass+tint = `blendTheme`.
- Each style loads `MaterialStyles-<Modern|System|UseTheme|BlendTheme>.json` over code defaults
  (`SurfaceStyleDefaults.swift`), plus `MaterialStyles-Sequoia.json` overrides when Liquid Glass is unavailable
  (`SurfaceStyleLibrary.usesSequoiaOverrides`; macOS 15). Document schema: `{version, palette(macOS|theme),
  light|dark: {windowInnerShadow, active|inactive: {comfortable|compact: SurfaceProfile}}}`.
- `SurfaceProfile` keys: `window, tabContainer, tabSelection, tabHover, pane, activePane, paneSheet, horizontalSheet,
  verticalSheet, sheetInsets, drawsCompactBoundaryLines, paneDividers, sheetDivider, panesWithoutGlass`.
- `SurfaceStyle{shape{cornerRadius, cornerCurve(continuous|circular), clipsContent, contentInsets}, contentOpacity,
  shadows[], innerShadow, backdrop, glass{isEnabled, geometry, style(regular|clear), windowMaterial, usesTint, tint},
  fill, fill2, strokes[{width, alignment(inside|center|outside), blendMode, level(belowContent|aboveContent)}],
  window{alphaValue}}`; colors `{role, color{kind fixed|adaptive, light, dark}}` with roles like `canvas`,
  `theme:surface`. Radius modes `concentric | matchSurface | fixed`.
- Rendering: `SurfaceStackView` composes planes (shadow, backdrop, glass/NSVisualEffectView, fill, fill2, strokes,
  inner shadow, content clip, chrome) — used for window, tab container, tab selection/hover, panes, popovers.
  `SuperGlassEffectView` wraps `NSGlassEffectView` (style regular/clear, tint, cornerRadius). The class names `NSGlassEffectView` / `NSGlassEffectContainerView` occur only as strings, so the app looks them up at runtime and falls back to `NSVisualEffectView` on macOS 15. SwiftUI surfaces use `.glassEffect(Glass.regular.tint(_:), in:)`; SuperSplit has its own `SuperSplitGlassEffectContainerView` / `SuperSplitPaneGlassContentView`.
- Compact density draws panes as one "sheet" with divider lines (`SheetDividerView`, primary/secondary divider layers)
  instead of separate floating cards; comfortable draws separate rounded panes with gaps.
- Example Modern/dark/active/comfortable values (JSON): window radius 12, glass `hudWindow` tint canvas α0.5, backdrop
  overlay α0.6; tabContainer radius 40 fill α0.05; tabSelection radius 16.5 glass matchSurface; tabHover fill overlay α0.05
  + backdrop α0.13, no glass; pane radius 10, glass tint canvas α0.3, fill α0.15, backdrop overlay canvas α0.48,
  contentOpacity 0.7 (active 1.0); panesWithoutGlass: stroke1 0.7pt plusLighter α0.5×0.2, stroke2 1pt outside belowContent.

### 3.10 Keyboard and actions [F]
- Server-defined keymap (Lua `init.lua`) + app-recorded overrides (`ShortcutStore`, `client-keymap.json`), modes
  (exclusive or pass-through), key sequences, `KeyEventMonitor` (local NSEvent monitor: route → resolve → translate →
  replay), `MenuShortcutSynchronizer` mirrors bindings onto NSMenu items, `ShortcutRecorder` refusals (e.g. "Hold ⌘, ⌃, or
  ⌥ with the key. Shift on its own types a character.", reserved chords cmd+tab, cmd+space, cmd+q, cmd+h, alt+cmd+h, cmd+m,
  cmd+,). "Copy Shortcuts as Lua" exports overrides.
- Built-in client actions (ids + titles, from `ServerActionProvider`/RexAction registry): see §4.

### 3.11 Other surfaces
- Settings window (custom `SettingsShellController` with toolbar back/forward, sidebar groups Server / Customize / Configure /
  Developer; pages server, interface, themes, terminal, shortcuts, notifications, integrations, remoteHosts, developer;
  full-text settings search with spotlight highlight of the matched row `SettingsSearchSpotlight`). Anchor ids:
  `interface.{appearance,window,tabs,panes,app-icon,launch}`, `terminal.{typography,colors,cursor,keyboard,padding,selection,
  links,path-browser,titles,shell}`, `themes.{light,dark,import}`, `notifications.{overview,activity,macos}`,
  `server.{status,client-info,tailscale,tailscale-address,version,stop}`, `integrations.{agents,agent-behavior}`,
  `remoteHosts.hosts`, `developer.{mode,version,installation,local-api,origins}`, `shortcuts.{list,json}`.
- Theme customizer (OKLCH chroma plane color picker, P3 gamut, swap swatches by drag, extended 256 palette regenerate),
  Ghostty theme/config migration ("Migrate theme from Ghostty config"), iTerm import.
- Remote hosts & Tailscale serving (pairing QR, "Rex does not provide transport authentication. Use a trusted tunnel such as
  Tailscale."), menu bar status item (icons MenuBarIconOff/On/Attention/Error; "Rex server running/stopped", "Rex needs
  attention", Copy local Rex endpoint, Copy Remote Address, Pair Device, Check for Updates, Settings, Quit).
- Agent integrations: installs Rex skill + session hook into Claude Code, Codex, OpenCode, Pi (`rex skill setup`),
  "Let agents name sessions" (`--session-naming=false`).
- Diagnostics window (API console with call/event transcripts, GPU usage chart (Charts) incl. WindowServer share, sync
  inspector, debug report copy).
- Updates: Sparkle 2 with custom `UserDriver` (in-app notices instead of Sparkle UI: "Rex App Update Available", "Restart
  to Update Rex…", "Your terminal tabs won't be lost"), channels `preview` / `snapshot` (Bleeding Edge), feed
  `https://blob.superlogical.com/public/rex-app/preview/appcast.xml`, `SURequireSignedFeed`.
- URL scheme `rex://`: `RexURLRouter.Destination` = `settings` | `diagnostics`; settings sub-paths are section names
  (`rex://settings/server`, `…/interface`, `…/terminal`, `…/remoteHosts`, `…/notifications`, `…/integrations`,
  `…/developer`, `…/appearance`); `start` / `stop` control the local server ("Starting/Stopping the server from a Rex URL",
  "Suppressed automatic server start after a pre-launch stop request"). Bare/unknown URLs are logged and ignored.
- Doom-melt transition (`DoomMeltTransition`, `doomMelt` animation, env `REX_SLOW_ANIMATIONS` slows animations) used when
  the server restarts / content is replaced (`prepareForServerChange(in:backgroundColor:timeScale:)`; "Melt preview failed").

## 5. Recovered constants (from disassembly/decompilation) [F unless marked]

Density enum byte: comfortable=0, compact=1.

### 5.1 Tab bar / tabs
| What  |  Value |
|---|---|
| Horizontal tab bar height (`intrinsicContentSize`) | **46 pt comfortable, 40 pt compact** |
| Tab width (not filling) | `w = (avail − (n−1)·1) / n`, capped at **220 pt**, floor **64 pt**; with "Fill available space" the 220 cap is removed. Gap between tabs = 1 pt (divider). |
| Tab hover/selection corner radius | `min(height/2, 16.5)`; menu-highlight variant 8 pt |
| Tab divider | 1 pt wide, height = tabHeight − 18, centred |
| Tab close button | 22×22 pt, x = width − trailingInset − 22 + 7; hidden when tab narrower than **52 pt** |
| Tab status dots (`TabStatusIndicatorView`) | container 14×14 pt centred; **3 dots of 3.5×3.5 pt, cornerRadius 1.75, pitch 5.5 pt** (gap 2 pt), first dot x = midX − 7.25 |
| Tab status dot animation | `CAKeyframeAnimation` "opacity" values **[0.3, 0.85, 0.3, 0.3]** at keyTimes [0, 0.25, 0.5, 1], easeInEaseOut, **duration 1.2 s**, repeat ∞, dot *i* begins at **i × 0.2 s**; beginTime snapped to multiples of 1.2 s of `CACurrentMediaTime` when `locksPhaseToClock` (all tabs in phase); show/hide fade 0.18 s; `preferredFrameRateRange` **min 8 / max 15 / preferred 15 fps** (battery) |
| Session picker width | icon-only **36 pt**; else chrome **44** (comfortable) / **42** (compact) + min(max(titleW, subtitleW), 224 − chrome) → max **224 pt** |
| Session picker slot in bar | min 36 pt (or measured + 4); **84 pt** reserved for traffic lights when not full screen |
| Hover card width | max **280 pt** (`fminnm(natural, 280)`) |
| Selection / hover / divider animation timings (`TabAnimationSettings` default, identical in HorizontalTabBarView, SidebarView, SessionHeaderView, TabItemView) | geometry **0.28 s spring**; insertion **0.22 s production**; tabReturn **0.42 s easeInOut**; returnLayout **0.40 s spring**; sessionDeparture **0.12 s**; sessionArrival **0.20 s**; sessionLabel **0.26 s**; hover **0.14 s**; divider **0.20 s**; titleClipping **0.25 s** (all others production) |
| "production" easing | `CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)` |
| "spring" easing | `CASpringAnimation` mass 1, stiffness **520**, damping **46**, initialVelocity 0 (critical damping 2√520 = 45.607 kept as a global) |
| Easing enum raw order | production 0, spring 1, linear 2, easeIn 3, easeOut 4, easeInOut 5 |

### 5.2 Sidebar / settings
| What  |  Value |
|---|---|
| Sidebar width | default **240**, clamped to **[227, 480]**, rounded |
| Sidebar tab row height | **30 pt** single-line, **44 pt** with activity detail line; inter-row spacing 6 or 10 |
| Window minimum width | **480 pt** (horizontal tabs); **720 pt** with vertical sidebar shown (720 − sidebarWidth when collapsed, floor 480) |
| Sidebar collapse/expand animation | **0.3 s** (pane travel display link; window fold when preserving width) |
| Sidebar scroll edge fade | gradient stop = min(18 / height, 0.45) → **18 pt** fade at top and bottom |
| Session drag tilt | damped spring integrated at 240 Hz substeps: stiffness **260**, damping **18**; pointer velocity low-pass factor min(dt·18, 1) |
| Traffic lights | KVC on the theme frame: `customTitlebarHeight` = bar height (−1 in full screen to reset), window `standardWindowButtonGroupOffset` |
| Terminal font size | default **12 pt**, clamp **[8, 64]** |
| Command palette list height [I: anchored in palette presenter] | clamp **[84, 460]** pt, available = window height − 76 − 40 − 38 |

### 5.3 Pane fade (material JSON, contentOpacity) — Modern/System/UseTheme share these
| Window state | inactive pane | active pane |
|---|---|---|
| active window | 0.7 | 1.0 |
| inactive window (dark) | 0.5 | 0.8 |
| inactive window (light) | 0.5 (compact light 0.6) | 0.85 |
Compact pane dividers: active dark 1 pt α0.7 plusLighter (Modern) / α0.8 automatic (System) / α0.08 plusLighter (UseTheme);
inactive 0.5 pt α0.55/0.5. Scope `betweenPanes` (Modern dark) or `includingTopAndBottom`.
Radii: window 12, pane 10, tab container 40 (capsule), tab selection 16.5 (all styles).

### 5.4 Delays (Swift `Duration` literals, attoseconds immediates) [F value, file attribution approximate]
| Delay  |  Value |
|---|---|
| Hold modifier → keycap shortcut hints appear on tabs | **700 ms** |
| Hover over tab → hover card (peek) | **250 ms** |
| Dragging a pane over a tab → spring-load (switch to) that tab | **650 ms** |
| First key of a sequence → pending-keys (which-key) panel | **300 ms** |
| Divider resize → send to server (debounce) | **120 ms** |
| Palette theme/channel preview while highlighting | **750 ms** |
| Palette helpers (loading indicator / shortcut hint refresh) [I] | 150 ms / 75 ms |
| Insert Path loading reveal | 150 ms |
| Command palette selector | 25 ms |

### 5.5 Animation curves seen at call sites [F values; owner file approximate]
- SwiftUI `.spring(response: 0.3, dampingFraction: 0.8)` — shortcut settings rows, shortcut recorder, `PaneMinimap` highlight.
- `.spring(response: 0.3, dampingFraction: 1.0)` — pending-keys panel expand; `.spring(1.0, 1.0)` floating notice;
  `.spring(0.28, 1.0)` fallback-font list.
- Pending keys: `easeOut(0.2)` + `delay(0.08)` insertion, `easeOut(0.1)` removal.
- Pane find bar: `easeOut(0.08)`. Focus ring: `easeOut(0.16)` then `linear(0.05)`. Pane split view transitions:
  `easeOut` 0.16 / 0.2 / 0.07 / 0.08. Settings sections: `easeInOut(0.24)`. TransientReveal: `easeOut(0.15)`.
- Core Animation: sidebar uses the same spring (mass 1, stiffness 520, damping 46) for row moves; 0.28 s / 0.18 s / 0.2 s
  basic animations; session/host header chevron rotation **0.18 s**; sidebar resize **0.25 s**; activity popup / session
  popup fade 0.1 in / 0.12 out with a damping-22 spring for the popup morph; SuperTip surface fade **0.13 s**; tab shortcut
  hint fade 0.13 in / 0.1 out; status-dot show/hide 0.18 s; sidebar footer filter expand 0.3 s / 0.16 s / 0.12 s.

## 6. Ideas for Oriel (what to copy, how)

Written before the UI polish scope was set: `plan/ui-polish.md` decides what Oriel builds (no compact density, no themes, no tear-off).

1. **Tab bar geometry**: equal-width tabs, `w = (avail − (n−1)) / n`, max 220 pt, min 64 pt, 1 pt divider gap, horizontal
   scroll with gradient edge fades when below min; optional "fill available space" removes the max. Bar height 46/40 pt
   by density. Hide close "×" below 52 pt width; keep tab frames frozen while the pointer stays in the bar after a close
   (Safari behaviour). Selection = one sliding capsule (radius min(h/2, 16.5)) animated with one spring
   (stiffness 520, damping 46, mass 1 ≈ SwiftUI `.spring(response: ~0.276, dampingFraction: ~1.0)`), not per-tab fills.
   Hide the selection background when only one tab.
2. **Status dots**: three 3.5 pt dots, 2 pt gap, in a 14×14 box, travelling animation phase-locked to wall clock so every
   tab animates in sync; separate glyphs for blocked (permission/question/auth), error, finished; clear finished/error
   when the tab is seen (a "seen ledger" persisted in defaults). herdr's agent status maps to working/blocked/done.
3. **Hover peek**: 250 ms hover → card with tab title (directory part dimmed), per-pane rows (icon, name, cwd, status
   message, progress pie), click row to focus that pane. Cheap (no thumbnails) and more useful than screenshots.
4. **Shortcut keycaps on tabs** after holding ⌘ for 700 ms (`TabShortcutHintMonitor`), fade 0.13 s in / 0.1 s out.
5. **Which-key panel** (PendingKeysIndicator) after 300 ms in a prefix sequence; mode badge while in a mode.
6. **Pane fade**: implement as content opacity per pane: active window → inactive panes 0.7, active 1.0; inactive window →
   0.5 / 0.8 (dark) or 0.5 / 0.85 (light). User choice none / surface / content / both, plus "standard inactive window
   styles" toggle.
7. **Density**: comfortable = separate rounded cards (radius 10) with gaps; compact = one sheet with 1 pt divider lines
   (0.5 pt in inactive windows, opacity 0.7–0.8, plusLighter in dark / plusDarker in light).
8. **Materials as data**: copy the `SurfaceStyle` JSON idea (shape/backdrop/glass/fill/strokes/shadows per
   window/tabContainer/tabSelection/tabHover/pane/activePane × light/dark × active/inactive × density). Lets Oriel tune
   looks without code; ship a Sequoia (no Liquid Glass) override layer. Use NSGlassEffectView via
   `NSClassFromString` so the app still runs on macOS 15.
9. **Traffic lights inside the tab bar** via `setCustomTitlebarHeight:` / `setStandardWindowButtonGroupOffset:`
   (private, risky) — or reserve a leading spacer in the custom bar as Rex does when the sidebar is hidden.
10. **Sidebar**: width 240 default, clamp 227–480; rows 30 pt (44 pt with detail line); sticky session headers; collapse
    chevron 0.18 s; two-finger swipe to toggle; option to fold the window instead of squeezing panes.
11. **Activity filter + popup**: one toggle shows only tabs with agent activity; also a floating detachable popup;
    Dock badge = count of unseen blocked/failed/finished; per-status notification/sound/badge matrix.
12. **Tear-off**: drag tab out → snapshot card morphs into a window-shaped preview → real window animates in. Also drop a
    pane on the tab bar → new tab; dwell 650 ms over a tab while dragging a pane → switch to it.
13. **Command palette as the settings surface**: every setting has an "Enable/Disable X" palette entry with rich keyword
    strings (quoted in §3.7 / cs strings); sub-pages for pickers; live preview on highlight after 750 ms.
14. **Notices**: one floating notice component (tone, progress ring, ticker title, expandable message, actions) placed at
    a user-chosen corner (6 positions) — use for update/restart/copy confirmations instead of alerts.
15. **Divider accessibility**: expose dividers as AX sliders with increment/decrement (Rex's SuperSplit does).
16. **Rex backend**: client action ids (`client.*`, `pane.*`, `session.*`) and the API method list (`session.new_split`,
    `session.zoom_block`, `session.resize_pane`, `session.swap_blocks`, `session.move_block`, `block.event`, …) are in
    `RexAPI` types .

