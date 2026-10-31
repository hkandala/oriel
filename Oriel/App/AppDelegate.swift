import AppKit
import HerdrKit
import SwiftUI
import UserNotifications

/// The notification delegate (set at launch, so a click that starts the app is not lost) and the Dock menu.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set from macOS's decode of the restorable state until launch ends: a restored window's scene storage comes
    /// back a moment after it first shows.
    static var restoring = false
    /// The windows macOS restored in full screen (it does so before launch ends); each leaves it once it shows.
    static var restoredFullScreen: Set<ObjectIdentifier> = []

    func application(_: NSApplication, didDecodeRestorableState _: NSCoder) {
        Self.restoring = true
    }

    func applicationDidFinishLaunching(_: Notification) {
        Self.restoring = false
        Self.restoredFullScreen = Set(NSApp.windows.filter { $0.styleMask.contains(.fullScreen) }
            .map(ObjectIdentifier.init))
        PluginBuilds.writeTypes()
        Task { await DefaultPlugins.shared.install() }
    }

    /// Oriel's marks on the panes it shows go first (talking-to-herdr#float-requests).
    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await HostStore.unmarkAll()
            app.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Each remote machine's master ends with the app (machines#macos).
    func applicationWillTerminate(_: Notification) {
        Machine.disconnectAll()
    }

    func applicationWillFinishLaunching(_: Notification) {
        // Windows and their pages come back after a normal quit too, whatever the system setting says. A session
        // start waits 10 s for its server (`-startTimeout`).
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true, "startTimeout": 10])
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // macOS asks the user once; later calls answer at once. The Dock badge shows only with `.badge` allowed.
        center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
        // SwiftUI takes the `oriel://` URLs for its scenes, which take none (`handlesExternalEvents`): it dropped
        // them (on CI).
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor, reply _: NSAppleEventDescriptor) {
        if let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue.flatMap(URL.init) {
            application(NSApp, open: [url])
        }
    }

    /// A row per pane that needs you or finished, each session once over every window, then New Tab.
    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for store in HostStore.all {
            for pane in store.panes {
                guard let state = pane.state, state >= .finishedUnseen else { continue }
                let workspace = store.workspace(of: pane.tabID)?.label ?? ""
                let item = NSMenuItem(
                    title: "\(pane.agentName ?? "agent") \(state.word) · \(store.label) · \(workspace)",
                    action: #selector(pick),
                    keyEquivalent: "",
                )
                item.target = self
                item.representedObject = Notifications.id(pane, of: store)
                menu.addItem(item)
            }
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "").target = self
        return menu
    }

    /// `oriel://` URLs, and folders dropped on the Dock icon (WindowPages). With no window (one that starts the app
    /// opens none: `handlesExternalEvents(matching: [])`), a new one takes them once its page is live.
    func application(_: NSApplication, open urls: [URL]) {
        urls.filter { $0.scheme == "oriel" }.forEach(WindowPages.float)
        // Files only: `oriel://float/?…` has a directory path too ("/").
        let folders = urls.filter { $0.isFileURL && $0.hasDirectoryPath }
        if !folders.isEmpty {
            WindowPages.open(folders: folders)
            // Out of the Dock if minimized, so the new workspace shows.
            WindowPages.windows.first?.window?.makeKeyAndOrderFront(nil)
        }
        openWindowIfNone()
    }

    /// AppKit's windows, not `WindowPages.windows`: a restored window joins those only once its pages restored.
    /// Hidden (⌘H), no window is visible.
    private func openWindowIfNone() {
        if !NSApp.windows.contains(where: {
            $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized || NSApp.isHidden)
        }) {
            WindowPages.openWindow?(id: "main")
        }
    }

    @objc private func pick(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        NSApp.activate()
        WindowPages.go(to: id)
    }

    /// In the last key window, out of the Dock if minimized; with no window, a new one.
    @objc private func newTab() {
        NSApp.activate()
        guard let pages = WindowPages.windows.first, let page = pages.current else { return openWindowIfNone() }
        pages.window?.makeKeyAndOrderFront(nil)
        Task { await page.newTab() }
    }

    /// While the app is active too: it posts only for panes the user is not looking at.
    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async
        -> UNNotificationPresentationOptions
    {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
    )
        async
    {
        let id = response.notification.request.identifier
        await MainActor.run {
            NSApp.activate()
            WindowPages.go(to: id)
        }
    }
}

/// The app's notifications (D31): needs you and finished, for every open page; no sounds.
@MainActor
enum Notifications {
    /// Posts the snapshot's new needs-you and finishes, except for panes the user looks at, and removes the page's
    /// ones that no longer hold (the pane works, idles, closed or lost its agent).
    static func post(_ changes: [Seen.Change], _ page: Page) {
        let store = page.store
        Task {
            let center = UNUserNotificationCenter.current()
            let delivered = await center.deliveredNotifications().map(\.request.identifier)
            // After the wait: a later snapshot's new one must not go.
            let holding = Set(store.panes.filter { $0.state ?? .idle >= .finishedUnseen }
                .map { id($0, of: store) })
            let gone = delivered
                .filter { $0.hasPrefix("\(store.machine.id)|\(store.session)|") && !holding.contains($0) }
            center.removeDeliveredNotifications(withIdentifiers: gone)
        }
        for change in changes where change.state >= .finishedUnseen {
            guard let pane = store.pane(change.paneID), pane.tabID != store.lookingTabID else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(pane.agentName ?? "agent") \(change.state.word)"
            content.body = "\(store.label) · \(page.place(pane))"
            UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: id(pane, of: store), content: content, trigger: nil))
        }
    }

    /// The user looks at these panes.
    static func remove(_ panes: [HostStore.Pane], of store: HostStore) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: panes.map { id($0, of: store) })
    }

    /// One per terminal, so a newer one replaces the older; the Dock menu's rows carry it too.
    static func id(_ pane: HostStore.Pane, of store: HostStore) -> String {
        "\(store.machine.id)|\(store.session)|\(pane.terminalID ?? pane.id)"
    }
}

extension HostStore {
    /// Agents that need you over every open session, each once.
    static var needsYou: Int {
        all.reduce(0) { $0 + $1.waiting }
    }

    static func showBadge() {
        NSApp.dockTile.badgeLabel = needsYou > 0 ? "\(needsYou)" : nil
    }
}
