import HerdrKit
import SwiftUI

/// A new pane's chooser over its hidden terminal (ui/new-pane): Terminal, Agent or Browser, then the agents; and the
/// loader while a picked agent starts. In the middle of the card's area under the header; a list on a small card.
struct NewPane: View {
    let chooser: Chooser
    let page: Page
    /// The card's id, which the identifiers start with.
    let cardID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.look) private var look
    /// VoiceOver goes to the selected tile as a step shows.
    @AccessibilityFocusState private var focus: Int?
    /// Where the pointer was when it showed or the selection last moved: only a pointer moved since selects, not a
    /// panel that shows under a pointer at rest (as the palette's rows).
    @State private var pointer = NSEvent.mouseLocation
    /// The panel's sizes: larger than new-pane.mdx's 112 pt tiles, which looked small on a large card.
    private static let tile: CGFloat = 128, spacing: CGFloat = 16, padding: CGFloat = 24
    private static let panel = CGSize(width: 3 * tile + 2 * spacing + 2 * padding, height: tile + 20 + 16 + 2 * padding)

    private struct Option {
        let id: String, name: String, line: String
        var symbol = "", command: String?
    }

    private var options: [Option] {
        guard !chooser.agents else {
            return Chooser.agents.map { Option(id: $0.command, name: $0.name, line: $0.command, command: $0.command) }
        }
        return [
            Option(id: "terminal", name: "Terminal", line: "Shell", symbol: "terminal"),
            Option(id: "agent", name: "Agent", line: "Coding agent", symbol: "sparkles"),
            Option(id: "browser", name: "Browser", line: "Coming soon", symbol: "globe"),
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Group {
                if let agent = chooser.starting {
                    loader(agent)
                } else if size.width < Self.panel.width + 32 || size.height < Self.panel.height + 32 {
                    list.padding(12).frame(width: max(0, min(280, size.width - 16)))
                        .floatingGlass(in: .rect(cornerRadius: 18))
                } else {
                    panel.padding(Self.padding).frame(width: Self.panel.width, height: Self.panel.height)
                        .floatingGlass(in: .rect(cornerRadius: 18))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        // A click beside the panel gives the card the keyboard, not the hidden terminal a click.
        .background {
            Color.clear.contentShape(.rect).onTapGesture {
                if let pane = page.store.pane(cardID) {
                    page.go(to: pane)
                }
            }
        }
        .animation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.15), value: chooser.agents)
        .animation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.15), value: chooser.starting)
        .onAppear { focus = chooser.selection }
        .onChange(of: chooser.agents) { focus = chooser.selection }
        .onChange(of: chooser.selection) { pointer = NSEvent.mouseLocation }
        // It leaves when the pane runs something else (typed from herdr's TUI): a program besides the shell, or an
        // agent herdr reports. Not the programs of a new shell's startup.
        .onChange(of: runs, initial: true) {
            if runs, chooser.starting == nil {
                page.store.drop(chooser)
            }
        }
    }

    private var runs: Bool {
        page.store.pane(cardID).map { $0.agent != nil || $0.program?.isShell == false && !$0.starting } ?? false
    }

    private var header: some View {
        let machine = page.store.machine
        return Text(chooser.agents ? "Agent" : machine.isRemote ? "New Pane on \(machine.name)" : "New Pane")
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .overlay(alignment: .leading) {
                if chooser.agents {
                    IconButton(symbol: "chevron.left", help: "Back", size: 22) { page.store.back(chooser) }
                        .accessibilityIdentifier("pane.\(cardID).chooser.back")
                }
            }
    }

    private var panel: some View {
        VStack(spacing: 16) {
            header
            HStack(spacing: chooser.agents ? 12 : Self.spacing) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    tile(index, option)
                }
            }
            // A new step cross-fades.
            .id(chooser.agents)
            .transition(.opacity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Pane")
    }

    private func tile(_ index: Int, _ option: Option) -> some View {
        let selected = chooser.selection == index
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return button(index, option) {
            VStack(spacing: 0) {
                if let command = option.command {
                    ProgramTile(icon: command).scaleEffect(2).frame(width: 44, height: 36)
                    Text(option.name).font(.system(size: 12, weight: .medium)).padding(.top, 10)
                    Text(option.line).font(.system(size: 11).monospaced()).foregroundStyle(.secondary)
                } else {
                    Image(systemName: option.symbol).font(.system(size: 32))
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)).frame(height: 36)
                    Text(option.name).font(.system(size: 13, weight: .medium)).padding(.top, 10)
                    Text(option.line).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.top, 24)
            // Four agents in the width of three tiles.
            .frame(width: chooser.agents ? (3 * Self.tile + 2 * Self.spacing - 36) / 4 : Self.tile, height: Self.tile)
            .background(
                selected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.primary.opacity(0.06)),
                in: shape,
            )
            .overlay {
                // Every tile has an edge, so all read as equal options.
                shape.strokeBorder(selected ? AnyShapeStyle(.tint.opacity(0.6))
                    : AnyShapeStyle(.primary.opacity(look.contrast ? 0.25 : 0.08)), lineWidth: selected ? 1.5 : 1)
            }
            .overlay(alignment: .topTrailing) {
                Text("\(index + 1)").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(look.contrast ? .primary : .secondary).padding(8)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    /// Under 440 × 228 pt: one row per option.
    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                let selected = chooser.selection == index
                button(index, option) {
                    HStack(spacing: 8) {
                        if let command = option.command {
                            ProgramTile(icon: command)
                        } else {
                            Image(systemName: option.symbol).font(.system(size: 16)).frame(width: 22)
                        }
                        Text(option.name).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(index + 1)").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(look.contrast ? .primary : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                }
                .buttonStyle(ChromeStyle(selected: selected, tint: .accentColor))
            }
        }
        .id(chooser.agents)
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Pane")
    }

    /// A tile or a row: the pointer selects it, a click picks it.
    private func button(_ index: Int, _ option: Option, label: () -> some View) -> some View {
        Button { page.store.pick(chooser, index) } label: { label() }
            .onContinuousHover { phase in
                if case .active = phase, NSEvent.mouseLocation != pointer {
                    chooser.selection = index
                }
            }
            .accessibilityLabel(option.name)
            .accessibilityValue(option.id == "browser" ? "Coming soon" : "")
            .accessibilityAddTraits(chooser.selection == index ? .isSelected : [])
            .accessibilityFocused($focus, equals: index)
            .accessibilityIdentifier("pane.\(cardID).chooser.\(option.id)")
    }

    private func loader(_ agent: Chooser.Agent) -> some View {
        VStack(spacing: 10) {
            ProgramTile(icon: agent.command).scaleEffect(2).frame(width: 44, height: 36)
            ProgressView().controlSize(.small)
            Text("Starting \(agent.name)…").font(.system(size: 13)).foregroundStyle(.secondary)
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
