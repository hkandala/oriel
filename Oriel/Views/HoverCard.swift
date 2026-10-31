import HerdrKit
import SwiftUI

/// Where a hover panel sits: its `panel` point on the trigger's `trigger` point, moved by `offset`.
struct PanelPlace {
    let trigger: UnitPoint
    let panel: UnitPoint
    let offset: CGSize

    /// Under the Agents button, the trailing edges lined up.
    static let underTrailing = PanelPlace(trigger: .bottomTrailing, panel: .topTrailing,
                                          offset: CGSize(width: 0, height: 4))
    /// Centered under a tab capsule, 6 pt below the title row.
    static let under = PanelPlace(trigger: .bottom, panel: .top,
                                  offset: CGSize(width: 0, height: (TitleBar.height - TabBar.height) / 2 + 6))
    /// Right of an Agents view row, 6 pt past the sidebar's edge (over the first card): the rows' inset and the
    /// 8 pt handle lie between.
    static let beside = PanelPlace(trigger: .topTrailing, panel: .topLeading,
                                   offset: CGSize(width: Sidebar.rowInsets.trailing + gap + 6, height: 0))
}

extension View {
    /// A panel that opens by this view after the pointer rests on it 0.25 s, stays while the pointer moves into
    /// it (0.15 s grace), and closes when the pointer leaves both, on a click or a scroll outside it, or with Esc.
    /// Not while a mouse button is down (a drag), nor while `enabled` is false (nothing to show). In the window,
    /// not a `.popover`: a popover is a window that takes the keyboard when it shows, and a resting pointer must
    /// not take keys from the terminal. `action` names an accessibility action that opens it.
    func hoverPanel(place: PanelPlace, action: String? = nil, enabled: Bool = true,
                    @ViewBuilder _ panel: @escaping (_ close: @escaping () -> Void) -> some View) -> some View
    {
        modifier(HoverPanel(place: place, action: action, wanted: enabled, panel: panel))
    }

    /// Draws the open hover panel over this view, the window's content: no scroll view or mask around its
    /// trigger clips it, and there is one at a time.
    func hoverPanelHost() -> some View {
        modifier(HoverPanelHost())
    }
}

/// The window's open hover panel, which its trigger sets: observed only by the host. (A preference that every tab
/// capsule wrote was combined at every update of the window: 100–150 ms of the main thread in a pass of tab
/// switches, swipes and overview opens.)
@MainActor @Observable
final class HoverPanels {
    var open: OpenPanel?
}

private struct HoverPanelHost: ViewModifier {
    @State private var panels = HoverPanels()

    func body(content: Content) -> some View {
        content.environment(panels).overlay {
            // Always here, so the panel is the view inserted and scales about its own edge, not the window's.
            GeometryReader { proxy in
                let open = panels.open, origin = proxy.frame(in: .global).origin
                let trigger = open?.trigger.offsetBy(dx: -origin.x, dy: -origin.y) ?? .zero
                PanelLayout(trigger: trigger, place: open?.place ?? .under) {
                    // In only: the panel would lose its place on the way out.
                    if let open {
                        // Another trigger's panel is another view: no state carries over.
                        open.content.id(open.owner).transition(.asymmetric(
                            insertion: .opacity.combined(with: NSWorkspace.shared
                                .accessibilityDisplayShouldReduceMotion ? .identity
                                : .scale(scale: 0.97, anchor: open.place.panel))
                                .animation(.easeOut(duration: 0.13)),
                            removal: .identity,
                        ))
                    }
                }
            }
        }
    }
}

struct OpenPanel {
    /// Its trigger's `HoverPanel`, and the trigger's frame in the window (global).
    let owner: UUID
    var trigger: CGRect
    let place: PanelPlace
    let content: AnyView
}

/// Puts the panel at its place by the trigger, kept inside the window.
private struct PanelLayout: Layout {
    let trigger: CGRect
    let place: PanelPlace

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let panel = subviews.first else { return }
        let size = panel.sizeThatFits(.unspecified)
        let left = trigger.minX + trigger.width * place.trigger.x - size.width * place.panel.x + place.offset.width
        let top = trigger.minY + trigger.height * place.trigger.y - size.height * place.panel.y + place.offset
            .height
        panel.place(at: CGPoint(x: bounds.minX + min(max(left, gap), bounds.width - gap - size.width),
                                y: bounds.minY + min(max(top, gap), bounds.height - gap - size.height)),
                    proposal: ProposedViewSize(size))
    }
}

private struct HoverPanel<Panel: View>: ViewModifier {
    let place: PanelPlace
    let action: String?
    let wanted: Bool
    let panel: (_ close: @escaping () -> Void) -> Panel
    @State private var open = false
    @State private var overTrigger = false
    @State private var overPanel = false
    /// The open panel's frame in the window (top left based).
    @State private var panelFrame = CGRect.null
    @State private var pending: Task<Void, Never>?
    @State private var monitor: Any?
    /// The window it opened in, under the pointer: not the key one, whose Esc and pointer are not the panel's.
    @State private var window: NSWindow?
    /// Off under the overview, which hides its trigger (`underOverview`).
    @Environment(\.isEnabled) private var isEnabled
    @Environment(HoverPanels.self) private var panels: HoverPanels?
    @State private var id = UUID()
    /// The trigger's frame in the window, not observed: a write at every move (the tab bar's capsules while the strip
    /// slides) redrew every trigger at every frame.
    @State private var trigger = Trigger()
    private final class Trigger {
        var frame = CGRect.zero
    }

    private var enabled: Bool {
        wanted && isEnabled
    }

    func body(content: Content) -> some View {
        content
            .onHover { overTrigger = $0
                hovered()
            }
            // A click is not a rest: no panel until the pointer comes back (onHover fires only on entering).
            .simultaneousGesture(TapGesture().onEnded {
                overTrigger = false
                hovered()
            })
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                trigger.frame = frame
                if open, panels?.open?.owner == id {
                    panels?.open?.trigger = frame
                }
            }
            .accessibilityActions {
                if let action {
                    Button(action) { show(true) }
                }
            }
            // Nothing left to show: it goes at once. It opens only on a hover, never under a still pointer.
            .onChange(of: enabled) {
                if !enabled {
                    show(false)
                }
            }
            .onDisappear { show(false) }
    }

    private func hovered() {
        pending?.cancel()
        let over = enabled && (overTrigger || overPanel)
        guard over != open, !over || NSEvent.pressedMouseButtons == 0 else { return }
        pending = Task {
            try? await Task.sleep(for: .milliseconds(over ? 250 : 150))
            // A drag may have started meanwhile.
            if !Task.isCancelled, !over || NSEvent.pressedMouseButtons == 0 {
                show(over || enabled && pointerInPanel)
            }
        }
    }

    /// Over the open panel by its frame: a busy app runs the panel's hover late, after the trigger's grace or a
    /// click in it, which then closed it and went to the view under it (on CI).
    private var pointerInPanel: Bool {
        guard open, let window, let height = window.contentView?.bounds.height else { return false }
        let point = window.mouseLocationOutsideOfEventStream
        return panelFrame.contains(CGPoint(x: point.x, y: height - point.y))
    }

    private func show(_ value: Bool) {
        pending?.cancel()
        open = value
        if value {
            panels?.open = OpenPanel(
                owner: id,
                trigger: trigger.frame,
                place: place,
                content: AnyView(panel { show(false) }
                    .onHover { overPanel = $0
                        hovered()
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelFrame = $0 }),
            )
        } else if panels?.open?.owner == id {
            panels?.open = nil
        }
        if value, monitor == nil {
            let under = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
            window = NSApp.window(withWindowNumber: under) ?? NSApp.keyWindow
            let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
            monitor = NSEvent.addLocalMonitorForEvents(matching: events) { event in
                guard event.type != .keyDown || event.keyCode == 53 && event.window === window else { return event }
                let escape = event.type == .keyDown
                let swallow = MainActor.assumeIsolated {
                    if escape || !overPanel && !pointerInPanel {
                        show(false)
                    }
                    // A text field that edits (a rename, a filter) still gets its Esc.
                    return escape && !(window?.firstResponder is NSText)
                }
                return swallow ? nil : event
            }
        } else if !value {
            // A panel that goes from under the pointer sends no hover exit.
            overPanel = false
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

/// Rex's "peek": a tab's title and rolled-up status and a row for each of its first six panes. A click on a row
/// goes to that pane; on the title, to the tab. A blocked agent's row shows its last screen lines (herdr 0.9.5
/// sends no blocked message), read once when the card opens.
struct HoverCard: View {
    let tabID: String
    let page: Page
    let close: () -> Void
    /// Each blocked pane's last 3 non-empty screen lines.
    @State private var lines: [String: [String]] = [:]

    var body: some View {
        let store = page.store
        if let workspace = store.workspace(of: tabID), let tab = workspace.tabs.first(where: { $0.id == tabID }) {
            let panes = store.panes(in: tabID)
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    page.select(workspace, tab: tabID)
                    close()
                } label: {
                    HStack(spacing: 8) {
                        FadeText(text: page.titleLabel(tab)).fontWeight(.medium)
                        Spacer(minLength: 0)
                        if let state = tab.agent?.state, state != .idle {
                            StateCapsule(state: state)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 26)
                }
                .buttonStyle(ChromeStyle(radius: 6))
                .accessibilityIdentifier("hovercard.title")
                ForEach(panes.prefix(6)) { pane in row(pane) }
                if panes.count > 6 {
                    Text("+\(panes.count - 6) more").font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }
            .padding(6)
            // Not narrower when it fits: the screen lines come in after it shows and would widen it.
            .frame(width: 280, alignment: .leading)
            .floatingGlass(in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Panes of \(page.titleText(tab))")
            .accessibilityIdentifier("hovercard")
            .task {
                guard let client = store.client else { return }
                for pane in panes.prefix(6) where pane.state == .needsYou {
                    if let text = try? await client.screen(pane.id) {
                        lines[pane.id] = text.split(whereSeparator: \.isNewline)
                            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(3)
                    }
                }
            }
        }
    }

    private func row(_ pane: HostStore.Pane) -> some View {
        let shown = lines[pane.id] ?? [], name = pane.agentName ?? pane.programName ?? "terminal"
        return Button {
            page.go(to: pane)
            close()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ProgramGlyph(icon: pane.iconID, letter: pane.letter)
                    Text(name).lineLimit(1).layoutPriority(1)
                    Text(pane.folder ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if pane.state == .working {
                        WorkingDots()
                    } else if let state = pane.state {
                        StateCapsule(state: state)
                    }
                }
                ForEach(shown.indices, id: \.self) { index in
                    Text(shown[index]).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minHeight: 26)
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .accessibilityIdentifier("hovercard.\(pane.id)")
        .accessibilityLabel([name, pane.folder].compactMap(\.self).joined(separator: ", "))
        .accessibilityValue(([pane.state?.capsule].compactMap(\.self) + shown).joined(separator: "\n"))
    }
}
