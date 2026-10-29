import AppKit
import HerdrKit
import SwiftUI

extension Page {
    /// A plugin pane's card, made on first use; nil for a browser's and every other pane.
    func plugin(_ pane: HostStore.Pane) -> Plugin? {
        guard let terminalID = pane.terminalID, let label = pane.plugin, label.kind != .browser else { return nil }
        return terminals.plugin(pane, label, terminalID: terminalID)
    }
}

/// The card's content under its header, with the toast at its top. Each kind's content is a placeholder the
/// variants replace (phases 43 and 44); a kind's content takes the keyboard on `plugin.wantsKeyboard` and calls
/// `page.terminals.claimed` when it gets it.
struct PluginCard: View {
    let plugin: Plugin
    let page: Page
    /// False in an overview tile, which leaves the keyboard to the card.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            switch plugin.kind {
            case .files: FilesCard(plugin: plugin, page: page)
            default: PluginPlaceholder(plugin: plugin, page: page)
            }
        }
        .overlay(alignment: .top) {
            if let toast = plugin.toast {
                ToastView(toast: toast, plugin: plugin).padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: plugin.toast == nil)
        // In place of the card that had the keyboard.
        .onAppear {
            if isEnabled, page.hasKeyboard(plugin.paneID) {
                plugin.wantsKeyboard = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(plugin.kind.rawValue).\(plugin.paneID).card")
    }
}

/// A kind's content until its variant's replaces it.
private struct PluginPlaceholder: View {
    let plugin: Plugin
    let page: Page
    @State private var text = ""
    @FocusState private var focused: Bool
    /// False in an overview tile.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let id = "\(plugin.kind.rawValue).\(plugin.paneID)"
        VStack(spacing: 8) {
            HStack {
                Spacer()
                // The placeholder's way to `Page.open` (the test's too) until the variants' links replace it.
                Button("Open in New Tab") { Task { await page.open(plugin.kind, arg: plugin.label.arg) } }
                    .accessibilityIdentifier("\(id).open")
            }
            if plugin.kind == .file || plugin.kind == .markdown {
                TextEditor(text: $text).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden)
                    .focused($focused)
                    .onChange(of: text) { plugin.dirty = true }
                    .accessibilityIdentifier("\(id).text")
            } else {
                Image(systemName: plugin.kind.symbol).font(.system(size: 28)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused)
                    .onTapGesture { focused = true }
            }
        }
        .padding([.horizontal, .bottom], PaneCard.inset)
        .onChange(of: plugin.wantsKeyboard, initial: true) {
            if plugin.wantsKeyboard, isEnabled {
                plugin.wantsKeyboard = false
                Task { focused = true }
            }
        }
        .onChange(of: focused) {
            if focused {
                page.terminals.claimed(plugin.terminalID)
            }
        }
    }
}

/// One line and two buttons over the card's top, on glass.
private struct ToastView: View {
    let toast: Toast
    let plugin: Plugin

    var body: some View {
        let id = "pane.\(plugin.paneID).toast"
        HStack(spacing: 10) {
            Text(toast.text).lineLimit(1).accessibilityIdentifier(id)
            Button(toast.other.title) {
                plugin.toast = nil
                toast.other.action()
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("\(id).other")
            Button(toast.main.title) {
                plugin.toast = nil
                toast.main.action()
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("\(id).main")
        }
        .controlSize(.small)
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }
}

/// The card header's second row: the kind's controls, a placeholder the variants replace; Open With for a file on
/// This Mac.
struct PluginToolbar: View {
    let plugin: Plugin
    let page: Page

    var body: some View {
        switch plugin.kind {
        case .files: FilesToolbar(plugin: plugin)
        default: placeholder
        }
    }

    private var placeholder: some View {
        HStack(spacing: 6) {
            Text(plugin.label.arg).foregroundStyle(.secondary).fontWeight(.regular).lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if [.file, .preview, .markdown].contains(plugin.kind), !page.store.machine.isRemote {
                OpenWith(path: plugin.label.arg).accessibilityIdentifier("pane.\(plugin.paneID).open-with")
            }
        }
    }
}

/// Open With ▾ (This Mac only): the default app, then the other apps that open the file.
private struct OpenWith: View {
    let path: String

    var body: some View {
        Menu {
            OpenWithItems(url: URL(filePath: path))
        } label: {
            Text("Open With")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
    }
}

/// Their own view: SwiftUI asks LaunchServices again only when the path changes, not at every render of the card.
private struct OpenWithItems: View {
    let url: URL

    var body: some View {
        let workspace = NSWorkspace.shared, main = workspace.urlForApplication(toOpen: url)
        let others = workspace.urlsForApplications(toOpen: url).filter { $0 != main }
        if let main {
            item(main)
            Divider()
        }
        ForEach(others, id: \.self, content: item)
    }

    private func item(_ app: URL) -> some View {
        Button {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } label: {
            Label {
                Text(FileManager.default.displayName(atPath: app.path))
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
            }
        }
    }
}

/// While a browser or a plugin pane takes the chooser's place, or a browser card is built.
struct PluginLoader: View {
    let kind: PluginKind

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: kind.symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Opening \(kind.name)…").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Opening \(kind.name)")
    }
}

/// A floated plugin pane: its second row under the floating window's title row, then its content.
struct FloatingPlugin: View {
    let plugin: Plugin
    let page: Page

    var body: some View {
        VStack(spacing: 0) {
            PluginToolbar(plugin: plugin, page: page).padding(.horizontal, 11).frame(height: PaneCard.header)
            PluginCard(plugin: plugin, page: page)
        }
    }
}

/// Unsaved edits, after the title in the card's header and the floating window's title row.
struct DirtyDot: View {
    let paneID: String

    var body: some View {
        Circle().fill(.secondary).frame(width: 6, height: 6).padding(.horizontal, 3)
            .accessibilityElement()
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel("Edited")
            .accessibilityIdentifier("pane.\(paneID).dirty")
    }
}
