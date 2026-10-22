#if os(macOS)
    import AppKit
    import HerdrKit
    import UserNotifications

    /// The notification delegate (set at launch, so a click that starts the app is not lost) and the Dock menu.
    final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
        func applicationWillFinishLaunching(_: Notification) {
            UNUserNotificationCenter.current().delegate = self
        }

        /// A row per pane that needs you or finished, then New Tab.
        func applicationDockMenu(_: NSApplication) -> NSMenu? {
            let menu = NSMenu()
            for page in WindowPages.main?.list ?? [] {
                for pane in page.store.panes where pane.state == .needsYou || pane.state == .finishedUnseen {
                    guard let state = pane.state, let terminalID = pane.terminalID else { continue }
                    let workspace = page.store.workspace(of: pane.tabID)?.label ?? ""
                    let item = NSMenuItem(
                        title: "\(pane.agentName ?? "agent") \(state.word) · \(page.id) · \(workspace)",
                        action: #selector(pick),
                        keyEquivalent: "",
                    )
                    item.target = self
                    item.representedObject = [page.id, terminalID]
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
            guard let ids = item.representedObject as? [String], ids.count == 2 else { return }
            NSApp.activate()
            WindowPages.main?.go(toTerminal: ids[1], in: ids[0])
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
            let parts = response.notification.request.identifier.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { return }
            await MainActor.run {
                NSApp.activate()
                WindowPages.main?.go(toTerminal: parts[2], in: parts[1])
            }
        }
    }

    /// The app's notifications (D31): needs you and finished, for every open page; no sounds.
    @MainActor
    enum Notifications {
        private static var asked = false

        /// Posts the snapshot's new needs-you and finishes, except for panes the user looks at.
        static func post(_ changes: [Seen.Change], _ page: Page) {
            let store = page.store
            for change in changes where change.state == .needsYou || change.state == .finishedUnseen {
                guard let pane = store.pane(change.paneID), pane.tabID != store.lookingTabID,
                      let tab = store.workspace(of: pane.tabID)?.tabs.first(where: { $0.id == pane.tabID })
                else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(pane.agentName ?? "agent") \(change.state.word)"
                content.body = [page.id, store.workspace(of: pane.tabID)?.label ?? "", page.titleText(tab)]
                    .joined(separator: " · ")
                add(UNNotificationRequest(identifier: id(pane, page), content: content, trigger: nil))
            }
        }

        /// The user looks at these panes.
        static func remove(_ panes: [HostStore.Pane], of page: Page) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: panes.map { id($0, page) })
        }

        /// One per terminal, so a newer one replaces the older.
        private static func id(_ pane: HostStore.Pane, _ page: Page) -> String {
            "local|\(page.id)|\(pane.terminalID ?? pane.id)"
        }

        private static func add(_ request: UNNotificationRequest) {
            Task {
                let center = UNUserNotificationCenter.current()
                if !asked {
                    asked = true
                    _ = try? await center.requestAuthorization(options: [.alert, .badge])
                }
                try? await center.add(request)
            }
        }
    }
#endif
