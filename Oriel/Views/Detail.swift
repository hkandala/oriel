#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// A short message in a capsule at the bottom of the strip, with an optional action (design: Notice).
    struct Notice<Action: View>: View {
        let text: String
        @ViewBuilder var action: Action

        var body: some View {
            HStack(spacing: 8) {
                Text(text)
                action
            }
            .padding(8)
            .glassEffect()
        }
    }

    /// The page's selected workspace's tabs, or why there is nothing to show.
    struct Detail: View {
        let pages: WindowPages
        let page: Page

        var body: some View {
            let store = page.store
            switch store.state {
            case .connecting:
                ProgressView("Connecting to \(HostStore.name(store.session))")
            case .live:
                if let workspace = page.selectedWorkspace {
                    Strip(workspace: workspace, page: page)
                        .overlay(alignment: .bottom) {
                            VStack(spacing: gap) {
                                if let notice = store.notice {
                                    Notice(text: notice) {}.accessibilityIdentifier("detail.notice")
                                }
                                // Another window controls the session (D66).
                                if page.watched {
                                    Notice(text: "Controlled in another window") {
                                        Button("Take Back") { pages.control(store) }
                                            .accessibilityIdentifier("notice.controlled.take-back")
                                    }
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier("notice.controlled")
                                }
                            }
                            .padding([.horizontal, .bottom], gap * 2)
                            .padding(.bottom, 30 - gap * 2)
                        }
                } else {
                    NewWorkspaceButton(page: page)
                }
            case .failed(.notFound):
                message("herdr is not installed", "Install it in a terminal:",
                        "curl -fsSL https://herdr.dev/install.sh | sh")
            case let .failed(.unsupported(text)):
                message("herdr is too old", text + ". Update it in a terminal:", "herdr update")
            case .failed where !store.isRunning:
                message("\(store.session) is not running", "Start it to see its workspaces.", nil, start: true)
            case let .failed(error):
                message("No answer from herdr", error.localizedDescription, nil)
            }
        }

        /// What is wrong and the command that fixes it; a stopped session gets a Start button instead (design D47).
        private func message(_ title: String, _ text: String, _ command: String?, start: Bool = false) -> some View {
            ContentUnavailableView {
                Label(title, systemImage: "terminal")
            } description: {
                Text(text)
                // Why a start failed.
                if let notice = page.store.notice {
                    Text(notice).accessibilityIdentifier("detail.notice")
                }
                if let command {
                    Text(command).monospaced().textSelection(.enabled)
                }
            } actions: {
                if start {
                    Button("Start \(page.store.session)") { Task { await page.store.start() } }
                        .accessibilityIdentifier("detail.start")
                }
            }
        }
    }
#endif
