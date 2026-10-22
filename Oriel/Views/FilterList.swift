import HerdrKit
import SwiftUI

/// A filter field over rows: type to filter, arrows move, Enter acts (Esc is the panel's). The palette, the
/// workspace menu and the Open Session sheet.
struct FilterList: View {
    struct Item {
        let id: String
        var symbol: String?
        /// A pane's program tile instead of the symbol.
        var pane: HostStore.Pane?
        /// A workspace's state icon instead of the symbol.
        var state: AgentState?
        let title: String
        var detail = ""
        /// Where it changes from the row before: a header above the row, or a divider when empty.
        var section: String?
        /// A spinner in place of the detail.
        var busy = false
        /// Opens a sub-page: a › on the right, and the list stays open.
        var opens = false
        let act: () -> Void
    }

    let prompt: String
    /// A header above the field (a palette sub-page says where you are): `<name>.title`.
    var title: String?
    var fieldSymbol = "line.3.horizontal.decrease.circle"
    /// The field is `<name>.filter`, a row `<name>.<item id>`.
    let name: String
    /// The rows for a filter. A function, so each key reads the rows as they are now.
    let items: (String) -> [Item]
    /// The row lit until something is typed.
    var start = 0
    let maxHeight: CGFloat
    /// The lit row's id, for a button outside the list that acts on it.
    var lit: Binding<String?>?
    /// The field's first text (a name page).
    var text = ""
    /// Enter acts on the field's text instead of a row (a name page).
    var submit: ((String) -> Void)?
    /// ⌫ on an empty field, or Esc: back a page. Whether it went back (Esc goes on to close the panel otherwise).
    var back: (() -> Bool)?
    var rowHeight: CGFloat = 26
    /// After a row acted.
    let done: () -> Void
    @State private var filter = ""
    @State private var index: Int?
    /// The rows' own height: the list is as tall as its rows, up to `maxHeight`, then scrolls.
    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        let items = items(filter)
        let index = current(items)
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.bottom, 2)
                    .accessibilityIdentifier("\(name).title")
            }
            FilterField(prompt: prompt, text: $filter, identifier: "\(name).filter", symbol: fieldSymbol,
                        autofocus: true)
                // Here, not onSubmit: a field's submit action is not refreshed when only the index changes, so ↓
                // Enter took the first row. Each handler reads the rows and the index as they are now.
                .onKeyPress(.return) {
                    let items = self.items(filter)
                    if let submit {
                        submit(filter)
                        done()
                    } else if !items.isEmpty {
                        act(items[current(items)])
                    }
                    return .handled
                }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                // ⌫ arrives as DEL (U+7F), which `.delete` (U+8) does not match.
                .onKeyPress(keys: [.delete, KeyEquivalent("\u{7F}")]) { _ in
                    filter.isEmpty && back?() == true ? .handled : .ignored
                }
                .onKeyPress(.escape) { back?() == true ? .handled : .ignored }
                .padding(.bottom, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                            if item.section != (offset > 0 ? items[offset - 1].section : nil) {
                                if let section = item.section, !section.isEmpty {
                                    Text(section).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 8).padding(.top, offset > 0 ? 6 : 0)
                                        .accessibilityIdentifier("\(name).section.\(section)")
                                } else {
                                    Divider().padding(4)
                                }
                            }
                            Button { act(item) } label: {
                                MenuRow(symbol: item.symbol, pane: item.pane, state: item.state, title: item.title,
                                        detail: item.busy ? "" : [item.detail, item.opens ? "›" : ""]
                                            .filter { !$0.isEmpty }.joined(separator: " "),
                                        selected: offset == index, height: rowHeight)
                                    .overlay(alignment: .trailing) {
                                        if item.busy {
                                            ProgressView().controlSize(.small).padding(.trailing, 8)
                                        }
                                    }
                            }
                            .buttonStyle(ChromeStyle(selected: offset == index, tint: .accentColor))
                            .accessibilityIdentifier("\(name).\(item.id)")
                            .accessibilityValue(item.state?.word ?? "")
                            .accessibilityAddTraits(offset == index ? .isSelected : [])
                        }
                        if items.isEmpty, submit == nil {
                            Text("No matches").foregroundStyle(.secondary).padding(8)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                }
                .scrollIndicators(.never)
                .frame(height: min(rowsHeight, maxHeight))
                .onChange(of: index) {
                    if items.indices.contains(index) {
                        proxy.scrollTo(items[index].id)
                    }
                }
            }
        }
        .onAppear { filter = text }
        // A cleared filter lights the start row again (the selected workspace).
        .onChange(of: filter) { self.index = filter.isEmpty ? nil : 0 }
        .onChange(of: items.isEmpty ? nil : items[index].id, initial: true) { lit?.wrappedValue = $1 }
    }

    private func current(_ items: [Item]) -> Int {
        max(0, min(index ?? start, items.count - 1))
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let items = items(filter)
        index = max(0, min(current(items) + step, items.count - 1))
        return .handled
    }

    private func act(_ item: Item) {
        item.act()
        if !item.opens {
            done()
        }
    }
}

/// The filter field of the sidebar and the session list. Until clicked (or with `autofocus`) it is plain text,
/// so the window has no text field to hand the keyboard to at launch; keys belong to the panes.
struct FilterField: View {
    let prompt: String
    @Binding var text: String
    let identifier: String
    var symbol = "line.3.horizontal.decrease.circle"
    var autofocus = false
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if editing || autofocus || !text.isEmpty {
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .focusSoon($focused)
                    .onChange(of: focused) { editing = focused }
                    .accessibilityIdentifier(identifier)
            } else {
                // A button, not a field: it can't take the keyboard at launch, and VoiceOver can press it.
                Button { editing = true } label: {
                    Text(prompt).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.07), in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { editing = true }
    }
}

extension View {
    /// Focuses the field as it appears.
    func focusSoon(_ focused: FocusState<Bool>.Binding) -> some View {
        task {
            // ponytail: focus asked for as the field appears is dropped (AppKit has not made it a key view yet), and
            // a single later ask was sometimes dropped too (⌘K, then typing went nowhere); ask every 50 ms until it
            // holds, for up to 1 s. Upgrade: an AppKit field that takes first responder in viewDidMoveToWindow.
            for _ in 0 ..< 20 where !focused.wrappedValue {
                try? await Task.sleep(for: .milliseconds(50))
                focused.wrappedValue = true
            }
        }
    }
}
