import AppKit
import HerdrKit
import SwiftUI

/// A file's text that a file or markdown card edits (phase 42's spec, items 1 and 3): the load with its caps, ⌘S
/// checked by hash, the reload on a change on disk, and their toasts.
@MainActor @Observable
final class FileText {
    /// What the editor shows and edits; a change from the editor marks the card dirty.
    var text = "" {
        didSet {
            if !loading, plugin?.dirty == false {
                plugin?.dirty = true
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
    private let machine: Machine
    /// The disk's hash when the text was read or saved; the save checks it.
    @ObservationIgnored private var hash: String?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var saving = false
    /// The file card's text view, which an overview tile borrows.
    @ObservationIgnored var editor: CodeEditor?

    init(plugin: Plugin, machine: Machine) {
        self.plugin = plugin
        self.machine = machine
    }

    var path: String {
        plugin?.label.arg ?? ""
    }

    private var name: String {
        (path as NSString).lastPathComponent
    }

    /// The card's `.task(id: path)`: loads the file, then follows it on disk.
    func run() async {
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
            // Not when a save ended meanwhile: the read may be older than it.
            guard contents.hash != hash, hash == known, !saving else { return }
            guard loaded, plugin?.dirty == true else { return apply(contents) }
            plugin?.toast = Toast(text: "\(name) changed on disk.",
                                  other: ("Reload", { [weak self] in self?.apply(contents) }),
                                  main: ("Keep Mine", { [weak self] in self?.hash = contents.hash }))
        } catch {
            // A file gone keeps its text, which a save writes again; one grown too large shows the info view.
            if !loaded || error is FileError {
                failure = FileText.reason(error)
                hash = nil
            }
        }
    }

    /// ⌘S.
    func save() async {
        guard loaded, !readOnly, failure == nil else { return }
        await write(replacing: hash)
    }

    /// nil: Overwrite, whatever the disk holds.
    private func write(replacing hash: String?) async {
        // A second ⌘S while one saves would find the first one's hash on disk.
        guard !saving else { return }
        let saved = text
        saving = true
        defer { saving = false }
        do {
            self.hash = try await Files.save(Data(saved.utf8), to: path, replacing: hash, exec: machine.exec())
            plugin?.toast = nil
            // Edits made while it saved stay unsaved.
            if text == saved {
                plugin?.dirty = false
            }
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
        // A byte order mark stays in the text, so a save keeps it.
        guard !contents.data.contains(0), let string = String(validating: contents.data, as: UTF8.self) else {
            failure = "Not a text file"
            return
        }
        loading = true
        text = string
        loading = false
        readOnly = machine.isRemote && contents.data.count > Files.remoteEditLimit
        failure = nil
        loaded = true
        plugin?.dirty = false
        plugin?.toast = nil
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

extension Page {
    /// The card's file text, made once.
    func fileText(_ plugin: Plugin) -> FileText {
        if let file = plugin.file {
            return file
        }
        let file = FileText(plugin: plugin, machine: store.machine)
        plugin.file = file
        return file
    }
}
