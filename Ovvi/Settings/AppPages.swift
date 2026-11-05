import GhosttyTerminal
import ServiceManagement
import SwiftUI

/// Settings ▸ General: opening at login, how panes take the keyboard, and the shortcuts.
struct GeneralPage: View {
    private var settings = AppSettings()

    var body: some View {
        Form {
            Section("Startup") { OpenAtLogin() }
            Section("Panes") {
                Toggle(isOn: settings.$followMouse) {
                    Text("Focus follows mouse")
                    Text("A pane gets the keyboard when the pointer rests on it.")
                }
                .accessibilityIdentifier("settings.general.follow-mouse").settingsRow("general.follow-mouse")
            }
            Section("Help") {
                LabeledContent("Keyboard shortcuts") {
                    Button("Show Shortcuts") { CommandList.runInMainWindow("Keyboard Shortcuts") }
                        .accessibilityIdentifier("settings.general.shortcuts")
                }
                .settingsRow("general.shortcuts")
            }
        }
    }
}

/// Open at login: the system's login item for the app (`SMAppService.mainApp`), read again each time the app comes
/// forward, so a change in System Settings ▸ General ▸ Login Items shows here; never kept in the app's defaults. A run
/// with a config folder of its own (the UI tests) only flips the switch: a test build must never become a login item.
private struct OpenAtLogin: View {
    @State private var status = Self.read()
    @State private var problem: String?
    @Environment(\.look) private var look

    private static var isTest: Bool {
        UserDefaults.standard.string(forKey: "configFolder") != nil
    }

    private static func read() -> SMAppService.Status {
        isTest ? .notRegistered : SMAppService.mainApp.status
    }

    var body: some View {
        Toggle(isOn: Binding { status == .enabled || status == .requiresApproval } set: { set($0) }) {
            Text("Open at login")
            if let problem {
                Text(problem).foregroundStyle(look.error)
            } else if status == .requiresApproval {
                Text("Allow Ovvi in System Settings ▸ General ▸ Login Items.")
            }
        }
        .accessibilityIdentifier("settings.general.open-at-login").settingsRow("general.open-at-login")
        .task {
            // A test run's switch keeps its own value.
            guard !Self.isTest else { return }
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                status = Self.read()
            }
        }
        if status == .requiresApproval {
            LabeledContent("Waiting for your approval") {
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    .accessibilityIdentifier("settings.general.login-items")
            }
        }
    }

    private func set(_ isOn: Bool) {
        problem = nil
        if Self.isTest {
            status = isOn ? .enabled : .notRegistered
            return
        }
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            problem = error.localizedDescription
        }
        status = Self.read()
    }
}

/// Settings ▸ Appearance: the look as picture tiles, and the text size.
struct AppearancePage: View {
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                LabeledContent("Appearance") {
                    HStack(spacing: 14) {
                        ForEach([Appearance.auto, .light, .dark], id: \.self) { value in
                            LookTile(title: value.rawValue.capitalized, selected: settings.appearance == value,
                                     id: "settings.appearance.\(value.rawValue)",
                                     picture: LookPicture(dark: value == .dark, split: value == .auto, glass: false),
                                     action: { settings.appearance = value })
                        }
                    }
                }
                .settingsRow("appearance.appearance")
                LabeledContent {
                    HStack(spacing: 14) {
                        ForEach([InterfaceStyle.glass, .classic], id: \.self) { value in
                            LookTile(title: value.rawValue.capitalized, selected: settings.style == value,
                                     id: "settings.style.\(value.rawValue)",
                                     picture: LookPicture(dark: colorScheme == .dark, split: false,
                                                          glass: value == .glass),
                                     action: { settings.style = value })
                        }
                    }
                } label: {
                    Text("Interface style")
                    Text("Glass lets the desktop show through softly. Classic is an opaque window.")
                }
                .settingsRow("appearance.style")
            }
            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text("\(settings.fontSize) pt").monospacedDigit()
                            .accessibilityIdentifier("settings.appearance.font-size.value")
                        Stepper("Text size", value: settings.$fontSize, in: PaneTerminal.fontSizes).labelsHidden()
                            .accessibilityIdentifier("settings.appearance.font-size")
                    }
                } label: {
                    Text("Text size")
                    Text("⌘+ and ⌘− change it in any window.")
                }
                .settingsRow("appearance.font-size")
            }
        }
    }
}

/// A choice drawn as a small window picture with its name under it.
private struct LookTile: View {
    let title: String
    let selected: Bool
    let id: String
    let picture: LookPicture
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                picture.frame(width: 66, height: 44).clipShape(.rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            selected ? Color.accentColor : .primary.opacity(0.15),
                            lineWidth: selected ? 2.5 : 1,
                        ))
                Text(title).font(.system(size: 11)).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// A window drawn small: a sidebar and two cards, in light or dark, half and half for Auto, over a desktop for Glass.
private struct LookPicture: View {
    let dark: Bool, split: Bool, glass: Bool

    var body: some View {
        ZStack {
            if glass {
                LinearGradient(colors: [.accentColor, .accentColor.opacity(0.2)], startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            }
            window(dark: dark).opacity(glass ? 0.55 : 1)
            if split {
                window(dark: true).mask(LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                                               .init(color: .black, location: 0.5)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
    }

    private func window(dark: Bool) -> some View {
        let look = Look(style: .classic, dark: dark), back = look.window, card = look.cardSolid
        return HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(card.opacity(0.5)).frame(width: 14)
            RoundedRectangle(cornerRadius: 2).fill(card)
            RoundedRectangle(cornerRadius: 2).fill(card)
        }
        .padding(4).background(back)
    }
}

/// Settings ▸ Terminal: libghostty's font, cursor, Option key and copy on select, for every terminal at once.
struct TerminalPage: View {
    private var settings = AppSettings()
    @State private var fonts: [String] = []

    var body: some View {
        Form {
            Section {
                Picker(selection: settings.$terminalFont) {
                    Text("SF Mono").tag("")
                    Divider()
                    // A family set before it was uninstalled stays a choice.
                    ForEach(fonts + (fonts.contains(settings.terminalFont) || settings.terminalFont.isEmpty
                            ? [] : [settings.terminalFont]), id: \.self) { Text($0).tag($0) }
                } label: {
                    Text("Font")
                    Text("Monospaced fonts on this Mac.")
                }
                .accessibilityIdentifier("settings.terminal.font").settingsRow("terminal.font")
                Picker("Cursor", selection: settings.$cursorStyle) {
                    Text("Block").tag(TerminalCursorStyle.block)
                    Text("Bar").tag(TerminalCursorStyle.bar)
                    Text("Underline").tag(TerminalCursorStyle.underline)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.terminal.cursor").settingsRow("terminal.cursor")
                Toggle("Blink the cursor", isOn: settings.$cursorBlink)
                    .accessibilityIdentifier("settings.terminal.blink").settingsRow("terminal.blink")
                Picker(selection: settings.$optionKey) {
                    Text("Types special characters").tag(OptionKey.characters)
                    Text("Acts as Meta").tag(OptionKey.meta)
                    Text("Left acts as Meta").tag(OptionKey.left)
                } label: {
                    Text("Option key")
                    Text("⌥B types ∫. Choose Meta for shells and editors that use ⌥ shortcuts.")
                }
                .accessibilityIdentifier("settings.terminal.option").settingsRow("terminal.option")
                Toggle("Copy text when you select it", isOn: settings.$copyOnSelect)
                    .accessibilityIdentifier("settings.terminal.copy").settingsRow("terminal.copy")
            } footer: {
                Text("Text size is in Appearance. Colors follow the appearance.").settingsFooter()
            }
        }
        .task { fonts = PaneTerminal.fonts }
    }
}

/// Settings ▸ Agents: the first view of new agents, the agents in New Pane, and the notifications.
struct AgentsPage: View {
    private var settings = AppSettings()

    var body: some View {
        Form {
            Section("New agents") {
                Picker(selection: settings.$agentView) {
                    Text("Terminal").tag(AgentView.terminal)
                    Text("Chat").tag(AgentView.chat)
                } label: {
                    Text("Open new agents in")
                    Text("Switch any agent between Chat and Terminal in its header.")
                }
                .accessibilityIdentifier("settings.agents.view").settingsRow("agents.view")
            }
            Section {
                ForEach(Chooser.agents, id: \.command) { AgentRow(agent: $0) }
            } header: {
                Text("Agents in New Pane").settingsRow("agents.new-pane")
            } footer: {
                Text("Ovvi adds the arguments when it starts the agent. An agent that is off is not in the New "
                    + "Pane list.").settingsFooter()
            }
            Section {
                Toggle(isOn: settings.$notifyNeedsYou) {
                    Text("When an agent needs you")
                    Text("It asks a question or waits for permission.")
                }
                .accessibilityIdentifier("settings.agents.needs-you").settingsRow("agents.needs-you")
                Toggle("When an agent finishes", isOn: settings.$notifyFinished)
                    .accessibilityIdentifier("settings.agents.finished").settingsRow("agents.finished")
                Toggle(isOn: settings.$notifyFromAgents) {
                    Text("When an agent sends one")
                    Text("Agents send them with the ovvi command.")
                }
                .accessibilityIdentifier("settings.agents.from-agents").settingsRow("agents.from-agents")
            } header: {
                Text("Notifications")
            } footer: {
                // A link in the sentence: it wraps with it and keeps its baseline.
                Text(.init("Banners, sounds and the Dock badge are in System Settings. [Notification Settings…]"
                        + "(x-apple.systempreferences:com.apple.Notifications-Settings.extension?id="
                        + "\(Bundle.main.bundleIdentifier ?? ""))"))
                    .settingsFooter()
            }
        }
    }
}

/// An agent's tile, name and command, its extra arguments, and whether New Pane lists it.
private struct AgentRow: View {
    let agent: Chooser.Agent
    @AppStorage private var arguments: String

    init(agent: Chooser.Agent) {
        self.agent = agent
        _arguments = AppStorage(wrappedValue: "", Chooser.argumentsKey(agent.command))
    }

    var body: some View {
        let id = "settings.agents.\(agent.command)"
        HStack(spacing: 10) {
            ProgramTile(icon: agent.command)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                Text(agent.command).font(.system(size: 11).monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Extra arguments", text: $arguments, prompt: Text("Extra arguments"))
                // The field shows what it keeps.
                .onChange(of: arguments) { arguments = Chooser.allowed(arguments) }
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .labelsHidden().accessibilityLabel("\(agent.name) extra arguments")
                .accessibilityIdentifier("\(id).arguments")
            Toggle("Show \(agent.name) in New Pane", isOn: Binding { !Registry.hiddenInNewPane(agent.command) } set: {
                Registry.show(agent.command, inNewPane: $0)
            })
            .toggleStyle(.switch).labelsHidden().accessibilityIdentifier("\(id).new-pane")
        }
    }
}

extension View {
    /// A section's footer, in System Settings' small grey text.
    func settingsFooter() -> some View {
        font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
