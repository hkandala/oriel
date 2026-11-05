import Foundation
import HerdrKit

/// Writes: each is one multiplexer action, then a snapshot read.
extension HostStore {
    /// A new tab in the workspace, in `cwd` or the pane's directory, asked now: a `cd` sends no event, so the
    /// snapshot's cwd may be old. Its pane.
    func newTab(in workspaceID: String, cwd: String?, of paneID: String? = nil) async -> HerdrKit.Pane? {
        var cwd = cwd
        if let paneID, let fresh = try? await client?.pane(paneID).cwd {
            cwd = fresh
        }
        var created: HerdrKit.Pane?
        await write { created = try await $0.newTab(workspace: workspaceID, cwd: cwd ?? "~") }
        return created
    }

    /// In home by default (herdr reads `~` as the machine's home): a server launchd started has another cwd. Its
    /// first pane, which asks what it runs.
    func newWorkspace(label: String? = nil, cwd: String = "~") async -> HerdrKit.Pane? {
        var created: HerdrKit.Pane?
        // Before the snapshot that shows it, so its first frame has the chooser.
        await write {
            created = try await $0.newWorkspace(label: label, cwd: cwd)
            choose(created)
        }
        return created
    }

    /// Trimmed; nothing when empty or the same.
    func rename(tab tabID: String, label: String) async {
        let label = label.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty,
              label != workspaces.flatMap(\.tabs).first(where: { $0.id == tabID })?.label else { return }
        await write { try await $0.rename(tab: tabID, label: label) }
    }

    /// Trimmed; nothing when empty or the same.
    func rename(workspace workspaceID: String, label: String) async {
        let label = label.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label != workspaces.first(where: { $0.id == workspaceID })?.label else { return }
        await write { try await $0.rename(workspace: workspaceID, label: label) }
    }

    /// One write. No focus change; the snapshot after it draws the result. Whether it went through.
    @discardableResult
    func write(_ action: (any Multiplexer) async throws -> Void) async -> Bool {
        guard client != nil else { return false }
        do {
            try await request { client in
                notice = nil
                try await action(client)
            }
            return true
        } catch {
            Task { await show(Notice(text: error.localizedDescription)) }
            return false
        }
    }

    /// One write after the ones before it, then a snapshot read, also after a failure: part of it may have happened
    /// (Close Other Tabs). Its error goes to the caller (an agent's request answers it).
    func request<T>(_ action: (any Multiplexer) async throws -> T) async throws -> T {
        guard let client else { throw HerdrError.failed("Ovvi is not connected to herdr session \(session)") }
        await writes.enter()
        let result: Result<T, Error>
        do {
            result = try await .success(action(client))
        } catch {
            result = .failure(error)
        }
        writes.leave()
        await client.refresh()
        return try result.get()
    }

    /// A notice for a few seconds (4 by default), unless a newer one replaced it.
    func show(_ new: Notice, for time: Duration = .seconds(4)) async {
        notice = new
        try? await Task.sleep(for: time)
        if notice?.id == new.id {
            notice = nil
        }
    }
}
