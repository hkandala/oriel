#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// ⌘K (D48): every command with its shortcut, the selected workspace's tabs, the window's workspaces and its
    /// pages. A command with choices or a name opens a sub-page; ⌫ on an empty field or Esc goes back.
    struct Palette: View {
        let pages: WindowPages
        let page: Page
        let commands: CommandList
        @Binding var open: Bool
        /// The window's height: the list takes what is left under the field, as in Rex.
        let height: CGFloat
        /// The command whose sub-page shows; nil on the root. Sub-pages hold no sub-pages, so one level is the stack.
        @State private var sub: String?
        @State private var lit: String?
        /// A preview page left without Enter puts the old choice back.
        @State private var restore: (() -> Void)?

        var body: some View {
            let list = commands.all
            let command = sub.flatMap { title in list.first { $0.title == title } }
            FilterList(
                prompt: command?.name == nil ? "Search" : "Name",
                // A sub-page says where you are.
                title: command?.title.replacing("…", with: ""),
                fieldSymbol: command?.name == nil ? "magnifyingglass" : "pencil",
                name: "palette",
                items: command.map(subItems) ?? { rootItems($0, list) },
                start: command.map(start) ?? 0,
                maxHeight: min(460, max(84, height - 154)),
                lit: $lit,
                text: command?.name?.current ?? "",
                submit: command?.name.map { name in { text in Task { await name.save(text) } } },
                back: back,
                rowHeight: 28,
            ) { open = false }
                // A new page starts with a new field and list.
                .id(sub)
                .padding(8)
                .frame(width: 480)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                // Rex's preview delay.
                .task(id: lit) {
                    guard command?.previews == true, let lit,
                          await (try? Task.sleep(for: .seconds(0.75))) != nil else { return }
                    command?.menu.first { lit == "choice.\($0.title)" }?.action()
                }
                .onDisappear { restore?() }
        }

        /// Empty field: Commands, Tabs, Workspaces, Sessions under headers. Typed: one list, best match first; ties go
        /// in that order, then shorter titles first. A keyword match ranks under a title match.
        private func rootItems(_ filter: String, _ list: [Command]) -> [FilterList.Item] {
            let rows = commandRows(list) + placeRows()
            guard !filter.trimmingCharacters(in: .whitespaces).isEmpty else { return rows.map(\.item) }
            let sections = ["Commands", "Tabs", "Workspaces", "Sessions"]
            return rows.compactMap { row in
                [row.item.title.fuzzyScore(filter), row.keywords.fuzzyScore(filter).map { $0 + 3 }].compactMap(\.self)
                    .min().map { (score: $0, item: row.item) }
            }
            .sorted { first, second in
                let rank = { (item: FilterList.Item) in sections.firstIndex(of: item.section ?? "") ?? 0 }
                return (first.score, rank(first.item), first.item.title.count)
                    < (second.score, rank(second.item), second.item.title.count)
            }
            .map { row in
                var item = row.item
                item.section = nil
                return item
            }
        }

        /// The enabled commands; a setting says what it does now ("Turn On Focus Follows Mouse").
        private func commandRows(_ list: [Command]) -> [(item: FilterList.Item, keywords: String)] {
            list.filter { $0.section != .tabs && $0.enabled }.map { command in
                let opens = !command.menu.isEmpty || command.name != nil
                let title = command.checked
                    .flatMap { command.setting ? "Turn \($0 ? "Off" : "On") \(command.title)" : nil }
                    ?? (opens ? command.title.replacing("…", with: "") : command.title)
                let item = FilterList.Item(id: "command.\(command.title)", symbol: command.symbol, title: title,
                                           detail: command.key?.glyphs ?? "", section: "Commands", opens: opens,
                                           act: {
                                               if opens {
                                                   sub = command.title
                                                   restore = command.previews
                                                       ? command.menu.first { $0.checked == true }?.action : nil
                                               } else {
                                                   command.action()
                                               }
                                           })
                return (item, command.keywords)
            }
        }

        /// The selected workspace's tabs, the window's workspaces (with their session) and its pages.
        private func placeRows() -> [(item: FilterList.Item, keywords: String)] {
            let tabs = (page.selectedWorkspace?.tabs ?? []).map { tab in
                FilterList.Item(id: "tab.\(tab.id)", pane: page.stack(tab).first, title: page.titleText(tab),
                                section: "Tabs", act: {
                                    if let workspace = page.selectedWorkspace {
                                        page.select(workspace, tab: tab.id)
                                    }
                                })
            }
            let workspaces = pages.list.flatMap { other in
                other.store.workspaces.map { workspace in
                    FilterList.Item(id: "workspace.\(other.id).\(workspace.id)", symbol: "folder",
                                    title: workspace.label, detail: other.id, section: "Workspaces", act: {
                                        pages.show(other)
                                        other.select(workspace)
                                    })
                }
            }
            let sessions = pages.list.map { other in
                FilterList.Item(id: "session.\(other.id)", symbol: "rectangle.stack", title: other.id,
                                section: "Sessions", act: { pages.show(other) })
            }
            // A workspace also matches its session's name.
            return tabs.map { ($0, "") } + workspaces.map { ($0, $0.detail) } + sessions.map { ($0, "") }
        }

        /// A sub-page: its choices, filtered; the current one has a checkmark. A name page has none.
        private func subItems(_ command: Command) -> (String) -> [FilterList.Item] {
            { filter in
                command.menu.filter { $0.enabled && $0.title.matches(filter) }.map { choice in
                    let symbol = choice.checked == true ? "checkmark" : choice.symbol
                    return FilterList.Item(id: "choice.\(choice.title)", symbol: symbol, title: choice.title) {
                        restore = nil
                        choice.action()
                    }
                }
            }
        }

        /// The current choice is lit first.
        private func start(_ command: Command) -> Int {
            command.menu.filter(\.enabled).firstIndex { $0.checked == true } ?? 0
        }

        /// Back to the root, putting back a choice being previewed. Not from the root.
        private func back() -> Bool {
            guard sub != nil else { return false }
            restore?()
            restore = nil
            sub = nil
            return true
        }
    }
#endif
