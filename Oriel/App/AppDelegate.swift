#if os(macOS)
    import AppKit
    import HerdrKit
    import UserNotifications

    /// The notification delegate (set at launch, so a click that starts the app is not lost) and the Dock menu.
    final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
        func applicationWillFinishLaunching(_: Notification) {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            // macOS asks the user once; later calls answer at once. The Dock badge shows only with `.badge` allowed.
            center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
        }

        /// A row per pane that needs you or finished, then New Tab.
        func applicationDockMenu(_: NSApplication) -> NSMenu? {
            let menu = NSMenu()
            for page in WindowPages.main?.list ?? [] {
                for pane in page.store.panes {
                    guard let state = pane.state, state >= .finishedUnseen else { continue }
                    let workspace = page.store.workspace(of: pane.tabID)?.label ?? ""
                    let item = NSMenuItem(
                        title: "\(pane.agentName ?? "agent") \(state.word) · \(page.id) · \(workspace)",
                        action: #selector(pick),
                        keyEquivalent: "",
                    )
                    item.target = self
                    item.representedObject = Notifications.id(pane, page)
                    menu.addItem(item)
                }
            }
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            menu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "").target = self
            return menu
        }

        @objc private func pick(_ item: NSMenuItem) {
            guard let id = item.representedObject as? String else { return }
            NSApp.activate()
            WindowPages.go(to: id)
        }

        @objc private func newTab() {
            NSApp.activate()
            Task { await WindowPages.main?.current?.newTab() }
        }

        /// While the app is active too: it posts only for panes the user is not looking at.
        nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async
            -> UNNotificationPresentationOptions
        {
            [.banner, .list]
        }

        /// A click shows the pane.
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
                let holding = Set(store.panes.filter { $0.state ?? .idle >= .finishedUnseen }.map { id($0, page) })
                let gone = delivered.filter { $0.hasPrefix("local|\(page.id)|") && !holding.contains($0) }
                center.removeDeliveredNotifications(withIdentifiers: gone)
            }
            for change in changes where change.state >= .finishedUnseen {
                guard let pane = store.pane(change.paneID), pane.tabID != store.lookingTabID else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(pane.agentName ?? "agent") \(change.state.word)"
                content.body = "\(page.id) · \(page.place(pane))"
                UNUserNotificationCenter.current()
                    .add(UNNotificationRequest(identifier: id(pane, page), content: content, trigger: nil))
            }
        }

        /// The user looks at these panes.
        static func remove(_ panes: [HostStore.Pane], of page: Page) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: panes.map { id($0, page) })
        }

        /// One per terminal, so a newer one replaces the older; the Dock menu's rows carry it too.
        static func id(_ pane: HostStore.Pane, _ page: Page) -> String {
            "local|\(page.id)|\(pane.terminalID ?? pane.id)"
        }
    }
#endif
