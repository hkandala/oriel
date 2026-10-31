import AppKit
import HerdrKit
import SwiftUI

extension Page {
    /// A plugin pane's card, made on first use; nil for a browser's and every other pane.
    func plugin(_ pane: HostStore.Pane) -> Plugin? {
        guard let terminalID = pane.terminalID, let label = pane.plugin, label.kind != .browser else { return nil }
        return terminals.plugin(pane, label, terminalID: terminalID, store: store)
    }
}

/// The card's content under its header, its kind's page, with the toast at its top.
struct PluginCard: View {
    let plugin: Plugin
    let page: Page
    /// False in an overview tile, which leaves the keyboard to the card.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        WebCardContent(card: plugin.web)
            .padding([.horizontal, .bottom], PaneCard.inset)
            // Over a page that has not drawn yet (a big tree's first listing, a remote file).
            .overlay {
                if !plugin.web.ready {
                    Loading().accessibilityIdentifier("pane.\(plugin.paneID).loading")
                }
            }
            .overlay(alignment: .top) {
                if let toast = plugin.web.toast {
                    ToastView(toast: toast, plugin: plugin).padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: plugin.web.toast == nil)
            // Not in an overview tile: the card's own watch catches up when it shows again.
            .task(id: "\(isEnabled) \(plugin.web.arg)") {
                if isEnabled {
                    await plugin.web.watch()
                }
            }
            // In place of the card that had the keyboard.
            .onAppear {
                if isEnabled, page.hasKeyboard(plugin.paneID) {
                    plugin.web.view.takeKeyboard()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(plugin.kind.rawValue).\(plugin.paneID).card")
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
                plugin.web.toast = nil
                toast.other.action()
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("\(id).other")
            Button(toast.main.title) {
                plugin.web.toast = nil
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

/// The card header's second row: Back and Forward, the page's controls, and for a file Show in File Explorer and
/// Open With (This Mac only) at the right end. It starts at the row's left edge, also in a floating window.
struct PluginToolbar: View {
    let plugin: Plugin
    let page: Page
    @Environment(\.look) private var look

    var body: some View {
        switch plugin.web.page {
        case .diff, .git: GitBar(plugin: plugin, page: page)
        case let shown:
            HStack(spacing: 6) {
                BackForward(plugin: plugin)
                // Each page's own spacer: Preview's controls sit right of it.
                switch shown {
                case .files: FilesBar(plugin: plugin, page: page)
                case .preview: PreviewBar(plugin: plugin)
                case .markdown:
                    MarkdownBar(plugin: plugin)
                    Spacer(minLength: 0)
                default:
                    JumpBar(plugin: plugin)
                    Spacer(minLength: 0)
                }
                if shown != .files {
                    IconButton(symbol: "list.bullet.indent", help: "Show in File Explorer", size: 22) {
                        Task { await plugin.reveal() }
                    }
                    .foregroundStyle(look.paneButton)
                    .accessibilityIdentifier("pane.\(plugin.paneID).reveal")
                    if !page.store.machine.isRemote {
                        OpenWith(path: plugin.web.arg).accessibilityIdentifier("pane.\(plugin.paneID).open-with")
                    }
                }
            }
        }
    }
}

/// Open With (This Mac only), as other editors draw it: the default app's icon opens the file in it; its menu lists
/// that app, then the others that open the file, each with its icon.
private struct OpenWith: View {
    let path: String

    var body: some View {
        let url = URL(filePath: path)
        Group {
            if let main = NSWorkspace.shared.urlForApplication(toOpen: url) {
                Menu {
                    OpenWithItems(url: url)
                } label: {
                    Image(nsImage: OpenWithItems.icon(main))
                } primaryAction: {
                    NSWorkspace.shared.open([url], withApplicationAt: main,
                                            configuration: NSWorkspace.OpenConfiguration())
                }
                .help("Open with \(FileManager.default.displayName(atPath: main.path))")
            } else {
                Menu("Open With") { OpenWithItems(url: url) }
            }
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

/// The app's spinner, once a load takes long enough to see.
private struct Loading: View {
    @State private var shown = false

    var body: some View {
        ProgressView().controlSize(.small).opacity(shown ? 1 : 0)
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                shown = true
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

/// Unsaved edits, after the title in the card's header and the floating window's title row: 7 pt, centered on the
/// title's x-height (a little under the line's middle), as a document window's.
struct DirtyDot: View {
    let paneID: String
    private static let drop = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return (font.ascender + font.descender - font.xHeight) / 2
    }()

    var body: some View {
        Circle().fill(.secondary).frame(width: 7, height: 7)
            .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] - Self.drop }
            .padding(.horizontal, 3)
            .help("Edited")
            .accessibilityElement()
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel("Edited")
            .accessibilityIdentifier("pane.\(paneID).dirty")
    }
}
