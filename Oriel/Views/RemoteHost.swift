#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// The machine button's Add Remote Host dialog (ui/add-a-machine): a name, the SSH target and an icon. Add saves
    /// the machine and opens it in a new window, which connects and asks what ssh asks.
    struct AddHost: View {
        let pages: WindowPages
        @State private var name = ""
        @State private var target = ""
        @State private var icon = "server.rack"
        @FocusState private var focused: Bool

        static let icons = ["laptopcomputer", "desktopcomputer", "server.rack", "cloud", "cpu", "house", "flask",
                            "gamecontroller"]

        var body: some View {
            let target = target.trimmingCharacters(in: .whitespaces)
            VStack(alignment: .leading, spacing: 14) {
                Label("Add Remote Host", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        label("Name")
                        TextField("", text: $name).focused($focused).focusSoon($focused).fieldCapsule()
                            .accessibilityLabel("Name").accessibilityIdentifier("add-host.name")
                    }
                    GridRow {
                        label("SSH Target")
                        TextField("", text: $target).fieldCapsule()
                            .accessibilityLabel("SSH Target").accessibilityIdentifier("add-host.target")
                    }
                    GridRow {
                        label("Icon")
                        Picker("Icon", selection: $icon) {
                            ForEach(Self.icons, id: \.self) { Image(systemName: $0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .font(.system(size: 13))
                HStack {
                    Spacer()
                    Button("Cancel") { pages.addingHost = false }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.glass)
                    Button("Add") { add(target) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                        .disabled(!SSHExec.isValidTarget(target))
                        .accessibilityIdentifier("add-host.add")
                }
            }
        }

        private func label(_ text: String) -> some View {
            Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
        }

        private func add(_ target: String) {
            let name = name.trimmingCharacters(in: .whitespaces)
            let machine = Machine(id: UUID().uuidString, name: name.isEmpty ? target : name, target: target, icon: icon)
            MachineList.shared.list.append(machine)
            pages.addingHost = false
            WindowPages.open(machine: machine, connect: true)
        }
    }

    /// One of ssh's questions (machines#macos): its text, and a hidden answer field (a password, a passcode, any
    /// code). A new host key asks only yes or no, with its fingerprint in the text.
    struct AskDialog: View {
        let question: WindowPages.Question
        let machine: Machine
        @State private var answer = ""
        @FocusState private var focused: Bool

        var body: some View {
            let hostKey = question.text.contains("(yes/no")
            VStack(alignment: .leading, spacing: 12) {
                Label(machine.name, systemImage: machine.icon).font(.system(size: 13, weight: .semibold))
                Text(hostKey ? Self.facts(question.text) : question.text
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(hostKey ? .system(size: 12).monospaced() : .system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ask.text")
                if !hostKey {
                    HStack(spacing: 6) {
                        Image(systemName: "key").foregroundStyle(.secondary).accessibilityHidden(true)
                        SecureField("", text: $answer)
                            .accessibilityLabel("Answer")
                            .focused($focused)
                            .focusSoon($focused)
                            .onSubmit { question.answer(answer) }
                            .accessibilityIdentifier("ask.answer")
                    }
                    .fieldCapsule()
                }
                HStack {
                    Spacer()
                    Button("Cancel") { question.answer(nil) }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("ask.cancel")
                    Button(hostKey ? "Connect" : "OK") { question.answer(hostKey ? "yes" : answer) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("ask.ok")
                }
            }
        }

        /// A host key question's facts: without ssh's last line, which Connect says, and with the fingerprint on a line
        /// of its own.
        static func facts(_ text: String) -> String {
            text.split(separator: "\n").filter { !$0.contains("(yes/no") }.joined(separator: "\n")
                .replacing(#/fingerprint is:? /#, with: "fingerprint is:\n")
        }
    }

    extension View {
        /// In the middle of the window, in the palette's glass (Add Remote Host, ssh's questions). The window behind
        /// takes no clicks: only the dialog's buttons close it, and Esc is Cancel.
        func dialog() -> some View {
            Color.clear.contentShape(.rect).onTapGesture {}
                .overlay {
                    padding(20).frame(width: 440).floatingGlass(in: .rect(cornerRadius: 14))
                        .accessibilityElement(children: .contain)
                }
        }
    }
#endif
