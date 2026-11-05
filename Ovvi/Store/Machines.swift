import Foundation
import HerdrKit
import Observation
import SystemConfiguration

/// A computer that runs herdr (D43): This Mac, or a remote machine of the app's own list (D54).
struct Machine: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// What `ssh` connects to, as the user types it in a terminal; empty for This Mac.
    var target: String
    var icon: String

    var isRemote: Bool {
        !target.isEmpty
    }
}

extension Machine {
    static let thisMac = Machine(id: "local", name: "This Mac", target: "", icon: thisMacIcon)
    /// This Mac's own name, as set in System Settings ("Hari's MacBook Pro"). Read once: a rename shows after a
    /// relaunch.
    static let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? thisMac.name

    /// Its one Exec for the app's life; the sessions of a remote machine share its ControlMaster.
    @MainActor func exec() async -> any Exec {
        let local = await localExec.value
        guard isRemote else { return local }
        if let exec = Self.execs[target] {
            return exec
        }
        let exec = SSHExec(target: target, local: local)
        Self.execs[target] = exec
        return exec
    }

    /// By target, as the sockets are: two machines of one target share a master.
    @MainActor private static var execs: [String: SSHExec] = [:]

    /// The app quits: each remote machine's master ends (machines#macos).
    @MainActor static func disconnectAll() {
        execs.values.forEach { $0.disconnect() }
    }
}

/// The remote machines, in `UserDefaults` (D54). A run with `-session` (the tests, a run against a throwaway
/// session) never sees the user's machines: it takes `-machines <json>` or none, and saves nothing.
@MainActor @Observable
final class MachineList {
    static let shared = MachineList()

    var list: [Machine] {
        didSet {
            if !Self.isolated, let data = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: "machines")
            }
        }
    }

    private static let isolated = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        .keys.contains { $0 == "session" || $0 == "machines" }

    private init() {
        // The argument as given: the argument domain reads a JSON array as something else.
        let arguments = ProcessInfo.processInfo.arguments
        let json = Self.isolated
            ? arguments.firstIndex(of: "-machines").flatMap { arguments.dropFirst($0 + 1).first }
            : UserDefaults.standard.string(forKey: "machines")
        list = json.flatMap { try? JSONDecoder().decode([Machine].self, from: Data($0.utf8)) } ?? []
    }

    /// An edit of a listed machine. Its open windows take it all, so their next windows and pages use the new
    /// target; its open sessions take the name and icon only, as they stay connected to the old target.
    func save(_ machine: Machine) {
        guard let index = list.firstIndex(where: { $0.id == machine.id }) else { return }
        list[index] = machine
        for window in WindowPages.windows where window.machine.id == machine.id {
            window.machine = machine
        }
        for store in HostStore.all where store.machine.id == machine.id {
            store.machine.name = machine.name
            store.machine.icon = machine.icon
        }
    }

    func machine(_ id: String) -> Machine? {
        id == Machine.thisMac.id ? .thisMac : list.first { $0.id == id }
    }
}
