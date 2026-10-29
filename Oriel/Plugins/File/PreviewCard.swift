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
        case image(NSImage), pdf(PDFDocument), media(URL)
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
    let plugin: Plugin
    private let machine: Machine
    @ObservationIgnored private var hash: String?

    init(plugin: Plugin, machine: Machine) {
        self.plugin = plugin
        self.machine = machine
    }

    var path: String {
        plugin.label.arg
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
                // The player reads a file. ponytail: one per card in the temporary folder, which the system empties.
                let copy = FileManager.default.temporaryDirectory
                    .appending(path: "oriel-preview-\(plugin.label.iid).\((path as NSString).pathExtension)")
                try contents.data.write(to: copy)
                content = .media(copy)
            } else {
                content = .media(URL(filePath: path))
            }
        } catch {
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
            case let .media(url): Player(url: url).accessibilityIdentifier("\(id).player")
            case let .info(note): FileInfo(plugin: plugin, page: page, note: note)
            case nil: PluginLoader(kind: .preview)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding([.horizontal, .bottom], 6)
        .task(id: plugin.label.arg) {
            if isEnabled {
                await preview.run()
            }
        }
    }
}

/// Row 2 of a preview card: the path; zoom for an image or a PDF, and a PDF's page.
struct PreviewBar: View {
    let preview: Preview

    var body: some View {
        let id = "pane.\(preview.plugin.paneID)"
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
        .task(id: path) { size = try? await Files.size(path, exec: page.store.machine.exec()) }
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

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        guard context.environment.isEnabled else { return view }
        preview.pdf = view
        NotificationCenter.default
            .addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak view] _ in
                MainActor.assumeIsolated {
                    if let view {
                        shown(view)
                    }
                }
            }
        return view
    }

    func updateNSView(_ view: PDFView, context _: Context) {
        if view.document !== document {
            view.document = document
            shown(view)
        }
    }

    private func shown(_ view: PDFView) {
        guard let document = view.document else { return }
        preview.page = ((view.currentPage.map(document.index) ?? 0) + 1, document.pageCount)
    }
}

/// The system player for audio and video.
private struct Player: NSViewRepresentable {
    let url: URL

    func makeNSView(context _: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        return view
    }

    func updateNSView(_ view: AVPlayerView, context _: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            view.player = AVPlayer(url: url)
        }
    }
}
