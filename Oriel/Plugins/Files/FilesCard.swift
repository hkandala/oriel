import AppKit
import HerdrKit
import SwiftUI

/// The File Explorer home's second row: the root as a path control, the filter, which the page runs over every path
/// of the root, and Collapse All.
struct FilesBar: View {
    let plugin: Plugin
    let page: Page
    /// A remote machine's folder field.
    @State private var asking = false
    @State private var typed = ""

    var body: some View {
        @Bindable var card = plugin.web
        let id = "pane.\(plugin.paneID)"
        HStack(spacing: 6) {
            root(id)
            FilterField(prompt: "Filter", text: $card.filter, identifier: "\(id).filter")
            IconButton(symbol: "rectangle.compress.vertical", help: "Collapse All", size: 22) {
                card.send(["op": "collapse"])
            }
            .accessibilityIdentifier("\(id).collapse")
        }
        .onChange(of: card.filter) { card.send(["op": "filter", "text": card.filter]) }
        .alert("Go to Folder", isPresented: $asking) {
            TextField("Path", text: $typed)
            Button("Go") { Task { await go(typed) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A folder on \(page.store.machine.name)")
        }
    }

    /// The root's name; its menu lists the folders above it, nearest first, and Choose Folder….
    private func root(_ id: String) -> some View {
        let path = plugin.web.arg.count > 1 ? String(plugin.web.arg.dropLast()) : plugin.web.arg
        // `/` is its own parent.
        let parents = path == "/" ? [] : Array(sequence(first: (path as NSString).deletingLastPathComponent) {
            $0 == "/" ? nil : ($0 as NSString).deletingLastPathComponent
        })
        return Menu {
            ForEach(parents, id: \.self) { folder in
                Button {
                    plugin.go(folder == "/" ? "/" : folder + "/")
                } label: {
                    Label(folder == "/" ? "/" : (folder as NSString).lastPathComponent, systemImage: "folder")
                }
            }
            Divider()
            Button("Choose Folder…") { choose(path) }
        } label: {
            Label((path as NSString).lastPathComponent, systemImage: "folder")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .frame(maxWidth: 200)
        .fixedSize()
        .accessibilityIdentifier("\(id).root")
    }

    /// This Mac's folder panel; a remote machine's folder field.
    private func choose(_ path: String) {
        guard !page.store.machine.isRemote, let window = NSApp.keyWindow else {
            typed = path
            asking = true
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(filePath: path)
        Task {
            guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
            let folder = url.path(percentEncoded: false)
            plugin.go(folder.hasSuffix("/") ? folder : folder + "/")
        }
    }

    /// A typed folder, `~` as the home folder, as the machine resolves it; else a notice.
    private func go(_ path: String) async {
        let script = #"case $1 in "~"*) set -- "$HOME${1#\~}";; esac; cd "$1" 2>/dev/null && pwd -P"#
        var folder = ""
        if let channel = try? await page.store.machine.exec().run(["sh", "-c", script, "sh", path]) {
            channel.closeInput()
            for await line in channel.lines {
                folder += line
            }
            folder = await channel.exit().status == 0 ? folder : ""
        }
        guard folder.hasPrefix("/") else {
            await page.store.show(Notice(text: "No folder \(path)", tone: .warning))
            return
        }
        plugin.go(folder == "/" ? "/" : folder + "/")
    }
}

extension WebCard {
    /// The File Explorer home's asks (`web/src/files.ts`), from the root in the card's argument: a folder's entries,
    /// every path for the filter, and the repository's changes for the letters when the root is a repository's; and
    /// its report that the filter ended. The other pages' messages come first (`answer`).
    func files(_ message: [String: Any]) async -> (Any?, String?) {
        let ask = message["op"] as? String
        guard ask != "filter" else {
            filter = message["text"] as? String ?? ""
            return (nil, nil)
        }
        guard ["list", "paths", "git"].contains(ask) else { return (nil, "Unknown message") }
        guard let exec = await store?.machine.exec() else { return (nil, "Closed") }
        // The argument is a folder's, with its `/`.
        let arg = arg.count > 1 && arg.hasSuffix("/") ? String(arg.dropLast()) : arg
        do {
            switch ask {
            case "list":
                // The repository first, so the first listing dims what git ignores.
                if repo?.root != arg {
                    repo = await (arg, gitRoot(arg, exec))
                }
                let entries = try await Files.list(message["path"] as? String ?? arg, repo: repo?.path, exec: exec)
                return (entries.map { ["name": $0.name, "folder": $0.isFolder, "ignored": $0.ignored] }, nil)
            case "paths":
                return try await (Files.paths(arg, repo: repo?.path, exec: exec), nil)
            default:
                repo = await (arg, gitRoot(arg, exec))
                guard repo?.path != nil else { return ([] as [Any], nil) }
                return try await (Git.status(arg, exec: exec).map { ["letter": String($0.letter), "path": $0.path] },
                                  nil)
            }
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// The root when it is a repository's root and git runs. A root inside a repository but not its root shows no
    /// git: git's paths are from the repository's root.
    private func gitRoot(_ root: String, _ exec: any Exec) async -> String? {
        guard await store?.gitRuns() == true else { return nil }
        return await Git.root(root, exec: exec).flatMap { $0 == root ? $0 : nil }
    }
}
