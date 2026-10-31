import AppKit
import HerdrKit
import SwiftUI

/// A plugin card's second header row from its manifest (`Header`): Back and Forward when it keeps a history, then its
/// controls, left to right, from the row's left edge; the same in a pane and in a floating window.
struct PluginHeader: View {
    let plugin: Plugin
    let page: Page

    var body: some View {
        let controls = plugin.header.controls, history = plugin.header.history
        let shown = controls.indices.filter { controls[$0].hidden != true }
        HStack(spacing: 0) {
            if history {
                BackForward(plugin: plugin)
            }
            // By index, not by place among the shown: hiding one keeps a typing field's identity, and its keyboard.
            ForEach(controls.indices, id: \.self) { index in
                if let place = shown.firstIndex(of: index) {
                    let after = place > 0 ? controls[shown[place - 1]] : nil
                    HeaderItem(control: controls[index], plugin: plugin, page: page)
                        .padding(.leading, after == nil && !history ? 0 : Self.gap(after, controls[index]))
                }
            }
            // Free space goes after the controls unless a spacer or a field takes it.
            if !shown.contains(where: { ["spacer", "field"].contains(controls[$0].type) }) {
                Spacer(minLength: 0)
            }
        }
    }

    /// 6 pt between controls; icon buttons side by side touch, as Back and Forward do.
    private static func gap(_ before: PluginManifest.Control?, _ control: PluginManifest.Control) -> CGFloat {
        let icons = ["button", "toggle"]
        return icons.contains(control.type) && before.map { icons.contains($0.type) } == true ? 0 : 6
    }
}

/// One control as its type draws it (future-work/plugins/manifest#header); its identifier is `pane.<pane>.<id>`.
private struct HeaderItem: View {
    let control: PluginManifest.Control
    let plugin: Plugin
    let page: Page
    @Environment(\.look) private var look

    var body: some View {
        let id = control.id ?? "", identifier = "pane.\(plugin.paneID).\(id)"
        // Each control its own identifier: one on the group would cover the segments' and the field's.
        switch control.type {
        case "button": button(id).accessibilityIdentifier(identifier).disabled(control.enabled == false)
        case "toggle": toggle(id).accessibilityIdentifier(identifier).disabled(control.enabled == false)
        case "segmented":
            Segments(id: identifier, options: (control.options ?? []).map { ($0.title ?? "", $0.value ?? "") },
                     selection: Binding { control.value?.text ?? "" } set: { plugin.header.pick(id, .text($0)) })
                .fixedSize().disabled(control.enabled == false)
        case "menu":
            HeaderMenu(control: control, header: plugin.header).accessibilityIdentifier(identifier)
                .disabled(control.enabled == false || control.busy == true)
        case "field":
            FilterField(prompt: control.placeholder ?? "Filter",
                        text: Binding { control.value?.text ?? "" } set: { plugin.header.pick(id, .text($0)) },
                        identifier: identifier)
                .onSubmit { plugin.header.pick(id, control.value ?? .text(""), submit: true) }
                .disabled(control.enabled == false)
        case "text": text.accessibilityIdentifier(identifier)
        case "openWith": openWith.accessibilityIdentifier(identifier)
        default: Spacer(minLength: 0)
        }
    }

    /// An icon button; with a badge or busy, its count after the symbol or a spinner in its place (Git's Pull and
    /// Push).
    @ViewBuilder
    private func button(_ id: String) -> some View {
        let title = control.title ?? "", symbol = control.symbol ?? "questionmark"
        if control.badge == nil, control.busy != true {
            IconButton(symbol: symbol, help: title, size: 22) { plugin.header.pick(id, nil) }
                .foregroundStyle(look.paneButton)
        } else {
            Button { plugin.header.pick(id, nil) } label: {
                HStack(spacing: 2) {
                    if control.busy == true {
                        ProgressView().controlSize(.mini).frame(width: 14)
                    } else {
                        Image(systemName: symbol).font(.system(size: 11)).frame(width: 14)
                    }
                    if let badge = control.badge {
                        Text(badge).font(.system(size: 11).monospacedDigit())
                    }
                }
                .padding(.horizontal, 4)
                .frame(minWidth: 22, minHeight: 22)
            }
            .buttonStyle(ChromeStyle(radius: 5.5))
            .foregroundStyle(look.paneButton)
            .help(title)
            // In the label: XCUITest reads no button's value.
            .accessibilityLabel(control.badge.map { "\(title), \($0)" } ?? title)
        }
    }

    /// An icon button in the accent while on.
    private func toggle(_ id: String) -> some View {
        let isOn = control.value == .bool(true)
        return IconButton(symbol: control.symbol ?? "questionmark", help: control.title ?? "", size: 22) {
            plugin.header.pick(id, .bool(!isOn))
        }
        .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(look.paneButton))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Plain, dim, or a path: its parts with `›` between them, the first dim. Cut in the middle.
    private var text: some View {
        let parts: [String] = switch control.value {
        case let .list(list): list
        case let .text(text): [text]
        default: []
        }
        let chevron = Text(" › ").foregroundStyle(.tertiary)
        let shown = control.style == "path"
            ? parts.enumerated().reduce(Text("")) { line, part in
                let text = part.offset == 0 ? Text(part.element).foregroundStyle(.secondary) : Text(part.element)
                return part.offset == 0 ? text : Text("\(line)\(chevron)\(text)")
            }
            : Text(parts.joined()).foregroundStyle(control.style == "dim" ? .secondary : .primary)
        return shown.fontWeight(.regular).lineLimit(1).truncationMode(.middle)
            .accessibilityValue(parts.joined(separator: " › "))
    }

    /// Open With for the path the page set; none without one. The Mac's apps on This Mac only, the other plugins that
    /// open the file on every machine.
    @ViewBuilder
    private var openWith: some View {
        if let path = control.value?.text, !path.isEmpty {
            let others = Registry.openers(path, options: true).filter { $0.id != plugin.manifest.id }
            if !page.store.machine.isRemote || !others.isEmpty {
                OpenWith(path: path, apps: !page.store.machine.isRemote, plugins: others, pick: plugin.reopen(as:))
            }
        }
    }
}

/// A borderless pop-up: the picked item's title (else the control's), its symbol or a spinner while busy; the picked
/// item checked. A `{ title }` item starts a section, `"-"` is a divider.
private struct HeaderMenu: View {
    let control: PluginManifest.Control
    let header: Header

    var body: some View {
        let items = control.items ?? [], value = control.value?.text
        let shown = items.first { $0.value != nil && $0.value == value }?.title ?? control.title ?? ""
        Menu {
            ForEach(sections(items).indices, id: \.self) { index in
                let (heading, items) = sections(items)[index]
                if let heading {
                    Section(heading) { rows(items, value) }
                } else {
                    rows(items, value)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if control.busy == true {
                    ProgressView().controlSize(.mini)
                } else if let symbol = control.symbol {
                    Image(systemName: symbol)
                }
                Text(shown).lineLimit(1).truncationMode(.middle)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel(control.title ?? "")
        .accessibilityValue(shown)
    }

    /// The items split at each heading.
    private func sections(_ items: [PluginManifest.Item]) -> [(String?, [PluginManifest.Item])] {
        items.reduce(into: [(nil, [])]) { sections, item in
            if item.value == nil, let title = item.title {
                sections.append((title, []))
            } else {
                sections[sections.count - 1].1.append(item)
            }
        }
    }

    @ViewBuilder
    private func label(_ item: PluginManifest.Item, _ pick: String) -> some View {
        if let symbol = item.symbol {
            Label(item.title ?? pick, systemImage: symbol)
        } else {
            Text(item.title ?? pick)
        }
    }

    private func rows(_ items: [PluginManifest.Item], _ value: String?) -> some View {
        ForEach(items.indices, id: \.self) { index in
            let item = items[index], id = control.id ?? ""
            if let pick = item.value {
                if pick == value {
                    Toggle(isOn: Binding { true } set: { _ in header.pick(id, .text(pick)) }) { label(item, pick) }
                } else {
                    Button { header.pick(id, .text(pick)) } label: { label(item, pick) }
                }
            } else {
                Divider()
            }
        }
    }
}

/// Open With, as other editors draw it: the default app's icon opens the file in it; its menu lists that app, then
/// the others that open the file, each with its icon, then the other plugins that open it, whose pick turns the card
/// into theirs.
struct OpenWith: View {
    let path: String
    /// The Mac's apps: on This Mac.
    let apps: Bool
    let plugins: [PluginManifest]
    let pick: (PluginManifest) -> Void

    var body: some View {
        let url = URL(filePath: path)
        Group {
            if apps, let main = NSWorkspace.shared.urlForApplication(toOpen: url) {
                Menu {
                    OpenWithItems(url: url, plugins: plugins, pick: pick)
                } label: {
                    Image(nsImage: OpenWithItems.icon(main))
                } primaryAction: {
                    NSWorkspace.shared.open([url], withApplicationAt: main,
                                            configuration: NSWorkspace.OpenConfiguration())
                }
                .help("Open with \(FileManager.default.displayName(atPath: main.path))")
            } else {
                Menu("Open With") { OpenWithItems(url: apps ? url : nil, plugins: plugins, pick: pick) }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
    }
}

/// Their own view: SwiftUI asks LaunchServices again only when the path changes, not at every render of the card.
private struct OpenWithItems: View {
    /// Nil: no apps (a remote machine's file).
    let url: URL?
    let plugins: [PluginManifest]
    let pick: (PluginManifest) -> Void

    var body: some View {
        if let url {
            let workspace = NSWorkspace.shared, main = workspace.urlForApplication(toOpen: url)
            let others = workspace.urlsForApplications(toOpen: url).filter { $0 != main }
            if let main {
                item(main, url)
                Divider()
            }
            ForEach(others, id: \.self) { item($0, url) }
            if !plugins.isEmpty {
                Divider()
            }
        }
        ForEach(plugins, id: \.id) { plugin in
            Button(plugin.name, systemImage: plugin.icon) { pick(plugin) }
        }
    }

    private func item(_ app: URL, _ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } label: {
            Label {
                Text(FileManager.default.displayName(atPath: app.path))
            } icon: {
                Image(nsImage: Self.icon(app))
            }
        }
    }

    /// The app's icon at menu size: LaunchServices gives it at 32 pt.
    static func icon(_ app: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
