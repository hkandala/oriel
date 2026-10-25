#if os(macOS)
    import SwiftUI

    /// ⌘/: every shortcut of the command list, grouped by the level it acts on. Glass like the palette; Esc, ⌘/ or a
    /// click outside closes it.
    struct Shortcuts: View {
        let commands: [Command]
        @FocusState private var focused: Bool

        var body: some View {
            let rows = Self.rows(commands)
            let panel = HStack(alignment: .top, spacing: 48) {
                column([.panes, .tabs, .workspaces], rows)
                column([.sessions, .view, .edit], rows)
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            // A short window scrolls the panel. ponytail: a window under about 870 pt wide clips its sides; a scroll
            // view on both axes filled the whole window.
            ViewThatFits(in: .vertical) {
                panel
                ScrollView { panel }.scrollIndicators(.never)
            }
            .floatingGlass(in: .rect(cornerRadius: 14))
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
                        .padding(.top, group == groups.first ? 0 : 18).padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("shortcuts.section.\(group.rawValue)")
                    ForEach(rows.filter { $0.group == group }, id: \.title) { row in
                        HStack(spacing: 4) {
                            Text(row.title)
                            Spacer(minLength: 24)
                            ForEach(Array(row.keys.enumerated()), id: \.offset) { index, caps in
                                if index > 0 {
                                    Text("or").foregroundStyle(.secondary).padding(.horizontal, 4)
                                }
                                ForEach(caps, id: \.self, content: Self.keycap)
                            }
                        }
                        .font(.system(size: 13))
                        .frame(height: 30)
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityLabel(row.title)
                        .accessibilityValue(row.keys.map { $0.joined() }.joined(separator: " or "))
                        .accessibilityIdentifier("shortcuts.\(row.title)")
                    }
                }
            }
            .frame(width: 380)
        }

        /// One modifier or key in its own box, so a long shortcut reads clearly.
        private static func keycap(_ cap: String) -> some View {
            Text(cap).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .frame(minWidth: 22, minHeight: 22)
                .background(.quaternary, in: .rect(cornerRadius: 5))
        }

        private struct Row {
            let group: Command.Group
            let title: String
            /// Each shortcut's keycaps: the first, then a second key ("⌘K or ⇧⌘P").
            let keys: [[String]]
        }

        /// One row per command with a key, in the command list's order, with its second key; a family's commands share
        /// one row and one keycap for their keys ("Select Pane ⌥ ⌘ ←→↑↓", "Show Tab 1–9 ⌘ 1–9").
        private static func rows(_ commands: [Command]) -> [Row] {
            var rows: [Row] = []
            for command in commands {
                guard let key = command.key, !rows.contains(where: { $0.title == command.family?.title }) else {
                    continue
                }
                let caps = command.family.map { key.caps.dropLast() + [$0.keys] } ?? key.caps
                let seconds = KeyboardShortcut.seconds.filter { $0.first == key }.map(\.second.caps)
                rows.append(Row(group: command.group ?? command.section.group,
                                title: command.family?.title ?? command.title.replacing("…", with: ""),
                                keys: [caps] + seconds))
            }
            return rows
        }
    }
#endif
