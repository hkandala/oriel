import HerdrKit
import SwiftUI

/// A Files card: the tree of its root, and the Git section at its bottom when the root is a repository's root.
struct FilesCard: View {
    let plugin: Plugin
    let page: Page
    @Environment(\.look) private var look
    /// False in an overview tile, which borrows the tree and leaves the runs and the keyboard to the card.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let tree = plugin.tree, id = "files.\(plugin.paneID)"
        let files = TreeHost(view: tree.scroll)
            .overlay {
                if let message = tree.failure ?? (tree.noMatches ? "No matching files" : nil) {
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                        .accessibilityIdentifier("\(id).message")
                }
            }
        let git = GitSection(tree: tree, id: id) { page.terminals.claimed(plugin.terminalID) }
        Group {
            if tree.repo == nil {
                files
            } else if tree.showsGit {
                // The user drags the split (it starts half and half).
                VSplitView {
                    files.frame(minHeight: 60)
                    git.frame(minHeight: 120)
                }
            } else {
                VStack(spacing: 0) {
                    files
                    git
                }
            }
        }
        .task(id: plugin.label.arg) {
            if isEnabled {
                await tree.run(plugin.label.arg, page: page)
            }
        }
        .onChange(of: [look.dark, look.contrast], initial: true) { tree.look = look }
        .onChange(of: plugin.wantsKeyboard, initial: true) {
            if plugin.wantsKeyboard, isEnabled {
                tree.outline.takeKeyboard(plugin)
            }
        }
    }
}

/// The tree's scroll view, which the tree keeps: the newest host adopts it, as a terminal's (an overview tile borrows
/// it, the card takes it back).
private struct TreeHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context _: Context) -> TerminalHost.Host {
        let host = TerminalHost.Host()
        host.clipsToBounds = true
        host.addSubview(view)
        return host
    }

    func updateNSView(_: TerminalHost.Host, context _: Context) {}
}

/// The card header's second row: the filter and Collapse All.
struct FilesToolbar: View {
    let plugin: Plugin
    @Environment(\.look) private var look

    var body: some View {
        @Bindable var tree = plugin.tree
        HStack(spacing: 6) {
            FilterField(prompt: "Filter", text: $tree.filter, identifier: "pane.\(plugin.paneID).filter")
            IconButton(symbol: "arrow.down.right.and.arrow.up.left", help: "Collapse All", size: 22,
                       action: tree.collapseAll)
                .foregroundStyle(look.paneButton)
                .accessibilityIdentifier("pane.\(plugin.paneID).collapse")
        }
    }
}

/// VS Code's place for git, collapsed at first: the changed files, then the last 100 commits with their graph.
/// Double-click or ⌘-click opens the diff at that file, or of that commit.
private struct GitSection: View {
    let tree: FileTree
    let id: String
    let claim: () -> Void
    @State private var selection: Pick?

    private enum Pick: Hashable {
        case change(String), commit(String)
    }

    @FocusState private var focused: Bool
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button { tree.showsGit.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(tree.showsGit ? 90 : 0)).foregroundStyle(.tertiary)
                    Text("Git").fontWeight(.semibold).foregroundStyle(.secondary)
                    Text(tree.branch).foregroundStyle(.tertiary).lineLimit(1)
                    Spacer()
                    if !tree.changes.isEmpty {
                        Text("\(tree.changes.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.system(size: 11))
                .padding(.horizontal, 6).frame(height: 28).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(id).git")
            .accessibilityValue(tree.showsGit ? "Expanded" : "Collapsed")
            if tree.showsGit {
                list
            }
        }
    }

    private var list: some View {
        // One width for every row's lanes.
        let lanes = tree.history.map { [$0.row.lane] + $0.row.parents + $0.row.children + $0.row.through }
            .joined().max().map { $0 + 1 } ?? 1
        // Headers as rows, not sections: a plain list's section headers are opaque bands. Plain rows touch, so the
        // lanes run on from row to row.
        return List(selection: $selection) {
            header("Changes")
            ForEach(tree.changes, id: \.path) { change in
                ChangeRow(change: change).tag(Pick.change(change.path)).listRowSeparator(.hidden)
                    .accessibilityIdentifier("\(id).change.\(change.path)")
            }
            header("History").padding(.top, 6)
            ForEach(tree.history, id: \.commit.hash) { commit, row in
                HistoryRow(commit: commit, row: row, lanes: lanes).tag(Pick.commit(commit.hash))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                    .accessibilityIdentifier("\(id).commit.\(commit.hash)")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 22)
        .contextMenu(forSelectionType: Pick.self, menu: { _ in }, primaryAction: { $0.first.map(open) })
        .focused($focused)
        // ⌘-click: the list selects (or, on the selected row, deselects) the row.
        .onChange(of: selection) { old, new in
            if NSEvent.modifierFlags.contains(.command), let pick = new ?? old {
                open(pick)
            }
        }
        .onChange(of: focused) {
            if focused {
                claim()
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .selectionDisabled().listRowSeparator(.hidden)
    }

    private func open(_ pick: Pick) {
        switch pick {
        case let .change(path): tree.openDiff("uncommitted", at: path)
        case let .commit(hash): tree.openDiff(hash)
        }
    }
}

private struct ChangeRow: View {
    let change: Git.Change
    @Environment(\.look) private var look

    var body: some View {
        let path = change.path as NSString
        HStack(spacing: 6) {
            Text(String(change.letter)).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(look.git(change.letter)).frame(width: 12)
            Text(path.lastPathComponent).lineLimit(1)
            Text(path.deletingLastPathComponent).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(change.path)
        .accessibilityValue(String(change.letter))
    }
}

/// A commit: its lanes, subject and short hash; the author and date on hover.
private struct HistoryRow: View {
    static let lane: CGFloat = 10
    let commit: Git.Commit
    let row: Git.GraphRow
    let lanes: Int
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 6) {
            Canvas(rendersAsynchronously: false, renderer: draw).frame(width: Self.lane * CGFloat(lanes), height: 22)
            Text(commit.subject).lineLimit(1)
            Spacer(minLength: 4)
            Text(commit.hash.prefix(7)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .help("\(commit.author), \(commit.date.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(commit.subject)
    }

    /// Lines from the children above into the dot, from the dot to the parents below, and straight past it.
    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let mid = size.height / 2, colors = [look.working, look.needsYou, look.finished, look.error]
        func x(_ lane: Int) -> CGFloat {
            Self.lane * (CGFloat(lane) + 0.5)
        }
        func line(_ start: CGPoint, _ end: CGPoint, _ lane: Int) {
            let bend = (start.y + end.y) / 2
            var path = Path()
            path.move(to: start)
            path.addCurve(to: end, control1: CGPoint(x: start.x, y: bend), control2: CGPoint(x: end.x, y: bend))
            context.stroke(path, with: .color(colors[lane % colors.count]), lineWidth: 1.5)
        }
        for lane in row.through {
            line(CGPoint(x: x(lane), y: 0), CGPoint(x: x(lane), y: size.height), lane)
        }
        for lane in row.children {
            line(CGPoint(x: x(lane), y: 0), CGPoint(x: x(row.lane), y: mid), lane)
        }
        for lane in row.parents {
            line(CGPoint(x: x(row.lane), y: mid), CGPoint(x: x(lane), y: size.height), lane)
        }
        let dot = CGRect(x: x(row.lane) - 3.5, y: mid - 3.5, width: 7, height: 7)
        context.fill(Path(ellipseIn: dot), with: .color(colors[row.lane % colors.count]))
    }
}
