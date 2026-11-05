import SwiftUI

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
                        .controlSize(.small).accessibilityIdentifier("settings.machines.add")
                }
                .settingsRow("machines.list")
            }
        }
    }
}

/// A machine's icon, name, a line under it, and whether a window is connected to it.
private struct MachineLabel: View {
    let machine: Machine
    let detail: String
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            // The width of an agent's or a plugin's tile: names line up across pages.
            Image(systemName: machine.icon).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(machine.name)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if machine.isRemote {
                let live = MachinePage.isLive(machine)
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
                        Button("Clear All") { set([], machine) }.controlSize(.small)
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
