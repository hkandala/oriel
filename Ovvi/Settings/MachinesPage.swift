import HerdrKit
import SwiftUI
import WebKit

/// Settings ▸ Machines: This Mac and the remote machines, in the machine menu's order. A row opens its page.
/// ponytail: no drag to reorder (a grouped form takes no `onMove`); a List section if users ask.
struct MachinesPage: View {
    var body: some View {
        let list = MachineList.shared
        Form {
            Section {
                NavigationLink(value: SettingsDetail.machine(Machine.thisMac.id)) {
                    MachineLabel(machine: .thisMac, detail: Machine.computerName)
                }
                .accessibilityIdentifier("settings.machine.\(Machine.thisMac.id)")
                ForEach(list.list) { machine in
                    NavigationLink(value: SettingsDetail.machine(machine.id)) {
                        MachineLabel(machine: machine, detail: machine.target)
                    }
                    .accessibilityIdentifier("settings.machine.\(machine.id)")
                }
            } header: {
                HStack {
                    Text("Machines")
                    Spacer()
                    NavigationLink("Add Machine…", value: SettingsDetail.machine(MachinePage.new))
                        .accessibilityIdentifier("settings.machines.add")
                }
                .settingsRow("machines.list")
            }
        }
    }
}

/// A machine's icon tile, name, a line under it, and whether a window is connected to it.
private struct MachineLabel: View {
    let machine: Machine
    let detail: String
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            SettingsTile(page: .machines, symbol: machine.icon, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(machine.name)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if machine.isRemote {
                let live = HostStore.all.contains { $0.machine.id == machine.id && $0.state == .live }
                Label(live ? "Connected" : "Not connected", systemImage: "circle.fill")
                    .labelStyle(StatusLabel(color: live ? look.finished : .secondary))
            }
        }
    }

    private struct StatusLabel: LabelStyle {
        let color: Color

        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 5) {
                configuration.icon.font(.system(size: 7)).foregroundStyle(color)
                configuration.title.font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

/// A machine's page: its name, SSH target and icon (Add Remote Host's fields), its website data, and Remove. This Mac
/// has only its website data. `new`: Add Machine's empty page.
struct MachinePage: View {
    static let new = "new"
    let id: String
    @State private var draft: Machine
    @State private var confirm: Confirm?
    @Environment(\.dismiss) private var dismiss

    private enum Confirm {
        case clear, remove
    }

    private var question: String {
        let name = MachineList.shared.machine(id)?.name ?? ""
        return confirm == .clear ? "Clear the website data of \(name)?" : "Remove \(name)?"
    }

    private var confirming: Binding<Bool> {
        Binding { confirm != nil } set: {
            if !$0 {
                confirm = nil
            }
        }
    }

    init(id: String) {
        self.id = id
        _draft = State(initialValue: MachineList.shared.machine(id)
            ?? Machine(id: UUID().uuidString, name: "", target: "", icon: "server.rack"))
    }

    var body: some View {
        let saved = MachineList.shared.machine(id), target = draft.target.trimmingCharacters(in: .whitespaces)
        Form {
            if draft.isRemote || saved == nil {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text(target))
                        .accessibilityIdentifier("settings.machine.name")
                    TextField(text: $draft.target) {
                        Text("SSH target")
                        Text("A host from ~/.ssh/config works too.")
                    }
                    .font(.system(size: 13).monospaced())
                    .accessibilityIdentifier("settings.machine.target")
                    LabeledContent("Icon") { IconPicker(icon: $draft.icon) }
                } footer: {
                    HStack {
                        Spacer()
                        Button(saved == nil ? "Add" : "Save") {
                            if saved == nil {
                                dismiss()
                            }
                            draft = MachineList.shared.keep(draft, target: target)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!SSHExec.isValidTarget(target) || saved == draft)
                        .accessibilityIdentifier("settings.machine.save")
                    }
                }
            }
            if let saved {
                Section("On \(saved.name)") {
                    LabeledContent {
                        Button("Clear…") { confirm = .clear }.accessibilityIdentifier("settings.machine.clear")
                    } label: {
                        Text("Website data")
                        Text("Logins and approved websites of browser cards on \(saved.name).")
                    }
                }
                if saved.isRemote {
                    Section {
                        Button("Remove \(saved.name)…", role: .destructive) { confirm = .remove }
                            .accessibilityIdentifier("settings.machine.remove")
                    } footer: {
                        Text("Its terminals keep running on \(saved.name).").settingsFooter()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(saved?.name ?? "Add Machine")
        // The buttons and the message keep their words while the alert closes: `confirm` is nil by then.
        .alert(question, isPresented: confirming, presenting: confirm) { which in
            Button(which == .clear ? "Clear" : "Remove", role: .destructive) {
                if let saved, which == .clear {
                    Self.clear(saved)
                } else if let saved {
                    MachineList.shared.remove(saved)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { which in
            Text(which == .clear ? "Browser cards log out of every site, and pages wait for Open again."
                : "Ovvi forgets it. Its terminals keep running on it.")
        }
    }

    /// Its browser cards' cookies, storage and cache, and its approved websites.
    private static func clear(_ machine: Machine) {
        UserDefaults.standard.removeObject(forKey: "browserApprovals.\(machine.id)")
        Browser.dataStore(machine).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                              modifiedSince: .distantPast) {}
    }
}

/// Settings ▸ Privacy: the websites each machine's browser cards load by themselves, with Remove and Clear All.
struct PrivacyPage: View {
    /// Read again after a change: the approvals are plain defaults.
    @State private var version = 0

    /// Any machine has an approved website: else the page has nothing to show and is not in the sidebar.
    /// ponytail: read when the sidebar draws; observe `UserDefaults.didChangeNotification` if a site approved while
    /// Settings is open must add the page at once.
    static var hasItems: Bool {
        machines.contains { !approvals($0).isEmpty }
    }

    var body: some View {
        let _ = version // swiftlint:disable:this redundant_discardable_let
        Form {
            ForEach(Self.machines.filter { !Self.approvals($0).isEmpty }) { machine in
                Section {
                    ForEach(Self.approvals(machine), id: \.self) { site in
                        LabeledContent(site) {
                            Button("Remove") { set(Self.approvals(machine).filter { $0 != site }, machine) }
                                .accessibilityIdentifier("settings.privacy.\(machine.id).\(site).remove")
                        }
                    }
                } header: {
                    HStack {
                        Text("Approved websites on \(machine.name)")
                        Spacer()
                        Button("Clear All") { set([], machine) }
                            .accessibilityIdentifier("settings.privacy.\(machine.id).clear")
                    }
                }
            }
            Section {} footer: {
                Text("A page from a machine loads by itself only from these sites, its localhost and a short safe "
                    + "list. Ovvi adds a site when you open it.").settingsFooter().settingsRow("privacy.websites")
            }
        }
    }

    private static var machines: [Machine] {
        [.thisMac] + MachineList.shared.list
    }

    private static func approvals(_ machine: Machine) -> [String] {
        UserDefaults.standard.stringArray(forKey: "browserApprovals.\(machine.id)") ?? []
    }

    private func set(_ sites: [String], _ machine: Machine) {
        UserDefaults.standard.set(sites, forKey: "browserApprovals.\(machine.id)")
        version += 1
    }
}
