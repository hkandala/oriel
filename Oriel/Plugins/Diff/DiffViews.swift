import HerdrKit
import SwiftUI

/// The diff card's content: the file list when open, then the diff.
struct DiffContent: View {
    let plugin: Plugin
    let page: Page
    /// False in an overview tile: the card loads and takes the keyboard.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let card = plugin.diff, id = "diff.\(plugin.paneID)"
        HStack(spacing: 0) {
            if card.showsList, !card.files.isEmpty {
                DiffList(card: card, id: id).frame(width: 220)
                Divider()
            }
            DiffHost(card: card)
                .overlay {
                    if let failure = card.failure {
                        message(failure).accessibilityIdentifier("\(id).message")
                    } else if card.loaded, card.files.isEmpty {
                        message("No Changes").accessibilityIdentifier("\(id).message")
                    }
                }
        }
        .task(id: plugin.label.arg) {
            if isEnabled {
                await card.load(plugin, page: page)
            }
        }
        .onChange(of: plugin.wantsKeyboard, initial: true) {
            if plugin.wantsKeyboard, isEnabled {
                plugin.wantsKeyboard = false
                card.view.takeKeyboard()
            }
        }
        .onAppear {
            // The first column is Unified's, or Side by Side's old side.
            for (text, name) in zip(card.view.texts, ["text", "new"]) {
                text.setAccessibilityIdentifier("\(id).\(name)")
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The card's diff view, which the newest host adopts (an overview tile, then the card again), as a terminal.
private struct DiffHost: NSViewRepresentable {
    let card: DiffCard

    func makeNSView(context _: Context) -> TerminalHost.Host {
        let host = TerminalHost.Host()
        host.clipsToBounds = true
        host.addSubview(card.view)
        return host
    }

    func updateNSView(_: TerminalHost.Host, context: Context) {
        card.restyle(context.environment.look)
    }
}

/// The changed files: a click scrolls the diff to one; the file at the diff's top is lit.
private struct DiffList: View {
    let card: DiffCard
    let id: String
    @Environment(\.look) private var look

    var body: some View {
        List(selection: Binding<Int?>(get: { card.current }, set: { file in
            // A file near the end whose header cannot reach the top stays lit.
            file.map(card.view.reveal)
            card.current = file ?? card.current
        })) {
            ForEach(Array(card.files.enumerated()), id: \.offset) { _, file in
                HStack(spacing: 6) {
                    Text(String(file.letter)).foregroundStyle(look.git(file.letter)).fontWeight(.semibold)
                    Text((file.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    DiffCounts(added: file.added, removed: file.removed)
                }
                .help(file.path)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("\(id).list.\(file.path)")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

/// `+n −m`.
private struct DiffCounts: View {
    let added: Int
    let removed: Int
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 4) {
            if added > 0 {
                Text("+\(added)").foregroundStyle(look.finished)
            }
            if removed > 0 {
                Text("−\(removed)").foregroundStyle(look.error)
            }
        }
        .font(.system(size: 11).monospacedDigit())
    }
}

/// A file's header over its row in the diff: fold, the path, `+n −m`, Open File, Viewed.
struct DiffHeader: View {
    let card: DiffCard
    let paneID: String
    let file: Int
    @Environment(\.look) private var look

    var body: some View {
        if card.files.indices.contains(file) {
            let diff = card.files[file], id = "diff.\(paneID).file.\(diff.path)"
            let folder = (diff.path as NSString).deletingLastPathComponent
            HStack(spacing: 8) {
                Button { card.fold(file) } label: {
                    Image(systemName: card.folded.contains(diff.path) ? "chevron.right" : "chevron.down")
                        .frame(width: 12)
                }
                .accessibilityLabel(card.folded.contains(diff.path) ? "Show Changes" : "Hide Changes")
                .accessibilityIdentifier("\(id).fold")
                let before = Text("\(diff.oldPath.map { "\($0) → " } ?? "")\(folder.isEmpty ? "" : folder + "/")")
                let name = Text((diff.path as NSString).lastPathComponent).fontWeight(.semibold)
                Text("\(before.foregroundStyle(.secondary))\(name)")
                Spacer(minLength: 8)
                DiffCounts(added: diff.added, removed: diff.removed)
                Button("Open File", systemImage: "arrow.up.forward.square") { card.open(diff) }
                    .labelStyle(.iconOnly).help("Open File").disabled(diff.letter == "D")
                    .accessibilityIdentifier("\(id).open")
                Toggle("Viewed", isOn: Binding(get: { card.isViewed(diff) }, set: { card.markViewed(file, $0) }))
                    .toggleStyle(.checkbox).accessibilityIdentifier("\(id).viewed")
            }
            .lineLimit(1).truncationMode(.head)
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The text scrolls under a pinned header, and a glass card has no opaque color.
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
        }
    }
}

/// Row 2: the source, the files' counts, Unified | Side by Side, the file list, previous and next change.
struct DiffToolbar: View {
    let plugin: Plugin
    let page: Page
    @Environment(\.look) private var look

    var body: some View {
        let card = plugin.diff, id = "pane.\(plugin.paneID).diff", (root, source) = plugin.label.diff
        let picked = card.commits.first { $0.hash.hasPrefix(source) }?.hash ?? source
        HStack(spacing: 6) {
            Picker("Source", selection: Binding(get: { picked }, set: { choose($0, root: root) })) {
                Text("Uncommitted").tag("uncommitted")
                Divider()
                if picked != "uncommitted", !card.commits.contains(where: { $0.hash == picked }) {
                    Text(String(picked.prefix(7))).tag(picked)
                }
                ForEach(card.commits, id: \.hash) { commit in
                    Text("\(commit.hash.prefix(7)) \(commit.subject)").tag(commit.hash)
                }
            }
            // Not as wide as the longest subject.
            .labelsHidden().frame(maxWidth: 240).accessibilityIdentifier("\(id).source")
            if !card.files.isEmpty {
                let files = card.files
                Text("\(files.count) \(files.count == 1 ? "file" : "files")").foregroundStyle(.secondary)
                DiffCounts(added: files.reduce(0) { $0 + $1.added }, removed: files.reduce(0) { $0 + $1.removed })
            }
            Spacer(minLength: 0)
            Picker("Layout", selection: Binding(get: { card.sideBySide }, set: { card.sideBySide = $0 })) {
                Text("Unified").tag(false)
                Text("Side by Side").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().accessibilityIdentifier("\(id).layout")
            Group {
                Button("File List", systemImage: "sidebar.left") { card.showsList.toggle() }
                    .accessibilityIdentifier("\(id).file-list")
                Button("Previous Change", systemImage: "chevron.up") { card.view.step(-1) }
                    .accessibilityIdentifier("\(id).previous")
                Button("Next Change", systemImage: "chevron.down") { card.view.step(1) }
                    .accessibilityIdentifier("\(id).next")
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(look.paneButton)
        }
        .fontWeight(.regular)
    }

    /// A new source renames the pane's label; the snapshot after it loads it.
    private func choose(_ source: String, root: String) {
        let label = PaneLabel(plugin: plugin.label.plugin, iid: plugin.label.iid, arg: "\(root) \(source)")
        Task { await page.store.rename(pane: plugin.paneID, label: label.text) }
    }
}
