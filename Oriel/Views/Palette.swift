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
    /// The choice a preview page opened on: it keeps the checkmark, and leaving without Enter picks it again.
    @State private var kept: String?

    var body: some View {
        let list = commands.all
        let command = sub.flatMap { title in list.first { $0.title == title } }
        VStack(alignment: .leading, spacing: 2) {
            // A sub-page says where you are.
            if let command {
                Text(Self.pageTitle(command)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.bottom, 2)
                    .accessibilityIdentifier("palette.title")
                    .accessibilityAddTraits(.isHeader)
            }
            palette(command, list)
        }
        .padding(8)
        .frame(width: 480)
        .floatingGlass(in: .rect(cornerRadius: 14))
        // Rex's preview delay.
        .task(id: lit) {
            guard command?.previews == true, let lit,
                  await (try? Task.sleep(for: .seconds(0.75))) != nil,
                  // Not after the page was left or a row chosen meanwhile.
                  kept != nil else { return }
            command?.menu.first { lit == Self.choiceID($0) }?.action()
        }
        .onDisappear { putBack() }
    }

    private func palette(_ command: Command?, _ list: [Command]) -> some View {
        FilterList(
            prompt: command?.name == nil ? "Search" : "Name",
            fieldSymbol: command?.name == nil ? "magnifyingglass" : "pencil",
            name: "palette",
            items: command.map(subItems) ?? { rootItems($0, list) },
            // The root lights the selected tab: ↩ on a fresh palette stays put. A floating window's lists no tabs.
            start: command.map(start) ?? (commands.floating != nil ? 0
                : page.selectedWorkspace?.tabs.firstIndex { $0.id == page.selectedTab?.id } ?? 0),
            maxHeight: min(460, max(84, height - 154)),
            // Only a preview page reads it: on the others each new light drew the whole palette again.
            lit: command?.previews == true ? $lit : nil,
            text: command?.name?.current ?? "",
            submit: command?.name.map { name in { text in Task { await name.save(text) } } },
            back: sub == nil ? nil : { back() },
            rowHeight: 28,
        ) { open = false }
            // A new page starts with a new field and list.
            .id(sub)
    }

    static func choiceID(_ choice: Command) -> String {
        "choice.\(choice.id ?? choice.title)"
    }

    /// A page's title and its row's: no "…" (Rename Pane… in the menu bar).
    static func pageTitle(_ command: Command) -> String {
        command.title.replacing("…", with: "")
    }

    /// Empty field: Tabs, Workspaces, Sessions, then Commands, under headers. Typed: one list, best match first; a
    /// tie goes to a title that starts with the filter ("font size": Font Size › before Increase Font Size), then
    /// to commands before places, then to the earlier row (the menu's and the sidebar's order). A keyword match
    /// ranks under a title match.
    private func rootItems(_ filter: String, _ list: [Command]) -> [FilterList.Item] {
        // A floating window's palette lists only its commands (D50).
        let commands = commandRows(list), places = self.commands.floating == nil ? placeRows() : []
        guard !filter.trimmingCharacters(in: .whitespaces).isEmpty else { return (places + commands).map(\.item) }
        return (commands + places).enumerated().compactMap { index, row in
            [row.item.title.fuzzyScore(filter), row.keywords.fuzzyScore(filter).map { $0 + 3 }].compactMap(\.self)
                .min().map { score in
                    let starts = row.item.title.range(of: filter, options: [.anchored, .caseInsensitive,
                                                                            .diacriticInsensitive]) != nil
                    return (score: score, rest: starts ? 0 : 1, index: index, item: row.item)
                }
        }
        .sorted { ($0.score, $0.rest, $0.index) < ($1.score, $1.rest, $1.index) }
        .map { row in
            var item = row.item
            item.section = nil
            return item
        }
    }

    /// The enabled commands; a setting says what it does now ("Turn On Focus Follows Mouse").
    private func commandRows(_ list: [Command]) -> [(item: FilterList.Item, keywords: String)] {
        // The menu bar's order, then the palette's own; not the places on ⌘1…⌘9 (the place rows list them). Not
        // Command Palette: it is open.
        Command.Section.allCases.filter { ![.tabs, .workspaces, .sessions].contains($0) }
            .flatMap { section in list.filter { $0.section == section } }
            .filter { $0.enabled && $0.key != .palette }.map { command in
                let opens = !command.menu.isEmpty || command.name != nil
                let title = command.checked
                    .flatMap { command.setting ? "Turn \($0 ? "Off" : "On") \(command.title)" : nil }
                    ?? (opens ? Self.pageTitle(command) : command.title)
                let item = FilterList.Item(id: "command.\(command.title)", symbol: command.symbol, title: title,
                                           detail: command.key?.glyphs ?? "", section: "Commands", opens: opens,
                                           act: {
                                               if opens {
                                                   sub = command.title
                                                   kept = command.previews
                                                       ? command.menu.first { $0.checked == true }?.title : nil
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
            command.menu.filter { $0.enabled && $0.title.fuzzyScore(filter) != nil }.map { choice in
                let current = command.previews ? choice.title == kept : choice.checked == true
                let symbol = current ? "checkmark" : choice.symbol
                return FilterList.Item(id: Self.choiceID(choice), symbol: symbol, title: choice.title,
                                       section: choice.heading, act: {
                                           kept = nil
                                           choice.action()
                                       })
            }
        }
    }

    /// The current choice is lit first.
    private func start(_ command: Command) -> Int {
        command.menu.filter(\.enabled).firstIndex { command.previews ? $0.title == kept : $0.checked == true } ?? 0
    }

    /// Back to the root, putting back a choice being previewed.
    private func back() {
        putBack()
        sub = nil
    }

    private func putBack() {
        if let kept, let command = commands.all.first(where: { $0.title == sub }) {
            command.menu.first { $0.title == kept }?.action()
        }
        kept = nil
    }
}
