import AppKit
import HerdrKit
import SwiftUI

extension Page {
    /// A plugin pane's card, made on first use; nil for a browser's and every other pane.
    func plugin(_ pane: HostStore.Pane) -> Plugin? {
        guard let terminalID = pane.terminalID, let label = pane.plugin else { return nil }
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
            .overlay {
                if let failure = plugin.web.bridge?.failure {
                    PluginFailure(plugin: plugin, title: failure.title, text: failure.text)
                }
            }
            .animation(.easeOut(duration: 0.15), value: plugin.web.toast == nil)
            // Not in an overview tile: the card's own watch catches up when it shows again. A plugin's page has its
            // own (`Bridge.shown`).
            .task(id: "\(isEnabled) \(plugin.web.arg)") {
                if isEnabled, plugin.web.page != .main {
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
            .accessibilityIdentifier("\(plugin.manifest.id).\(plugin.paneID).card")
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
            if let other = toast.other {
                Button(other.title) {
                    plugin.web.toast = nil
                    other.action()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("\(id).other")
            }
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
        case .main: PluginHeader(plugin: plugin, page: page)
        case .diff: DiffToolbar(plugin: plugin)
        case .git: GitBar(plugin: plugin)
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
                    // The Mac's apps on This Mac only; the other plugins that open the file on every machine.
                    let others = Registry.openers(plugin.web.arg, options: true).filter { $0.id != plugin.manifest.id }
                    if !page.store.machine.isRemote || !others.isEmpty {
                        OpenWith(path: plugin.web.arg, apps: !page.store.machine.isRemote, plugins: others,
                                 pick: plugin.reopen(as:))
                            .accessibilityIdentifier("pane.\(plugin.paneID).open-with")
                    }
                }
            }
        }
    }
}

/// A plugin page that stopped (its `main` threw) or cannot run (its API is too new): the title, the error's first
/// lines, and Reload.
private struct PluginFailure: View {
    let plugin: Plugin
    let title: String
    let text: String
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: plugin.manifest.icon).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .semibold))
                .accessibilityIdentifier("pane.\(plugin.paneID).failure")
            Text(text).font(.system(size: 12).monospaced()).foregroundStyle(.secondary).lineLimit(6)
                .multilineTextAlignment(.center).textSelection(.enabled)
            if plugin.manifest.api <= Bridge.api {
                Button("Reload") { plugin.web.reload() }
                    .buttonStyle(.glass).controlSize(.small).padding(.top, 4)
                    .accessibilityIdentifier("pane.\(plugin.paneID).reload")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Over what the page drew before it stopped.
        .background(look.cardSolid)
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
    let plugin: PluginManifest

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: plugin.icon).font(.system(size: 28)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Opening \(plugin.name)…").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Opening \(plugin.name)")
    }
}

/// The card of a label naming a plugin not on this Mac (removed, or from another Mac): the plugin id and the
/// argument. The label stays, so the card comes back with the plugin. A plugin with no page yet shows its loader.
struct MissingPlugin: View {
    let label: PaneLabel
    let pane: HostStore.Pane
    let page: Page

    var body: some View {
        if let plugin = label.manifest {
            PluginLoader(plugin: plugin)
        } else {
            missing
        }
    }

    private var missing: some View {
        VStack(spacing: 12) {
            Image(systemName: Registry.missing).font(.system(size: 28)).foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("\(label.plugin) is not on this Mac").font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier("pane.\(pane.id).missing")
                if !label.arg.isEmpty {
                    Text(label.arg).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        .truncationMode(.middle).textSelection(.enabled)
                }
            }
            .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Show Placeholder") { pane.placeholder = true }
                    .accessibilityIdentifier("pane.\(pane.id).show-placeholder")
                Button("Close Pane") { page.closePane(pane) }
                    .accessibilityIdentifier("pane.\(pane.id).close-missing")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A floated plugin pane: its second row under the floating window's title row, then its content.
struct FloatingPlugin: View {
    let plugin: Plugin
    let page: Page

    var body: some View {
        VStack(spacing: 0) {
            // A plugin with no header and no Back and Forward has no row, as in a pane.
            if plugin.manifest.hasRow(plugin.web.page) {
                PluginToolbar(plugin: plugin, page: page).padding(.horizontal, 11).frame(height: PaneCard.header)
            }
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
