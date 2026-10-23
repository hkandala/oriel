#if os(macOS)
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
        }

        func applicationWillFinishLaunching(_: Notification) {
            // Windows and their pages come back after a normal quit too, whatever the system setting says. A session
            // start waits 10 s for its server (`-startTimeout`).
            UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true, "startTimeout": 10])
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            // macOS asks the user once; later calls answer at once. The Dock badge shows only with `.badge` allowed.
            center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
        }

        /// A row per pane that needs you or finished, each session once over every window, then New Tab.
        func applicationDockMenu(_: NSApplication) -> NSMenu? {
            let menu = NSMenu()
            for store in HostStore.all {
                for pane in store.panes {
                    guard let state = pane.state, state >= .finishedUnseen else { continue }
                    let workspace = store.workspace(of: pane.tabID)?.label ?? ""
                    let item = NSMenuItem(
                        title: "\(pane.agentName ?? "agent") \(state.word) · \(store.session) · \(workspace)",
                        action: #selector(pick),
                        keyEquivalent: "",
                    )
                    item.target = self
                    item.representedObject = Notifications.id(pane, session: store.session)
                    menu.addItem(item)
                }
            }
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            menu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "").target = self
            return menu
        }

        /// Folders dropped on the Dock icon (WindowPages). With no window (a drop that starts the app opens none:
        /// `handlesExternalEvents(matching: [])`), a new one takes them once its page is live.
        func application(_: NSApplication, open urls: [URL]) {
            WindowPages.open(folders: urls.filter(\.hasDirectoryPath))
            // Out of the Dock if minimized, so the new workspace shows.
            WindowPages.windows.first?.window?.makeKeyAndOrderFront(nil)
            // AppKit's windows, not `WindowPages.windows`: a restored window joins those only once its pages restored.
            // Hidden (⌘H), no window is visible.
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

        @objc private func newTab() {
            NSApp.activate()
            Task { await WindowPages.windows.first?.current?.newTab() }
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
                    .map { id($0, session: page.id) })
                let gone = delivered.filter { $0.hasPrefix("local|\(page.id)|") && !holding.contains($0) }
                center.removeDeliveredNotifications(withIdentifiers: gone)
            }
            for change in changes where change.state >= .finishedUnseen {
                guard let pane = store.pane(change.paneID), pane.tabID != store.lookingTabID else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(pane.agentName ?? "agent") \(change.state.word)"
                content.body = "\(page.id) · \(page.place(pane))"
                UNUserNotificationCenter.current()
                    .add(UNNotificationRequest(identifier: id(pane, session: page.id), content: content, trigger: nil))
            }
        }

        /// The user looks at these panes.
        static func remove(_ panes: [HostStore.Pane], session: String) {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: panes.map { id($0, session: session) })
        }

        /// One per terminal, so a newer one replaces the older; the Dock menu's rows carry it too.
        static func id(_ pane: HostStore.Pane, session: String) -> String {
            "local|\(session)|\(pane.terminalID ?? pane.id)"
        }
    }
#endif
