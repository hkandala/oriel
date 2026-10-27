# Phase 31: The user's seventh round of feedback

Goal: selection stays in view, gestures (three fingers, quicker and smoother paging), float requests that
work from remote machines, keys that reach the right window, overview session paging, Return in close
dialogs, and a CI that is fast and never flaky.

## Items

- **Lane S (1, 2).** 1: the sidebar and the Agents view scroll to the selected row. 2: after zooming into a
  middle tab from the overview, the tab bar's pill sat between two tabs.
- **Lane G (3–6).** 3: remove ⌥ + swipe. 4: three fingers up go to the workspace above. 5: faster two-finger
  paging between tabs and between sessions in the overview, following the fingers. 6: in the Agents view a
  vertical three-finger swipe steps the agent rows.
- **Lane F (7).** pi-herd's float request travels through herdr (metadata tokens), so it works for agents on
  remote machines; Oriel marks the panes it shows instead of an ack.
- **Lane M (11, 12).** 11: the quicker paging looked cut. 12: the pill jumped after the overview; it should
  fade in on the selected tab.
- **Lane K (13).** ⌃⇥ sometimes stepped panes, and with several windows a key acted on another window.
- **Lane O (14, 15).** 14: swiping between sessions in the overview dropped frames. 15: one fade for the
  sidebar, tab bar and pill after the overview.
- **Integration (8–10).** 8: Return confirms every close dialog. 9: CI back to about 7–8 minutes. 10: no
  flaky tests; two full runs in a row green without a rerun.

## Findings

### Lane G (items 3–6)

- **Cause, item 5.** The strip and the overview used SwiftUI's paging, which ignores the fingers' speed (a
  140 pt flick slid back) and snaps in about 0.55 s.
- **Fix.** They take the gesture as the sidebar's pages do (`Paging`): one-to-one moves, then a slide from the
  lift to the page it lands on (the next one that way, the nearest under 100 pt/s). `.paging` is gone: with it
  the first `scrollTo(x:)` snapped to the next page. Landing in about 250 ms instead of 550.
- **Decisions.** `AgentsList.groups` is the one source of the list order, for the view and for the
  three-finger steps; folded rows and floated panes are skipped.

### Lane S (items 1, 2)

- **Cause, item 2.** On a new strip's first layout, `containerRelativeFrame` sized the pages at the window's
  width; `onScrollGeometryChange` then delivered merged, out-of-order offsets, and the last was wrong.
- **Fix.** The pages take a `GeometryReader`'s size, so the first layout is right. The lists scroll with
  `scrollTo(id:)` and no anchor when the selection changes, without motion.

### Lane F (item 7)

- **Decisions** (spiked on herdr 0.9.5). Oriel reports `oriel-shown` on every pane in view (30 s ttl,
  refreshed every 10 s, cleared on leave and at quit). pi-herd reads its own pane: with the mark it reports
  `oriel-float` and a nonce, else it opens herdr's popup at once. Token names allow no dots; 16 per report,
  32 per pane, 80-character values. An ack was built first and dropped: it slowed herdr's popup without Oriel.

### Lane M (items 11, 12)

- **Cause, item 11.** `withAnimation(completionCriteria: .logicallyComplete)` completes at once for a scroll,
  so the landing (streams, chrome) ran in the slide's first frame and held it; and a 0.2 s spring from a slow
  lift moved most of a page in four frames.
- **Fix.** `Paging.slide` starts at the fingers' speed and eases out within 0.28 s; the landing runs once the
  pages are within 1 pt of the page.
- **Cause, item 12.** Under the overview there is no strip, so the pill stayed on the old selection's offset.
  No pill while the overview is open; it fades in on the selected tab.

### Lane K (item 13)

- **Cause.** A second key (⌃⇥) whose first's menu item was disabled went on to AppKit, which stepped the key
  view loop; menu actions are closures of the focused value's `CommandList`, which can be another window's.
- **Fix.** A matched second key in an Oriel window is always taken; every keyed menu item runs the key window's
  command, made when the key is pressed (`CommandList.keyWindow`).

### Lane O (items 14, 15)

- **Cause, item 14.** Every finger move remade every tile in view (closures never compare equal); an
  `allowsHitTesting` change at the swipe's start re-ran all tile bodies; hover hit tests ran each frame; the
  next session's page was built in the swipe's first frame; the hidden sidebar slid its pages after the
  landing.
- **Fix.** Equatable pages and tiles, a clear overlay instead of `allowsHitTesting`, neighbor pages built
  ahead, no live changes during a slide. Slide frames over 12 ms went from about 33 to 5 of 250.
- **Fix, item 15.** The pill has no fade of its own; the chrome fades in 0.12 s from the zoom's start.

### Integration (items 8–10)

- **Cause, item 8.** macOS gives a `confirmationDialog`'s destructive button no Return. Close dialogs are
  `.alert`s with `.defaultAction` and `.cancel`.
- **Fix, item 9.** Five jobs, split by measured test time; stress, cost, frame-record and look tests on demand;
  swipe and drag helpers compiled once. A full run is 9–12 minutes; 7–8 needs about 8 runners or 1500 s of
  tests ([ci.md](../ci.md)).
- **Fix, item 10.** Every flake fixed at its cause: tests that clicked before the app drew (capsules, cards,
  menus), a double click SwiftUI's `TapGesture` missed while busy (now AppKit's clickCount), a teardown that
  hovered a closing window, Finder drags replaced by the app's own drag source, a busy app running hover late
  (decide from the pointer's location), the relay closing stdin before its kill, and the quick-split bug
  (A | C | B | D) from reading the keyboard pane twice. Two full runs in a row green on the first try.
