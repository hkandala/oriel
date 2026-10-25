#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// The machine button's Add Remote Host sheet (ui/add-a-machine): a name, the SSH target and an icon. Add saves
    /// the machine, shows its `default` session in the window and connects, asking what ssh asks.
    struct AddHost: View {
        let pages: WindowPages
        @State private var name = ""
        @State private var target = ""
        @State private var icon = "server.rack"
        @Environment(\.dismiss) private var dismiss

        static let icons = ["laptopcomputer", "desktopcomputer", "server.rack", "cloud", "cpu", "house", "flask",
                            "gamecontroller"]

        var body: some View {
            let target = target.trimmingCharacters(in: .whitespaces)
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Remote Host").font(.headline)
                Form {
                    TextField("Name", text: $name).accessibilityIdentifier("add-host.name")
                    TextField("SSH Target", text: $target).accessibilityIdentifier("add-host.target")
                    Picker("Icon", selection: $icon) {
                        ForEach(Self.icons, id: \.self) { Image(systemName: $0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Add") { add(target) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!SSHExec.isValidTarget(target))
                        .accessibilityIdentifier("add-host.add")
                }
            }
            .padding(20)
            .frame(width: 420)
        }

        private func add(_ target: String) {
            let name = name.trimmingCharacters(in: .whitespaces)
            let machine = Machine(id: UUID().uuidString, name: name.isEmpty ? target : name, target: target, icon: icon)
            MachineList.shared.list.append(machine)
            dismiss()
            pages.show(machine: machine)
            Task { await pages.current?.store.connect() }
        }
    }

    /// One of ssh's questions (machines#macos): its text, and the answer field, hidden for a password, passphrase or
    /// PIN. A new host key asks only yes or no, with its fingerprint in the text.
    struct AskSheet: View {
        let question: WindowPages.Question
        @State private var answer = ""
        @FocusState private var focused: Bool

        var body: some View {
            let hostKey = question.text.contains("(yes/no")
            let secret = ["password", "passphrase", "PIN"]
                .contains { question.text.localizedCaseInsensitiveContains($0) }
            VStack(alignment: .leading, spacing: 12) {
                Text(question.machine).font(.headline)
                Text(question.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(hostKey ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ask.text")
                if !hostKey {
                    Group {
                        if secret {
                            SecureField("Answer", text: $answer)
                        } else {
                            TextField("Answer", text: $answer)
                        }
                    }
                    .labelsHidden()
                    .focused($focused)
                    .accessibilityIdentifier("ask.answer")
                }
                HStack {
                    Spacer()
                    Button("Cancel") { question.answer(nil) }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("ask.cancel")
                    Button(hostKey ? "Connect" : "OK") { question.answer(hostKey ? "yes" : answer) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("ask.ok")
                }
            }
            .padding(20)
            .frame(width: 460)
            .onAppear { focused = true }
        }
    }
#endif
