#if os(macOS)
    import HerdrKit
    import SwiftUI

    /// The machine menu's remote host dialog (ui/add-a-machine): a name, the SSH target and an icon. Add saves a new
    /// machine and opens it in a new window, which connects and asks what ssh asks; Save keeps an edit, Remove takes
    /// the machine off the list.
    struct HostDialog: View {
        let pages: WindowPages
        let editing: Bool
        @State private var draft: Machine
        @FocusState private var focused: Bool

        init(pages: WindowPages, machine: Machine) {
            self.pages = pages
            editing = MachineList.shared.list.contains { $0.id == machine.id }
            _draft = State(initialValue: machine)
        }

        var body: some View {
            let target = draft.target.trimmingCharacters(in: .whitespaces)
            VStack(alignment: .leading, spacing: 14) {
                Label(editing ? "Edit Remote Host" : "Add Remote Host", systemImage: editing ? "pencil" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Name").gridColumnAlignment(.trailing)
                        TextField("", text: $draft.name).focused($focused).focusSoon($focused).dialogField()
                            .accessibilityLabel("Name").accessibilityIdentifier("host.name")
                    }
                    GridRow {
                        Text("SSH Target")
                        TextField("", text: $draft.target).dialogField()
                            .accessibilityLabel("SSH Target").accessibilityIdentifier("host.target")
                    }
                    GridRow {
                        Text("Icon")
                        IconPicker(icon: $draft.icon)
                    }
                }
                .font(.system(size: 13))
                HStack {
                    if editing {
                        Button("Remove", role: .destructive) {
                            MachineList.shared.list.removeAll { $0.id == draft.id }
                            pages.hostDialog = nil
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("host.remove")
                    }
                    Spacer()
                    Button("Cancel") { pages.hostDialog = nil }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.glass)
                    Button(editing ? "Save" : "Add") { save(target) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                        .disabled(!SSHExec.isValidTarget(target))
                        .accessibilityIdentifier("host.save")
                }
            }
        }

        private func save(_ target: String) {
            var machine = draft
            let name = machine.name.trimmingCharacters(in: .whitespaces)
            machine.name = name.isEmpty ? target : name
            machine.target = target
            pages.hostDialog = nil
            if editing {
                MachineList.shared.save(machine)
            } else {
                MachineList.shared.list.append(machine)
                WindowPages.open(machine: machine, connect: true)
            }
        }
    }

    /// The icon, as a button; its popover is a grid of SF Symbols with a search by symbol name.
    private struct IconPicker: View {
        @Binding var icon: String
        @State private var open = false
        @State private var filter = ""

        var body: some View {
            Button { open = true } label: {
                Image(systemName: icon).frame(width: 36, height: 20)
            }
            .buttonStyle(.glass)
            .help("Icon")
            .accessibilityLabel("Icon")
            .accessibilityValue(icon)
            .accessibilityIdentifier("host.icon")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                let shown = Self.icons.filter { $0.replacing(".", with: " ").matches(filter.replacing(".", with: " ")) }
                VStack(spacing: 8) {
                    FilterField(prompt: "Search", text: $filter, identifier: "host.icon.search",
                                symbol: "magnifyingglass", autofocus: true)
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 2), count: 10), spacing: 2) {
                            ForEach(shown, id: \.self) { symbol in
                                Button {
                                    icon = symbol
                                    open = false
                                } label: {
                                    Image(systemName: symbol).font(.system(size: 14)).frame(width: 30, height: 30)
                                }
                                .buttonStyle(ChromeStyle(selected: symbol == icon, radius: 7))
                                .help(symbol)
                                .accessibilityLabel(symbol)
                                .accessibilityIdentifier("host.icon.\(symbol)")
                            }
                        }
                    }
                    .frame(height: 200)
                }
                .padding(10)
                .frame(width: 340)
            }
        }

        /// Computers first, then networks, places and things: SF Symbols that tell machines apart in the title row.
        static let icons = [
            "laptopcomputer", "desktopcomputer", "macmini", "macstudio", "macpro.gen3", "display", "server.rack",
            "externaldrive", "internaldrive", "cpu", "memorychip", "opticaldiscdrive", "terminal", "apple.terminal",
            "keyboard", "printer", "tv", "appletv", "iphone", "ipad", "applewatch", "visionpro", "gamecontroller",
            "headphones", "hifispeaker", "homepod", "cloud", "icloud", "network", "globe",
            "antenna.radiowaves.left.and.right", "wifi", "dot.radiowaves.left.and.right",
            "point.3.connected.trianglepath.dotted", "cable.connector", "bolt.horizontal", "lock", "shield", "key",
            "house", "building", "building.2", "building.columns", "briefcase", "graduationcap", "books.vertical",
            "book", "flask", "testtube.2", "atom", "brain", "cube", "shippingbox", "archivebox", "tray.full", "folder",
            "doc.text", "chart.bar", "gauge.with.dots.needle.67percent", "hammer", "wrench.and.screwdriver",
            "gearshape", "gearshape.2", "paintbrush", "paintpalette", "pencil", "camera", "film", "music.note", "mic",
            "sparkles", "star", "heart", "flag", "bell", "tag", "bookmark", "leaf", "tree", "mountain.2", "sun.max",
            "moon", "snowflake", "flame", "drop", "bolt", "tortoise", "hare", "ant", "ladybug", "bird", "fish",
            "pawprint", "cat", "dog", "car", "bus", "tram", "airplane", "ferry", "bicycle", "sailboat",
            "globe.americas", "globe.europe.africa", "globe.asia.australia", "map", "location", "mappin.and.ellipse",
            "circle", "square", "triangle", "diamond", "hexagon", "seal", "crown", "trophy", "gift",
            "cup.and.saucer", "fork.knife", "cart", "bag", "creditcard", "banknote", "dollarsign.circle", "person",
            "person.2", "figure.walk", "eye", "hand.raised", "lightbulb", "puzzlepiece", "function",
            "chevron.left.forwardslash.chevron.right", "curlybraces", "number", "textformat",
        ]
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
                    .dialogField()
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
        /// A dialog's field: filled and outlined, so it reads on the glass over light and dark content (the palette's
        /// soft capsule nearly vanished there, user, phase 29).
        func dialogField() -> some View {
            fieldCapsule().background(.background.opacity(0.6), in: .capsule)
                .overlay(Capsule().strokeBorder(.primary.opacity(0.2)))
        }

        /// In the middle of the window, in the palette's glass. The window behind takes no clicks: only the dialog's
        /// buttons close it, and Esc is Cancel (not `floatingPanel`: its Esc and outside click close).
        func dialog() -> some View {
            Color.clear.contentShape(.rect).onTapGesture {}
                .overlay {
                    padding(20).frame(width: 440).floatingGlass(in: .rect(cornerRadius: 14))
                        .accessibilityElement(children: .contain)
                }
        }
    }
#endif
