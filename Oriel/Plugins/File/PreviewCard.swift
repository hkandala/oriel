import AVKit
import HerdrKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A preview card's file and the view its row 2 zooms (phase 42's spec, item 2): an image, a PDF, audio or video,
/// else the info view. Reloads on a change on disk.
@MainActor @Observable
final class Preview {
    enum Content {
        case image(NSImage), pdf(PDFDocument)
        /// The file to play, and its hash: the player starts again when the file changes.
        case media(URL, String)
        /// Why there is nothing to show, if not the file's type.
        case info(String?)
    }

    enum Zoom {
        case fit, smaller, bigger, actual
    }

    private(set) var content: Content?
    /// A PDF's page, from 1, and its pages.
    var page = (number: 0, count: 0)
    @ObservationIgnored weak var scroll: NSScrollView?
    @ObservationIgnored weak var pdf: PDFView?
    /// Weak: the plugin keeps this.
    private(set) weak var plugin: Plugin?
    private let machine: Machine
    @ObservationIgnored private var hash: String?

    init(plugin: Plugin, machine: Machine) {
        self.plugin = plugin
        self.machine = machine
    }

    var path: String {
        plugin?.label.arg ?? ""
    }

    var type: UTType? {
        UTType(filenameExtension: (path as NSString).pathExtension)
    }

    /// The card's `.task(id: path)`.
    func run() async {
        let exec = await machine.exec()
        await load(exec)
        for await _ in Files.watch(path, exec: exec) {
            await load(exec)
        }
    }

    private func load(_ exec: any Exec) async {
        guard let type, [.image, .pdf, .audiovisualContent].contains(where: type.conforms) else {
            content = .info(nil)
            return
        }
        do {
            let contents = try await Files.read(path, exec: exec)
            guard contents.hash != hash else { return }
            hash = contents.hash
            if type.conforms(to: .pdf) {
                content = PDFDocument(data: contents.data).map(Content.pdf) ?? .info("Not a PDF")
            } else if type.conforms(to: .image) {
                content = NSImage(data: contents.data).map(Content.image) ?? .info("Not an image")
            } else if machine.isRemote {
                // The player reads a file. ponytail: one per version in the temporary folder, which the system
                // empties.
                let copy = FileManager.default.temporaryDirectory.appending(
                    path: "oriel-preview-\(contents.hash.filter(\.isNumber)).\((path as NSString).pathExtension)",
                )
                try contents.data.write(to: copy)
                content = .media(copy, contents.hash)
            } else {
                content = .media(URL(filePath: path), contents.hash)
            }
        } catch {
            // A file that comes back the same shows again.
            hash = nil
            content = .info(FileText.reason(error))
        }
    }

    func zoom(_ zoom: Zoom) {
        if let pdf {
            switch zoom {
            case .fit: pdf.autoScales = true
            case .smaller: pdf.zoomOut(nil)
            case .bigger: pdf.zoomIn(nil)
            case .actual: pdf.scaleFactor = 1
            }
        } else if let scroll, let image = scroll.documentView {
            switch zoom {
            case .fit: scroll.magnify(toFit: image.frame)
            case .smaller: scroll.animator().magnification /= 1.25
            case .bigger: scroll.animator().magnification *= 1.25
            case .actual: scroll.animator().magnification = 1
            }
        }
    }
}

extension Page {
    /// The card's preview, made once.
    func preview(_ plugin: Plugin) -> Preview {
        if let preview = plugin.preview {
            return preview
        }
        let preview = Preview(plugin: plugin, machine: store.machine)
        plugin.preview = preview
        return preview
    }
}

/// The preview kind's content.
struct PreviewCard: View {
    let plugin: Plugin
    let page: Page
    /// False in an overview tile, which draws its own copy and leaves the work and the zoom to the card.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let preview = page.preview(plugin), id = "preview.\(plugin.paneID)"
        Group {
            switch preview.content {
            case let .image(image): ImageScroll(image: image, preview: preview).accessibilityIdentifier("\(id).image")
            case let .pdf(document): PDFPages(document: document, preview: preview)
                .accessibilityIdentifier("\(id).pdf")
            case let .media(url, version): Player(url: url, plugin: plugin).id(version)
                .accessibilityIdentifier("\(id).player")
            case let .info(note): FileInfo(plugin: plugin, page: page, note: note)
            case nil: PluginLoader(kind: .preview)
            }
        }
        .takesKeyboard(plugin, page)
        .task(id: plugin.label.arg) {
            if isEnabled {
                await preview.run()
            }
        }
    }
}

/// Row 2 of a preview card: the path; zoom for an image or a PDF, and a PDF's page.
struct PreviewBar: View {
    let plugin: Plugin
    let preview: Preview

    var body: some View {
        let id = "pane.\(plugin.paneID)"
        Text(preview.path).foregroundStyle(.secondary).fontWeight(.regular).lineLimit(1).truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("\(id).path")
        switch preview.content {
        case .image, .pdf:
            if case .pdf = preview.content {
                Text("\(preview.page.number) of \(preview.page.count)").foregroundStyle(.secondary)
                    .fontWeight(.regular).monospacedDigit().fixedSize()
                    .accessibilityIdentifier("\(id).page")
            }
            HStack(spacing: 0) {
                IconButton(symbol: "aspectratio", help: "Fit", size: 22) { preview.zoom(.fit) }
                    .accessibilityIdentifier("\(id).zoom.fit")
                IconButton(symbol: "minus.magnifyingglass", help: "Zoom Out", size: 22) { preview.zoom(.smaller) }
                    .accessibilityIdentifier("\(id).zoom.out")
                IconButton(symbol: "plus.magnifyingglass", help: "Zoom In", size: 22) { preview.zoom(.bigger) }
                    .accessibilityIdentifier("\(id).zoom.in")
                IconButton(symbol: "1.magnifyingglass", help: "Actual Size", size: 22) { preview.zoom(.actual) }
                    .accessibilityIdentifier("\(id).zoom.actual")
            }
        default:
            EmptyView()
        }
    }
}

/// A file with nothing to show: its icon, name, size and kind (Open With is in row 2).
struct FileInfo: View {
    let plugin: Plugin
    let page: Page
    let note: String?
    @State private var size: Int?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let path = plugin.label.arg, type = UTType(filenameExtension: (path as NSString).pathExtension) ?? .data
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(for: type)).resizable().frame(width: 64, height: 64)
                .padding(.bottom, 6)
            Text((path as NSString).lastPathComponent).font(.system(size: 13, weight: .semibold))
            Text([size?.formatted(.byteCount(style: .file)), type.localizedDescription].compactMap(\.self)
                .joined(separator: " · "))
                .foregroundStyle(.secondary)
            if let note {
                Text(note).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(plugin.kind.rawValue).\(plugin.paneID).info")
        .task(id: path) {
            if isEnabled {
                size = try? await Files.size(path, exec: page.store.machine.exec())
            }
        }
    }
}

/// An image in a scroll view that zooms, centered when smaller than the card.
private struct ImageScroll: NSViewRepresentable {
    let image: NSImage
    let preview: Preview

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.contentView = CenteringClip()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.02
        scroll.maxMagnification = 32
        scroll.documentView = NSImageView()
        if context.environment.isEnabled {
            preview.scroll = scroll
            scroll.addGestureRecognizer(KeyboardClick(preview.plugin))
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context _: Context) {
        guard let view = scroll.documentView as? NSImageView, view.image !== image else { return }
        view.image = image
        view.frame = NSRect(origin: .zero, size: image.size)
        // Fit when bigger than the card, once it has its size.
        Task {
            scroll.magnification = 1
            if image.size.width > scroll.bounds.width || image.size.height > scroll.bounds.height {
                scroll.magnify(toFit: view.frame)
            }
        }
    }
}

/// Keeps a document smaller than the view in its middle.
private final class CenteringClip: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposed)
        if let document = documentView?.frame {
            if rect.width > document.width {
                rect.origin.x = (document.width - rect.width) / 2
            }
            if rect.height > document.height {
                rect.origin.y = (document.height - rect.height) / 2
            }
        }
        return rect
    }
}

/// A PDF's pages at the card's width, with the page on screen for row 2.
private struct PDFPages: NSViewRepresentable {
    let document: PDFDocument
    let preview: Preview

    func makeCoordinator() -> Pages {
        Pages(preview)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        guard context.environment.isEnabled else { return view }
        preview.pdf = view
        view.addGestureRecognizer(KeyboardClick(preview.plugin))
        // By selector: the center lets go of the coordinator by itself.
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Pages.changed),
                                               name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            context.coordinator.changed(Notification(name: .PDFViewPageChanged, object: view))
        }
    }

    final class Pages: NSObject {
        private weak var preview: Preview?

        init(_ preview: Preview) {
            self.preview = preview
        }

        @objc func changed(_ note: Notification) {
            guard let view = note.object as? PDFView, view === preview?.pdf,
                  let document = view.document else { return }
            preview?.page = ((view.currentPage.map(document.index) ?? 0) + 1, document.pageCount)
        }
    }
}

/// The system player for audio and video; a new file makes a new one (`id`).
private struct Player: NSViewRepresentable {
    let url: URL
    let plugin: Plugin

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        if context.environment.isEnabled {
            view.addGestureRecognizer(KeyboardClick(plugin))
        }
        return view
    }

    func updateNSView(_: AVPlayerView, context _: Context) {}
}

extension View {
    /// A content that is no text view takes the keyboard, as phase 42's placeholder: on a click, and when the page
    /// gives it to the card.
    func takesKeyboard(_ plugin: Plugin, _ page: Page) -> some View {
        modifier(TakesKeyboard(plugin: plugin, page: page))
    }
}

private struct TakesKeyboard: ViewModifier {
    let plugin: Plugin
    let page: Page
    @FocusState private var focused: Bool
    /// False in an overview tile, which leaves the keyboard to the card.
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .simultaneousGesture(TapGesture().onEnded { plugin.wantsKeyboard = true })
            .onChange(of: plugin.wantsKeyboard, initial: true) {
                if plugin.wantsKeyboard, isEnabled {
                    plugin.wantsKeyboard = false
                    Task { focused = true }
                }
            }
            .onChange(of: focused) {
                if focused {
                    page.terminals.claimed(plugin.terminalID)
                }
            }
    }
}

/// A click on a preview's AppKit view, which SwiftUI's taps miss: the card takes the keyboard (`takesKeyboard`).
private final class KeyboardClick: NSClickGestureRecognizer {
    private weak var plugin: Plugin?

    init(_ plugin: Plugin?) {
        self.plugin = plugin
        super.init(target: nil, action: nil)
        target = self
        action = #selector(clicked)
        delaysPrimaryMouseButtonEvents = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func clicked() {
        plugin?.wantsKeyboard = true
    }
}
