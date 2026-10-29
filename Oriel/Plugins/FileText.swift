import AppKit
import HerdrKit
import SwiftUI

/// A file's text that a file or markdown card edits (phase 42's spec, items 1 and 3): the load with its caps, ⌘S
/// checked by hash, the reload on a change on disk, and their toasts.
@MainActor @Observable
final class FileText {
    /// What the editor shows and edits; the card is dirty while it differs from the disk's (an undo back clears it).
    var text = "" {
        didSet {
            if !loading, plugin?.dirty != (text != disk) {
                plugin?.dirty = text != disk
            }
        }
    }

    private(set) var loaded = false
    /// Over the edit cap on a remote machine.
    private(set) var readOnly = false
    /// Why there is no text to show: the read failed, the file is over 16 MB or is not UTF-8 text.
    private(set) var failure: String?
    /// The file card's jump bar: the symbol at the caret.
    var symbol = ""

    /// Weak: the plugin keeps this.
    private(set) weak var plugin: Plugin?
    /// The pane's machine, from `run`.
    @ObservationIgnored private var machine = Machine.thisMac
    /// The disk's text and hash when it was read or saved; the save checks the hash.
    @ObservationIgnored private var disk = ""
    @ObservationIgnored private var hash: String?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var saving = false
    /// The file card's text view, which an overview tile borrows.
    @ObservationIgnored var editor: CodeEditor?

    init(plugin: Plugin) {
        self.plugin = plugin
    }

    var path: String {
        plugin?.label.arg ?? ""
    }

    private var name: String {
        (path as NSString).lastPathComponent
    }

    /// The card's `.task(id: path)`: loads the file, then follows it on disk.
    func run(_ machine: Machine) async {
        self.machine = machine
        let exec = await machine.exec()
        await check(exec)
        for await _ in Files.watch(path, exec: exec) {
            await check(exec)
        }
    }

    /// The disk's file, when it is new: the text, unless it has edits: then a toast asks.
    private func check(_ exec: any Exec) async {
        let known = hash
        do {
            let contents = try await Files.read(path, exec: exec)
            // Not when a save ended meanwhile (the read may be older than it), nor for a path the card left.
            guard contents.hash != hash, hash == known, !saving, !Task.isCancelled else { return }
            guard loaded, plugin?.dirty == true else { return apply(contents) }
            plugin?.toast = Toast(text: "\(name) changed on disk.",
                                  other: ("Reload", { [weak self] in self?.apply(contents) }),
                                  main: ("Keep Mine", { [weak self] in self?.keep(contents) }))
        } catch {
            // A file gone keeps its text, which a save writes again; one grown too large shows the info view, edits
            // or not. ponytail: no toast for that.
            if !loaded || error is FileError {
                failure = FileText.reason(error)
                hash = nil
            }
        }
    }

    /// The edits stay, over the disk's new version (once too large: back to the text).
    private func keep(_ contents: FileContents) {
        hash = contents.hash
        disk = String(validating: contents.data, as: UTF8.self) ?? disk
        failure = nil
    }

    /// ⌘S; nothing for the disk's own text, which a write would only touch (every watcher and build wakes).
    func save() async {
        guard loaded, !readOnly, failure == nil, plugin?.dirty == true else { return }
        await write(replacing: hash)
    }

    /// nil: Overwrite, whatever the disk holds.
    private func write(replacing hash: String?) async {
        // A second ⌘S while one saves would find the first one's hash on disk.
        guard !saving else { return }
        let saved = text
        // Return types a bare line feed: a CRLF file stays CRLF throughout.
        let bytes = saved.range(of: "\r\n") == nil ? saved
            : saved.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        saving = true
        defer { saving = false }
        do {
            self.hash = try await Files.save(Data(bytes.utf8), to: path, replacing: hash, exec: machine.exec())
            disk = saved
            plugin?.toast = nil
            // Edits made while it saved stay unsaved.
            plugin?.dirty = text != saved
        } catch FileError.changed {
            plugin?.toast = Toast(text: "\(name) changed on disk since you opened it.",
                                  other: ("Overwrite", { [weak self] in Task { await self?.write(replacing: nil) } }),
                                  main: ("Reload", { [weak self] in Task { await self?.reload() } }))
        } catch {
            plugin?.toast = Toast(text: "\(name) was not saved: \(FileText.reason(error))", other: ("Cancel", {}),
                                  main: ("Try Again", { [weak self] in Task { await self?.write(replacing: hash) } }))
        }
    }

    private func reload() async {
        if let contents = try? await Files.read(path, exec: machine.exec()) {
            apply(contents)
        }
    }

    /// The file's bytes as the text, clean.
    private func apply(_ contents: FileContents) {
        hash = contents.hash
        plugin?.dirty = false
        plugin?.toast = nil
        // A byte order mark stays in the text, so a save keeps it.
        guard !contents.data.contains(0), let string = String(validating: contents.data, as: UTF8.self) else {
            failure = "Not a text file"
            return
        }
        disk = string
        loading = true
        text = string
        loading = false
        readOnly = machine.isRemote && contents.data.count > Files.remoteEditLimit
        failure = nil
        loaded = true
    }

    /// An error as the card says it.
    static func reason(_ error: any Error) -> String {
        switch error {
        case let FileError.tooLarge(size): "Too large to show (\(size.formatted(.byteCount(style: .file))))"
        case let HerdrError.failed(text): text
        default: error.localizedDescription
        }
    }
}
