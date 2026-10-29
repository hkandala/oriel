import HerdrKit
import SwiftUI

/// A new pane's chooser over its hidden terminal (ui/new-pane): a compact list in the middle of the card's own fill,
/// the palette's accent pill on the selected row; Agent opens its agents under it. A short card scrolls the list to
/// the selected row. Then the loader while a picked agent starts.
struct NewPane: View {
    let chooser: Chooser
    let page: Page
    /// The card's id, which the identifiers start with.
    let cardID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fade: Animation? {
        reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.15)
    }

    @Environment(\.look) private var look
    /// VoiceOver goes to the selected row as the list shows.
    @AccessibilityFocusState private var focus: Chooser.Row?
    /// Where the pointer was when it showed or the selection last moved: only a pointer moved since selects, not a
    /// list that shows under a pointer at rest (as the palette's rows).
    @State private var pointer = NSEvent.mouseLocation
    private static let row: CGFloat = 28, spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Group {
                if let agent = chooser.starting {
                    loader(agent)
                } else if let kind = chooser.opening {
                    PluginLoader(kind: kind).accessibilityIdentifier("pane.\(cardID).loader")
                } else {
                    let rows = chooser.rows
                    let height = CGFloat(rows.count) * (Self.row + Self.spacing) - Self.spacing
                    list(rows, details: size.width >= 300)
                        .frame(width: max(0, min(300, size.width - 24)), height: max(0, min(height, size.height - 16)))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        // A click beside the list gives the card the keyboard, not the hidden terminal a click.
        .background {
            Color.clear.contentShape(.rect).onTapGesture {
                if let pane = page.store.pane(cardID) {
                    page.go(to: pane)
                }
            }
        }
        .animation(fade, value: chooser.starting)
        .animation(fade, value: chooser.open)
        .animation(fade, value: chooser.opening)
        .onAppear { focus = chooser.selected }
        .onChange(of: chooser.selected) { pointer = NSEvent.mouseLocation }
        // It leaves when the pane runs something else (typed from herdr's TUI): a program besides the shell, or an
        // agent herdr reports. Not the programs of a new shell's startup.
        .onChange(of: runs, initial: true) {
            if runs, chooser.starting == nil, chooser.opening == nil {
                page.store.drop(chooser)
            }
        }
    }

    private var runs: Bool {
        page.store.pane(cardID).map { $0.agent != nil || $0.program?.isShell == false && !$0.starting } ?? false
    }

    private func list(_ rows: [Chooser.Row], details: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Self.spacing) {
                    ForEach(rows, id: \.self) { row in
                        self.row(row, details: details).id(row)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            .onChange(of: chooser.selected) { proxy.scrollTo(chooser.selected) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Pane")
    }

    private func row(_ row: Chooser.Row, details: Bool) -> some View {
        let selected = chooser.selected == row, (name, detail) = row.labels
        let agent = if case .start = row {
            true
        } else {
            false
        }
        // Readable on the accent pill.
        let dim = selected ? AnyShapeStyle(Look.onAccent.opacity(0.75))
            : look.contrast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
        return Button {
            // The card takes the keyboard, as a click on its terminal does.
            if let pane = page.store.pane(cardID) {
                page.go(to: pane)
            }
            page.store.pick(chooser, row, page: page)
        } label: {
            HStack(spacing: 8) {
                icon(row, selected: selected)
                Text(name).lineLimit(1)
                if row == .agent {
                    Image(systemName: chooser.open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(dim)
                }
                Spacer(minLength: 4)
                if details {
                    Text(detail).font(.system(size: 12, design: agent ? .monospaced : .default)).foregroundStyle(dim)
                        .lineLimit(1)
                }
                if let number = chooser.number(row) {
                    Text("\(number)").font(.system(size: 11)).monospacedDigit().foregroundStyle(dim)
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(Look.onAccent) : AnyShapeStyle(.primary))
            // An agent sits under Agent.
            .padding(.leading, agent ? 28 : 8)
            .padding(.trailing, 8)
            .frame(height: Self.row)
        }
        .buttonStyle(ChromeStyle(selected: selected, tint: .accentColor))
        .onContinuousHover { phase in
            if case .active = phase, NSEvent.mouseLocation != pointer {
                chooser.selected = row
            }
        }
        .accessibilityLabel(name)
        .accessibilityValue(row == .agent ? chooser.open ? "expanded" : "collapsed" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityFocused($focus, equals: row)
        .accessibilityIdentifier("pane.\(cardID).chooser.\(row.id)")
    }

    /// The kind's symbol, or the agent's program tile.
    private func icon(_ row: Chooser.Row, selected: Bool) -> some View {
        Group {
            switch row {
            case .terminal: Image(systemName: "terminal")
            case .agent: Image(systemName: "sparkles")
            case let .plugin(kind): Image(systemName: kind.symbol)
            case .start: ProgramTile(icon: row.id)
            }
        }
        .foregroundStyle(selected ? AnyShapeStyle(Look.onAccent.opacity(0.75))
            : row == .agent && chooser.open ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: 22)
    }

    private func loader(_ agent: Chooser.Agent) -> some View {
        VStack(spacing: 12) {
            ProgramTile(icon: agent.command).scaleEffect(2).frame(width: 44, height: 36)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting \(agent.name)…").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Starting \(agent.name)")
        .accessibilityIdentifier("pane.\(cardID).loader")
    }
}

/// The chooser on a card, fading out over 0.15 s after a pick as the terminal fades in (`TerminalHost`).
struct NewPaneOverlay: View {
    let chooser: Chooser?
    let page: Page
    let cardID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let chooser {
                NewPane(chooser: chooser, page: page, cardID: cardID).transition(.opacity)
            }
        }
        .animation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.15), value: chooser == nil)
    }
}
