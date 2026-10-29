import AppKit
import HerdrKit
import MarkdownEngine
import SwiftUI

/// The Markdown card's content: the file rendered (Read) or MarkdownEngine's live preview of its own text (Edit),
/// with the outline of its headings at the left.
struct MarkdownCard: View {
    let plugin: Plugin
    let page: Page
    /// MarkdownEngine's text view has the keyboard; or Read's scroll view.
    @State private var focused = false
    @FocusState private var reading: Bool
    @State private var headings: [OutlineHeading] = []
    /// Read's sections, parsed off the main actor when the text changes.
    @State private var sections: [(line: Int, text: String)] = []
    @State private var anchor = EditorAnchor()
    /// The line Read scrolls to.
    @State private var target: Int?
    /// False in an overview tile: it shows Read and leaves the file and the keyboard to the card.
    @Environment(\.isEnabled) private var isEnabled

    /// MarkdownEngine and Read lay out the whole file at once (1.4 s at 200 KB): bigger files show their plain text,
    /// in both modes.
    static let renderLimit = 128 << 10

    /// Edit's column, as Read's: SF Pro at 14 pt, 640 pt wide, 24 pt in.
    private static let configuration = {
        var configuration = MarkdownEditorConfiguration.default
        configuration.readingWidth = 640
        configuration.textInsets = TextInsets(horizontal: 24, vertical: 16)
        // Straight quotes and no corrections: the text goes into the file as typed (code, YAML, commands).
        configuration.spellChecking = SpellCheckingPolicy(automaticSpellingCorrection: false,
                                                          automaticQuoteSubstitution: false)
        return configuration
    }()

    /// A big file's plain text: MarkdownEngine's raw source mode, which styles nothing.
    private static let source = {
        var source = configuration
        source.rawSourceMode = true
        return source
    }()

    var body: some View {
        let file = plugin.file
        HStack(spacing: 0) {
            if plugin.outline {
                outline
                Divider()
            }
            content(file)
        }
        .task(id: plugin.label.arg) {
            if isEnabled {
                await file.run(page.store.machine)
            }
        }
        .task(id: file.text) {
            // A tile draws the first screen or so.
            let text = isEnabled ? file.text : String(file.text.prefix(8 << 10))
            let parsed = await Task.detached { OutlineHeading.sections(text) }.value
            if !Task.isCancelled {
                sections = parsed
            }
        }
        .task(id: plugin.outline ? file.text : nil) {
            // After a pause in typing; the parse of an older text is dropped.
            guard plugin.outline, await (try? Task.sleep(for: .milliseconds(250))) != nil else { return }
            let text = file.text
            let parsed = await Task.detached { OutlineHeading.parse(text) }.value
            if !Task.isCancelled {
                headings = parsed
            }
        }
        .onChange(of: file.text) {
            if !plugin.dirty {
                anchor.reloaded()
            }
        }
        // A linked open's line: Edit, with the caret there.
        .onChange(of: file.loaded, initial: true) {
            guard isEnabled, file.loaded, let place = plugin.place else { return }
            plugin.place = nil
            if let line = Int(place), line > 0 {
                plugin.editing = !file.readOnly
                let starts = OutlineHeading.lineStarts(file.text)
                anchor.jump(to: max(0, starts[min(line, starts.count) - 1] - front(file)))
            }
        }
        // The card keeps the keyboard across Read and Edit.
        .onChange(of: plugin.editing) {
            if isEnabled, page.hasKeyboard(plugin.paneID) {
                plugin.wantsKeyboard = true
            }
        }
        .onChange(of: plugin.wantsKeyboard, initial: true) {
            if plugin.wantsKeyboard, isEnabled {
                plugin.wantsKeyboard = false
                Task {
                    if showsText {
                        focused = true
                    } else {
                        reading = true
                    }
                }
            }
        }
        .onChange(of: focused || reading) {
            if focused || reading {
                page.terminals.claimed(plugin.terminalID)
            }
        }
        .onChange(of: focused) {
            // On the next turn: the card's own `focused = true` comes before the view is first responder.
            if focused {
                Task {
                    anchor.tookKeyboard()
                    // ⌘F from Read, now in Edit.
                    if let find = plugin.find {
                        plugin.find = nil
                        CommandList.findInText(find)
                    }
                }
            }
        }
    }

    private var showsText: Bool {
        isEnabled && Self.showsText(plugin)
    }

    /// The file's text in a text view: Edit's, or a big file's in both modes.
    static func showsText(_ plugin: Plugin) -> Bool {
        plugin.editing || plugin.file.text.utf8.count > renderLimit
    }

    @ViewBuilder private func content(_ file: FileText) -> some View {
        if let failure = file.failure {
            FileInfo(plugin: plugin, page: page, note: failure)
        } else if !file.loaded {
            // A tile leaves the load to the card, which may not have been shown yet.
            Group {
                if isEnabled {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: plugin.kind.symbol).font(.system(size: 28)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showsText {
            let big = file.text.utf8.count > Self.renderLimit, front = front(file)
            NativeTextViewWrapper(text: front == 0 ? Bindable(file).text : part(file, body: true),
                                  configuration: big ? Self.source : Self.configuration, fontSize: 14,
                                  documentId: plugin.terminalID, isEditable: plugin.editing && !file.readOnly,
                                  isFocused: $focused, header: front == 0 ? nil : AnyView(frontMatter(file)))
                .background(AnchorView(anchor: anchor))
        } else {
            read
        }
    }

    /// Front matter's length when Edit shows it above MarkdownEngine's text, which would draw its `---` as a rule; 0
    /// for none, or a big file's plain text.
    private func front(_ file: FileText) -> Int {
        file.text.utf8.count > Self.renderLimit ? 0 : OutlineHeading.frontMatter(file.text)
    }

    /// Edit's front matter or the rest: the file's text stays whole.
    private func part(_ file: FileText, body: Bool) -> Binding<String> {
        Binding {
            let source = file.text as NSString, front = OutlineHeading.frontMatter(file.text)
            return body ? source.substring(from: front) : source.substring(to: front)
        } set: { new in
            let source = file.text as NSString, front = OutlineHeading.frontMatter(file.text)
            file.text = body ? source.substring(to: front) + new : new + source.substring(from: front)
        }
    }

    /// Edit's front matter as plain text above the body, in its column.
    private func frontMatter(_ file: FileText) -> some View {
        let text = part(file, body: false)
        // The text, hidden, sizes the editor to its wrapped lines; 5 pt in each side as the text view's.
        return SwiftUI.Text(text.wrappedValue).padding(.horizontal, 5).hidden().accessibilityHidden(true)
            .overlay {
                TextEditor(text: text).scrollContentBackground(.hidden).scrollDisabled(true).focused($reading)
                    .accessibilityIdentifier("markdown.\(plugin.paneID).front")
            }
            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            .padding(.horizontal, -5)
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 16)
            .frame(maxWidth: .infinity)
    }

    /// Read: the chat's renderer in a centered 640 pt column, a section a time.
    private var read: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    // Each by its line, which the scroll asks for: a lazy stack knows a row's id before it builds it.
                    ForEach(Array(sections.enumerated()), id: \.element.line) { index, section in
                        Markdown(text: section.text).accessibilityIdentifier("markdown.\(plugin.paneID).read.\(index)")
                    }
                }
                .environment(\.openURL, OpenURLAction { url in
                    Task { await open(url) }
                    return .handled
                })
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: target) {
                if let target {
                    proxy.scrollTo(target, anchor: .top)
                    self.target = nil
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($reading)
        .simultaneousGesture(TapGesture().onEnded { reading = true })
    }

    /// The outline's or a `#heading` link's jump: Read scrolls to it, a text view puts the caret on its line.
    private func jump(to heading: OutlineHeading) {
        if showsText {
            anchor.jump(to: max(0, heading.offset - front(plugin.file)))
        } else {
            target = sections.last { $0.line <= heading.line }?.line
        }
    }

    private var outline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(headings.enumerated()), id: \.offset) { index, heading in
                    Button {
                        jump(to: heading)
                    } label: {
                        Text(heading.title).lineLimit(1).truncationMode(.tail)
                            .font(.system(size: 12, weight: heading.level == 1 ? .semibold : .regular))
                            .padding(.leading, CGFloat(heading.level - 1) * 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).frame(height: 24)
                    }
                    .buttonStyle(ChromeStyle(radius: 6))
                    .accessibilityIdentifier("markdown.\(plugin.paneID).heading.\(index)")
                }
            }
            .padding(6)
        }
        .frame(width: 200)
        .accessibilityIdentifier("markdown.\(plugin.paneID).outline")
    }

    /// A link from Read: a web address in the browser plugin, a relative or absolute path in its own kind's,
    /// `#heading` in place.
    private func open(_ url: URL) async {
        switch url.scheme?.lowercased() {
        case "http", "https":
            await page.open(.browser, arg: url.absoluteString)
        case nil where url.path.isEmpty:
            let name = url.fragment(percentEncoded: false)?.lowercased()
            if let heading = OutlineHeading.parse(plugin.file.text).first(where: { $0.anchor == name }) {
                jump(to: heading)
            }
        case nil:
            let folder = URL(filePath: (plugin.label.arg as NSString).deletingLastPathComponent,
                             directoryHint: .isDirectory)
            let path = (URL(string: url.relativeString, relativeTo: folder) ?? url).standardized
                .path(percentEncoded: false)
            await page.open(.opening(path), arg: path)
        // A cloned repository's file is outside input: no `oriel:`, `file:`, `mailto:` or other app's link.
        default: break
        }
    }
}

/// The card's second header row: the outline's toggle, the path and `Read | Edit`; Open With follows on This Mac.
struct MarkdownToolbar: View {
    @Bindable var plugin: Plugin
    let page: Page

    var body: some View {
        let id = "pane.\(plugin.paneID)"
        Button {
            plugin.outline.toggle()
        } label: {
            Image(systemName: "sidebar.left").font(.system(size: 11)).frame(width: 22, height: 22)
        }
        .buttonStyle(ChromeStyle(selected: plugin.outline, radius: 6))
        .help("Outline")
        .accessibilityLabel("Outline")
        .accessibilityAddTraits(plugin.outline ? .isSelected : [])
        .accessibilityIdentifier("\(id).outline")
        Text(plugin.label.arg).foregroundStyle(.secondary).fontWeight(.regular).lineLimit(1)
            .truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            // Before the row's spacer: `Read | Edit` sits by Open With.
            .layoutPriority(1)
        Segments(id: "\(id).mode", options: [("Read", false), ("Edit", true)], selection: $plugin.editing)
            .fixedSize()
            .disabled(plugin.file.readOnly)
    }
}
