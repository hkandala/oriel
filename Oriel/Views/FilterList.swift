import HerdrKit
import SwiftUI

/// A filter field over rows: type to filter, arrows move, Enter acts (Esc is the panel's). The palette, the
/// workspace menu and the Open Session panel.
struct FilterList: View {
    struct Item {
        let id: String
        var symbol: String?
        /// A pane's program tile instead of the symbol.
        var pane: HostStore.Pane?
        /// A workspace's state icon instead of the symbol; `.some(nil)` for a workspace with no agent.
        var state: AgentState??
        let title: String
        var detail = ""
        /// Where it changes from the row before: a header above the row, or a divider when empty.
        var section: String?
        /// A spinner in place of the detail.
        var busy = false
        /// Opens a sub-page: a › on the right, and the list stays open.
        var opens = false
        /// A second action, a button on the lit row's right end (Open Session's Stop, Delete and Detach). The list
        /// stays open.
        var button: (title: String, act: () -> Void)?
        /// The button's role: red when destructive.
        var buttonRole: ButtonRole?
        #if os(macOS)
            /// Where a drop on the row moves the page's dragged pane or tab: a workspace, or a new one (the workspace
            /// menu).
            var drop: MenuRowDrop.Target?
        #endif
        let act: () -> Void
    }

    let prompt: String
    var fieldSymbol: String?
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
    /// ⌫ on an empty field, or Esc: back a page. Without it Esc goes on to close the panel.
    var back: (() -> Void)?
    var rowHeight: CGFloat = 26
    /// The last rows sit under the scrolled ones, always in view: the workspace menu's New Workspace is a drop target
    /// only in view as a drag starts (macOS 27, `MenuRowDrop`).
    var pinned = 0
    /// Off for the workspace menu a drag holds open: the drag's keyboard card keeps the keys.
    var autofocus = true
    /// After a row acted or the field's text was submitted.
    let done: () -> Void
    @State private var filter = ""
    /// The lit row, by id: rows that move or go (Open Session's Stop and Delete read the list again) must not hand
    /// the light, and the row's button, to the row that takes its place. None: the start row, or the first once
    /// something is typed.
    @State private var litID: String?
    /// The rows' own height: the list is as tall as its rows, up to `maxHeight`, then scrolls.
    @State private var rowsHeight: CGFloat = 0
    #if os(macOS)
        /// The pointer's last place on screen: only a move lights a row, not a row that scrolls under a pointer at
        /// rest or the row under it as the panel opens.
        @State private var pointer = NSEvent.mouseLocation
    #endif
    /// The pointer lit the row: no scroll to it, as in a menu.
    @State private var pointed = false

    var body: some View {
        let items = items(filter)
        let index = current(items)
        VStack(alignment: .leading, spacing: 2) {
            FilterField(prompt: prompt, text: $filter, identifier: "\(name).filter", symbol: fieldSymbol,
                        autofocus: autofocus)
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
                // ⌫ arrives as DEL (U+7F), which `.delete` (U+8) does not match. Not its repeats: holding ⌫ to clear
                // the field must not leave the page.
                .onKeyPress(keys: [.delete, KeyEquivalent("\u{7F}")], phases: .down) { _ in
                    guard filter.isEmpty, let back else { return .ignored }
                    back()
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard let back else { return .ignored }
                    back()
                    return .handled
                }
                .padding(.bottom, 4)
            // A name page has no rows.
            if submit == nil {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Lazy: the palette's 100 rows took 230 ms to build and lay out on CI as it opened (phase 25).
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(items.enumerated().dropLast(pinned)), id: \.element.id) { offset, _ in
                                row(items, offset, index)
                            }
                            if items.isEmpty {
                                Text("No matches").foregroundStyle(.secondary).padding(8)
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                    }
                    .scrollIndicators(.never)
                    .frame(height: min(rowsHeight, maxHeight))
                    // A new lit row, and the lit row once the list has its height: a sub-page's may sit below the fold
                    // (Font Size).
                    .onChange(of: rowsHeight > 0 ? index : nil) {
                        if !pointed, items.indices.contains(index) {
                            proxy.scrollTo(items[index].id)
                        }
                    }
                }
                ForEach(Array(items.enumerated().suffix(pinned)), id: \.element.id) { offset, _ in
                    row(items, offset, index)
                }
            }
        }
        .onAppear { filter = text }
        // A cleared filter lights the start row again.
        .onChange(of: filter) {
            pointed = false
            litID = nil
        }
        .onChange(of: items.isEmpty ? nil : items[index].id, initial: true) { lit?.wrappedValue = $1 }
    }

    /// A row, with a header or a divider above it where its section changes.
    @ViewBuilder
    private func row(_ items: [Item], _ offset: Int, _ index: Int) -> some View {
        let item = items[offset]
        if item.section != (offset > 0 ? items[offset - 1].section : nil) {
            if let section = item.section, !section.isEmpty {
                Text(section).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.top, offset > 0 ? 6 : 0)
                    .accessibilityIdentifier("\(name).section.\(section)")
                    .accessibilityAddTraits(.isHeader)
            } else {
                Divider().padding(4)
            }
        }
        Button { act(item) } label: {
            MenuRow(item: item, selected: offset == index, height: rowHeight)
        }
        .buttonStyle(ChromeStyle(selected: offset == index, tint: .accentColor))
        .accessibilityIdentifier("\(name).\(item.id)")
        .accessibilityValue(item.state??.word ?? "")
        .accessibilityAddTraits(offset == index ? .isSelected : [])
        // After the row's accessibility, which would name this button too.
        .overlay(alignment: .trailing) {
            // Not while its spinner shows.
            if let button = item.button, offset == index, !item.busy {
                Button(button.title, role: item.buttonRole, action: button.act)
                    .buttonStyle(RowButtonStyle())
                    .padding(.trailing, 4)
                    .accessibilityIdentifier("\(name).\(item.id).\(button.title.lowercased())")
            }
        }
        #if os(macOS)
        .modifier(MenuRowDrop(target: item.drop))
        // The light follows the pointer, as in a menu (user, phase 24).
        .onContinuousHover { phase in
            guard case .active = phase, NSEvent.mouseLocation != pointer else { return }
            pointer = NSEvent.mouseLocation
            pointed = true
            litID = item.id
        }
        #endif
    }

    private func current(_ items: [Item]) -> Int {
        items.firstIndex { $0.id == litID } ?? max(0, min(filter.isEmpty ? start : 0, items.count - 1))
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let items = items(filter)
        pointed = false
        if !items.isEmpty {
            litID = items[max(0, min(current(items) + step, items.count - 1))].id
        }
        return .handled
    }

    private func act(_ item: Item) {
        item.act()
        if !item.opens {
            done()
        }
    }
}

/// The filter field of the sidebar and `FilterList`. Until clicked (or with `autofocus`) it is plain text,
/// so the window has no text field to hand the keyboard to at launch; keys belong to the panes.
struct FilterField: View {
    let prompt: String
    @Binding var text: String
    let identifier: String
    var symbol: String?
    var autofocus = false
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol ?? "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if editing || autofocus || !text.isEmpty {
                TextField(prompt, text: $text)
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
        .fieldCapsule()
        .contentShape(.capsule)
        .onTapGesture { editing = true }
    }
}

#if os(macOS)
    /// A rename field, focused as it appears with the old name: Enter commits, Esc ends, a click elsewhere blurs it.
    struct RenameField: View {
        let prompt: String
        let initial: String
        let commit: (String) -> Void
        /// After a commit and on Esc.
        let end: () -> Void
        /// The field lost the keyboard: `end` unless given.
        var blur: (() -> Void)?
        @State private var draft = ""
        @FocusState private var focused: Bool

        var body: some View {
            TextField(prompt, text: $draft).textFieldStyle(.plain).focused($focused)
                .onSubmit {
                    commit(draft)
                    end()
                }
                .onExitCommand(perform: end)
                .onChange(of: focused) { _, now in
                    if !now {
                        (blur ?? end)()
                    }
                }
                .onAppear { draft = initial }
                .focusSoon($focused)
        }
    }
#endif

extension View {
    /// A text field in a soft capsule.
    func fieldCapsule() -> some View {
        textFieldStyle(.plain).padding(.horizontal, 8).padding(.vertical, 5)
            .background(.primary.opacity(0.07), in: .capsule)
    }

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

extension String {
    /// Whether this label passes a typed filter: trimmed, case and accent blind, empty passes all.
    func matches(_ filter: String) -> Bool {
        let filter = filter.trimmingCharacters(in: .whitespaces)
        return filter.isEmpty || localizedStandardContains(filter)
    }
}
