#if os(macOS)
    import SwiftUI

    /// ⌘/: every shortcut of the command list, grouped by the level it acts on. Glass like the palette; Esc, ⌘/ or a
    /// click outside closes it.
    struct Shortcuts: View {
        let commands: [Command]
        @FocusState private var focused: Bool

        var body: some View {
            let rows = Self.rows(commands)
            let panel = HStack(alignment: .top, spacing: 32) {
                column([.panes, .tabs, .workspaces], rows)
                column([.sessions, .view, .edit], rows)
            }
            .padding(16)
            // A short window scrolls the panel.
            ViewThatFits(in: .vertical) {
                panel
                ScrollView { panel }.scrollIndicators(.never)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .padding(.vertical, 16)
            // The panel takes the keyboard, so Esc reaches it.
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("shortcuts")
        }

        private func column(_ groups: [Command.Group], _ rows: [Row]) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.self) { group in
                    Text(group.rawValue).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.top, group == groups.first ? 0 : 12).padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("shortcuts.section.\(group.rawValue)")
                    ForEach(rows.filter { $0.group == group }, id: \.title) { row in
                        HStack {
                            Text(row.title)
                            Spacer(minLength: 16)
                            Text(row.keys).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                        .frame(height: 20)
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityLabel(row.title)
                        .accessibilityValue(row.keys)
                        .accessibilityIdentifier("shortcuts.\(row.title)")
                    }
                }
            }
            .frame(width: 280)
        }

        struct Row {
            let group: Command.Group
            let title: String
            var keys: String
        }

        /// One row per command with a key, in the command list's order, with its second key ("⇧⌘P"); a family's
        /// commands share one row ("Select Pane ⌥⌘←→↑↓", "Show Tab 1–9 ⌘1–9").
        static func rows(_ commands: [Command]) -> [Row] {
            var rows: [Row] = []
            for command in commands {
                guard let key = command.key else { continue }
                let digit = command.family != nil && key.key.character.isNumber
                if let family = command.family, let index = rows.firstIndex(where: { $0.title == family }) {
                    if !digit {
                        rows[index].keys += key.glyphs.suffix(1)
                    }
                    continue
                }
                let seconds = KeyboardShortcut.seconds.filter { $0.first == key }.map(\.second.glyphs)
                rows.append(Row(group: command.group ?? command.section.group,
                                title: command.family ?? command.title.replacing("…", with: ""),
                                keys: ([key.glyphs + (digit ? "–9" : "")] + seconds).joined(separator: "  ")))
            }
            return rows
        }
    }
#endif
