import HerdrKit
import SwiftUI

/// The selected workspace's tabs in the title row (D42): one width on a track, one marker that follows the
/// strip's scroll, dividers, hover and close. Tabs never shrink: the row scrolls sideways when they do not fit.
struct TabBar: View {
    /// Every tab's: the user wants tabs that keep their width and a row that scrolls.
    static let width: CGFloat = 220
    /// The track's height; Rex's capsules sit 2 pt inside it, 30 pt tall and fully round.
    static let height: CGFloat = 34
    static let inset: CGFloat = 2
    static let radius: CGFloat = 17

    let workspace: HostStore.Workspace
    let page: Page
    /// A pane dragged over the `+`; with one over the track's end, a ghost capsule at the end, when it fits.
    let plus: Bool
    /// The overview is open: the pill sits on the selected tab (`marker`).
    let overview: Bool
    @State private var end = false
    /// A drag over the track: the capsule a pane is over, or the place a dragged tab goes.
    @State private var over: Int?
    @State private var spring: Task<Void, Never>?
    /// The capsule that just spring-loaded, scaled up for a moment.
    @State private var pulsing: String?
    /// The row's free space.
    @State private var space: CGFloat = 0
    @State private var hovered: String?
    /// The tab a click or a spring-load selects: it is under the pointer, so the row does not scroll to it.
    @State private var clicked: String?
    /// The row's visible part, in the tabs' space: its edges fade where tabs are out of view. No fade until the
    /// row has laid out.
    @State private var visible: ClosedRange<CGFloat> = 0 ... .infinity
    /// ⌘ held for 0.7 s: keycaps on the first nine tabs.
    @State private var hints = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.look) private var look

    var body: some View {
        let tabs = workspace.tabs, count = CGFloat(tabs.count), width = Self.width
        let content = count * width + count - 1
        let hidden = (leading: visible.lowerBound > 0.5, trailing: visible.upperBound < content - 0.5)
        // Pages floor(x/w) through ceil((x+w)/w) − 1, that is floor(page)...ceil(page). With no strip under the
        // overview, the selected tab's.
        let place = overview ? Double(page.selectedIndex(in: workspace)) : page.stripPage
        let lit = Int(place.rounded(.down)) ... Int(place.rounded(.up))
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        // One view per tab, so a scroll to its id shows the tab, not the divider before it.
                        HStack(spacing: 0) {
                            if index > 0 {
                                // Hidden next to the marker, the selected tab and the pointer.
                                let quiet = lit.contains(index) || lit.contains(index - 1)
                                    || [tab.id, tabs[index - 1].id]
                                    .contains { $0 == hovered || $0 == page.selectedTabIDs[workspace.id] }
                                Rectangle().fill(look.divider).frame(width: 1, height: Self.height - 16)
                                    .opacity(quiet ? 0 : 1)
                                    .animation(.easeInOut(duration: 0.2), value: quiet)
                            }
                            TabButton(tab: tab, workspace: workspace, page: page, lit: lit.contains(index),
                                      hovering: hovered == tab.id, keycap: hints && index < 9 ? index + 1 : nil,
                                      clicked: { clicked = tab.id })
                                .onHover { hovered = $0 ? tab.id : hovered == tab.id ? nil : hovered }
                                .overlay {
                                    if page.dragging?.paneID != nil, over == index {
                                        DropIndicator(radius: Self.radius)
                                    }
                                }
                                .scaleEffect(pulsing == tab.id ? 1.04 : 1)
                                .opacity(page.dragging == .tab(tab.id) ? 0.4 : 1)
                                .offset(x: shift(index))
                        }
                    }
                }
                // A container of its own: without it, a row of one tab that grew to two kept the first capsule's
                // accessibility element with the whole row's frame (a click there landed between the capsules).
                .accessibilityElement(children: .contain)
                // In the content's space: the capsule under the pointer, wherever the track scrolled.
                .onDrop(of: [.orielDrag], delegate: TrackDrop(tabs: tabs, page: page, slot: width + 1,
                                                              over: $over, spring: $spring, springLoad: springLoad))
                .clearsDrop(page) {
                    spring?.cancel() // a late update after the drop may have started one
                    over = nil
                    end = false
                }
                .background {
                    ZStack(alignment: .leading) {
                        Capsule().fill(look.track).opacity(tabs.count > 1 ? 1 : 0)
                        marker(place, count: tabs.count)
                    }
                }
                // Room for the Classic pill's shadow (radius 3.5, y 1.5): the scroll view clips.
                .padding(.vertical, 5)
            }
            .scrollIndicators(.never)
            // No rubber band while every tab fits: it cut the end tab off at the edge.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onScrollGeometryChange(for: ClosedRange<CGFloat>.self) { geometry in
                geometry.contentOffset.x ... geometry.contentOffset.x + geometry.containerSize.width
            } action: {
                visible = $1
            }
            .fadeEdges(.horizontal, start: hidden.leading ? 24 : 0, end: hidden.trailing ? 24 : 0)
            .frame(width: max(min(content, space), 0))
            // minWidth 0: the row's free space, not the tabs' width; else the bar never shrinks (a workspace
            // button that appears pushed ⌘ and + out of the window).
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            // The track's empty end, after the tabs (not behind them: a `.forbidden` over the pane's own capsule
            // would fall through to it): a new tab in the workspace, shown as a ghost capsule.
            .overlay(alignment: .leading) {
                // It takes the clicks of the row's empty space, so it moves the window as that space does.
                Color.clear.contentShape(.rect).gesture(WindowDragGesture())
                    .overlay(alignment: .leading) {
                        if end || plus, page.dragging != nil, content + 1 + width <= space {
                            DropIndicator(radius: Self.radius).frame(width: width, height: Self.height)
                                .padding(.leading, 1)
                        }
                    }
                    .onDrop(of: [.orielDrag], delegate: PaneDrop(page: page,
                                                                 target: .move(.newTab(workspaceID: workspace.id)),
                                                                 over: $end))
                    .padding(.leading, min(content, space))
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { space = $0 }
            // Into view, without motion, when keys, the palette or a new tab select it; not after a click: a scroll
            // then moved the tab away from the pointer.
            .onChange(of: page.selectedTabIDs[workspace.id], initial: true) { _, new in
                if let new, new != clicked {
                    withTransaction(\.animation, nil) { proxy.scrollTo(new) }
                    // A new tab's capsule lays out in this same update, and a scroll to it can miss (Strip): again
                    // once it has.
                    Task { proxy.scrollTo(new) }
                }
                clicked = nil
            }
        }
        .frame(height: Self.height + 10)
        .testValue("tabs.fades", "Tab Fades", [hidden.leading ? "leading" : nil, hidden.trailing ? "trailing" : nil]
            .compactMap(\.self).joined(separator: ", "))
        .keycapHints(.command, shown: $hints)
        .onDisappear { spring?.cancel() }
    }

    /// A tab dragged along the track: it and the tabs it passes trade places as it goes (the others slide apart).
    private func shift(_ index: Int) -> CGFloat {
        guard case let .tab(id) = page.dragging, let slot = over,
              let from = workspace.tabs.firstIndex(where: { $0.id == id }) else { return 0 }
        let place = slot > from ? slot - 1 : slot
        return (Self.width + 1) * CGFloat(index == from ? place - from
            : from < index && index <= place ? -1 : place <= index && index < from ? 1 : 0)
    }

    /// Holding a pane over a capsule selects its tab, which pulses once.
    private func springLoad(_ tabID: String) {
        clicked = tabID
        page.select(workspace, tab: tabID)
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.1)) { pulsing = tabID }
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.1)) { pulsing = nil }
        }
    }

    /// The look's pill on the page in view, between two tabs while the strip is between their pages: it slides
    /// with a swipe or a wheel turn and jumps on any other switch, as the strip does. Under the overview, on the
    /// selected tab (the strip's place was the tab selected before), so it fades in there with the title row; a
    /// fade of its own came after the zoom.
    private func marker(_ place: Double, count: Int) -> some View {
        let place = min(max(place, 0), Double(max(count - 1, 0))), selected = page.selectedIndex(in: workspace)
        let rest = !overview && place == place.rounded()
        let astray = rest && Int(place) != selected ? "pill \(place) \(selected)" : ""
        return Pill(shape: RoundedRectangle(cornerRadius: Self.radius - Self.inset, style: .continuous))
            .frame(width: Self.width, height: Self.height - 2 * Self.inset)
            .modifier(Slide(drawn: place, place: place))
            // Not in another change's animation: the title row's fade after the overview slid it there.
            .animation(nil, value: place)
            .allowsHitTesting(false)
            // e2e (`-recordLatency YES`): "pill <place> <selected>" when it shows at rest on another tab.
            .onChange(of: astray) {
                if !$1.isEmpty {
                    Latency.shared.note($1)
                }
            }
    }
}

/// The pill's offset, drawn at each frame. e2e (`-recordLatency YES`): "pill slides <drawn> <place>" at a frame drawn
/// short of its place: it follows the strip frame by frame and never animates (an animation of the same
/// update, the title row's fade after the overview, slid it from the tab selected before).
private struct Slide: ViewModifier, Animatable {
    var drawn: Double
    let place: Double

    var animatableData: Double {
        get { drawn }
        set { drawn = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: drawn * (TabBar.width + 1))
            .onChange(of: drawn) {
                if Latency.isOn, $1 != place {
                    Latency.shared.note("pill slides \(String(format: "%.2f", $1)) \(place)")
                }
            }
    }
}

extension Page {
    /// The workspace's selected tab's index, 0 when none.
    func selectedIndex(in workspace: HostStore.Workspace) -> Int {
        workspace.tabs.firstIndex { $0.id == selectedTabIDs[workspace.id] } ?? 0
    }
}
