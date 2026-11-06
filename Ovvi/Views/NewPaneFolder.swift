import AppKit
import HerdrKit
import SwiftUI

/// New Pane's folder line under the list (ui/new-pane#folder): "Opens in ~/code/ovvi", the folder its pick starts in.
/// A click on the path, ⌘L or Tab makes it a field with the whole path selected, as File Explorer's path bar: Return
/// takes a folder of the pane's machine (`~` and relative paths too), and one that is not there shows an error and
/// keeps the old folder, under the field; Esc puts it back. The icon before the path opens the system's folder
/// panel, on This Mac only, as the path bar's.
struct NewPaneFolder: View {
    let chooser: Chooser
    let page: Page
    let cardID: String
    /// The field's height and the error's under it: the list stays put as the line turns into the field.
    static let height: CGFloat = 44
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.look) private var look

    var body: some View {
        let store = page.store, remote = store.machine.isRemote
        // Not on a stand-in: herdr's pane, as it shows, gives its terminal the keyboard and would close the field.
        let editing = chooser.editing && store.pane(cardID) != nil
        if let folder = chooser.folder ?? store.pane(cardID)?.cwd ?? chooser.cwd {
            VStack(spacing: 4) {
                // The icon is one view in both looks: a click on it as the field lets go still lands.
                HStack(spacing: 6) {
                    if !remote {
                        choose(folder).foregroundStyle(editing ? AnyShapeStyle(.secondary) : dim)
                    }
                    if editing {
                        field(folder)
                    } else {
                        line(folder, remote: remote, machine: store.machine.name)
                    }
                }
                .frame(maxWidth: editing ? .infinity : nil)
                // The path bar's capsule while editing, its padding at rest too.
                .fieldCapsule(fill: editing)
                .overlay { Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5).opacity(editing ? 1 : 0) }
                .font(.system(size: 12))
                .frame(height: 26)
                // Its room kept, so the list does not move.
                Text(error ?? "").font(.system(size: 11)).foregroundStyle(look.error).lineLimit(1).frame(height: 14)
                    .accessibilityIdentifier("pane.\(cardID).chooser.folder.error")
                    .accessibilityHidden(error == nil)
            }
            .onChange(of: chooser.editing, initial: true) {
                if chooser.editing, page.store.pane(cardID) == nil {
                    chooser.editing = false
                }
                draft = folder
                error = nil
            }
            .onChange(of: draft) { error = nil }
            .onChange(of: focused) {
                if focused {
                    // Selected whole once the field has the keyboard, as the path bar.
                    DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil) }
                } else {
                    // A click elsewhere.
                    chooser.editing = false
                }
            }
            // Tab or ⌘L while no line showed (a stand-in, a short card) leaves no field for later.
            .onAppear { chooser.editing = false }
            .onDisappear { chooser.editing = false }
        }
    }

    private var dim: AnyShapeStyle {
        look.contrast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }

    private func line(_ folder: String, remote: Bool, machine: String) -> some View {
        HStack(spacing: 4) {
            Text("Opens in").foregroundStyle(dim).accessibilityHidden(true)
            Button {
                if let pane = page.store.pane(cardID) {
                    page.go(to: pane)
                }
                chooser.editing = true
            } label: {
                Text(PathField.short(folder, remote: remote)).fontWeight(.medium).lineLimit(1).truncationMode(.head)
            }
            .buttonStyle(.plain)
            // Grey as "Opens in" until it is a field.
            .foregroundStyle(dim)
            .accessibilityLabel("Opens in")
            .accessibilityValue(folder)
            .accessibilityIdentifier("pane.\(cardID).chooser.folder")
            if remote {
                Text("on \(machine)").foregroundStyle(dim).lineLimit(1)
            }
        }
    }

    private func field(_ folder: String) -> some View {
        TextField("Folder", text: $draft)
            .focused($focused)
            .accessibilityIdentifier("pane.\(cardID).chooser.folder.field")
            .onSubmit { submit(from: folder) }
            .onExitCommand(perform: stop)
            .focusEffectDisabled()
            .focusSoon($focused)
    }

    /// Choose Folder…: the system's folder panel at the folder.
    private func choose(_ folder: String) -> some View {
        Button {
            guard let window = NSApp.keyWindow else { return }
            Task {
                if let path = await page.store.chooseFolder(from: folder, in: window), path != folder {
                    chooser.folder = path
                }
                if chooser.editing {
                    stop()
                }
            }
        } label: {
            Image(systemName: "folder")
        }
        .buttonStyle(.plain)
        .help("Choose Folder…")
        .accessibilityLabel("Choose Folder…")
        .accessibilityIdentifier("pane.\(cardID).chooser.folder.choose")
    }

    /// The typed folder as the machine resolves it, from the shown one; an empty field changes nothing.
    private func submit(from folder: String) {
        let typed = draft.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return stop() }
        Task {
            let path = await page.store.folder(typed, from: folder)
            // Typed on, or left, meanwhile.
            guard chooser.editing, draft.trimmingCharacters(in: .whitespaces) == typed else { return }
            if let path {
                // The same folder types no `cd`.
                if path != folder {
                    chooser.folder = path
                }
                stop()
            } else {
                error = "No folder \(typed)"
            }
        }
    }

    /// The line again, and the keyboard back to the card's chooser.
    private func stop() {
        chooser.editing = false
        if let pane = page.store.pane(cardID) {
            page.go(to: pane)
        }
    }
}

extension HostStore {
    /// Choose Folder… of a plugin (`pick.folder`) and of New Pane's folder line: This Mac's folder panel at `start`; a
    /// remote machine's folder field (`folder(_:from:)`), with a notice for a path that is no folder. Nil when
    /// cancelled.
    func chooseFolder(from start: String, in window: NSWindow) async -> String? {
        if !machine.isRemote {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.directoryURL = URL(filePath: start)
            guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return nil }
            let path = url.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        let alert = NSAlert()
        alert.messageText = "Go to Folder"
        alert.informativeText = "A folder on \(machine.name)"
        let field = NSTextField(string: start)
        field.frame.size.width = 280
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return nil }
        guard let path = await folder(field.stringValue, from: start) else {
            await show(Notice(text: "No folder \(field.stringValue)", tone: .warning))
            return nil
        }
        return path
    }

    /// The folder a typed path names on the machine, as its shell resolves it: `~` its home folder, a relative path
    /// from `base`, links resolved. Nil when it is no folder there.
    func folder(_ typed: String, from base: String) async -> String? {
        let script = #"cd -- "$2" 2>/dev/null; case $1 in "~"|"~/"*) set -- "$HOME${1#\~}";; esac; "#
            + #"cd -- "$1" 2>/dev/null && pwd -P"#
        guard let channel = try? await machine.exec().run(["sh", "-c", script, "sh", typed, base]) else { return nil }
        channel.closeInput()
        let path = await channel.lines.reduce("", +)
        return await channel.exit().status == 0 && path.hasPrefix("/") ? path : nil
    }
}
