import AppKit
import HerdrKit
import SwiftUI

/// One column's text (TextKit 2, read only, no wrapping, so the two columns of Side by Side keep their rows level):
/// each row's background and gutter drawn behind it from the rows' tops.
final class DiffText: NSTextView {
    private(set) var rows: [DiffRow] = []
    /// Each row's top, then the text's bottom.
    private(set) var tops: [CGFloat] = [0]
    private var columns = 1, digits = 3
    private var width: CGFloat = 0
    private var look = Look(style: .glass, dark: true)
    var onKeyboard: (() -> Void)?
    var onOpen: ((DiffRow) -> Void)?

    static func scrolling() -> (NSScrollView, DiffText) {
        let text = DiffText(usingTextLayoutManager: true)
        text.isEditable = false
        text.drawsBackground = false
        // `fit` sizes it: NSTextView's own fit kept the first column as narrow as its scroll view.
        text.isVerticallyResizable = false
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        text.textContainer?.lineFragmentPadding = 0
        text.setAccessibilityLabel("Diff")
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = text
        scroll.contentView.postsBoundsChangedNotifications = true
        return (scroll, text)
    }

    /// Lays the whole text out at once, for its width and so that TextKit draws each row at its top.
    /// ponytail: about 190 ms for 6,700 lines, and files over 2,000 lines start folded; lay out by pages if whole
    /// 16 MB patches must open fast.
    func show(_ rows: [DiffRow], _ text: NSAttributedString, columns: Int, look: Look) {
        self.rows = rows
        // Every row is one line of a fixed height.
        var bottom: CGFloat = 0
        tops = [0] + rows.map { row in
            bottom += row.kind == .header ? DiffRow.headerHeight : DiffRow.height
            return bottom
        }
        self.look = look
        self.columns = columns
        digits = max(3, String(rows.compactMap { max($0.old ?? 0, $0.new ?? 0) }.max() ?? 0).count)
        // The gutter is the inset; with no padding the text's bounds start at 0, else NSTextView moves the text left.
        textContainerInset = NSSize(width: gutterWidth, height: 0)
        textStorage?.setAttributedString(text)
        guard let layout = textLayoutManager else { return }
        layout.ensureLayout(for: layout.documentRange)
        width = layout.usageBoundsForTextContainer.maxX + 2 * gutterWidth
        needsDisplay = true
    }

    /// As wide as the longest line and as tall as the rows, at least the scroll view's size.
    func fit(_ size: NSSize) {
        setFrameSize(NSSize(width: max(size.width, width), height: max(size.height, tops.last ?? 0)))
    }

    /// Two number columns in Unified (old, new), one per side, then the `+` or `−`.
    private var gutterWidth: CGFloat {
        CGFloat(columns) * (CGFloat(digits) * DiffRow.digitWidth + 10) + 2 * DiffRow.digitWidth + 6
    }

    func row(at offset: CGFloat) -> Int? {
        let index = (tops.firstIndex { $0 > offset } ?? tops.count) - 1
        return rows.indices.contains(index) ? index : nil
    }

    override func drawBackground(in rect: NSRect) {
        guard var index = row(at: max(0, rect.minY)) else { return }
        let gutter = [.font: DiffRow.font,
                      .foregroundColor: NSColor.tertiaryLabelColor] as [NSAttributedString.Key: Any]
        let column = CGFloat(digits) * DiffRow.digitWidth + 10
        while index < rows.count, tops[index] < rect.maxY {
            let row = rows[index]
            let frame = NSRect(x: rect.minX, y: tops[index], width: rect.width,
                               height: tops[index + 1] - tops[index])
            if let fill = fill(row.kind) {
                NSColor(fill).setFill()
                frame.fill(using: .sourceOver)
            }
            if row.kind == .filler {
                hatch(frame)
            }
            let numbers = columns == 2 ? [row.old, row.new] : [row.old ?? row.new]
            // On the text's baseline: TextKit puts a line's extra height above it.
            let baseline = frame.maxY - DiffRow.font.ascender + DiffRow.font.descender
            for (place, number) in numbers.enumerated() {
                guard let number else { continue }
                let string = String(number) as NSString
                let right = CGFloat(place + 1) * column - 6
                string.draw(at: NSPoint(x: right - string.size(withAttributes: gutter).width, y: baseline),
                            withAttributes: gutter)
            }
            if row.kind == .added || row.kind == .removed {
                (row.kind == .added ? "+" : "−").draw(at: NSPoint(x: CGFloat(numbers.count) * column, y: baseline),
                                                      withAttributes: gutter)
            }
            index += 1
        }
    }

    private func fill(_ kind: DiffRow.Kind) -> Color? {
        switch kind {
        case .added: look.finished.opacity(0.07)
        case .removed: look.error.opacity(0.07)
        case .hunk: look.working.opacity(0.1)
        case .gap: look.paneButton.opacity(0.06)
        default: nil
        }
    }

    /// No line on this side: lines at 45° every 8 pt, on x + y, so they run on through the rows of a run.
    private func hatch(_ frame: NSRect) {
        let path = NSBezierPath()
        var sum = ((frame.minX + frame.minY) / 8).rounded(.down) * 8
        while sum < frame.maxX + frame.maxY {
            path.move(to: NSPoint(x: sum - frame.minY, y: frame.minY))
            path.line(to: NSPoint(x: sum - frame.maxY, y: frame.maxY))
            sum += 8
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: frame).addClip()
        NSColor(look.paneButton.opacity(0.18)).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// ⌘-click on a line opens the file there.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), let index = row(at: point.y), rows[index].line != nil {
            onOpen?(rows[index])
            return
        }
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onKeyboard?()
        }
        return became
    }
}

/// The diff's one or two columns, and over them a header view per file shown: each at its header row, the top file's
/// pinned to the top until the next one pushes it up.
final class DiffView: NSView {
    private let scrolls: [NSScrollView]
    let texts: [DiffText]
    /// A file's header view, by its index.
    var header: ((Int) -> NSView)?
    /// The file at the top changed.
    var onCurrent: ((Int) -> Void)?
    private var headers: [Int: NSView] = [:]
    /// The header rows, for each scroll.
    private var starts: [Int] = []
    /// The files shown, by index.
    private var paths: [String] = []
    private var current = -1
    private var sideBySide = false
    private var syncing = false
    private var wantsKeyboard = false

    override var isFlipped: Bool {
        true
    }

    init() {
        let columns = [DiffText.scrolling(), DiffText.scrolling()]
        scrolls = columns.map(\.0)
        texts = columns.map(\.1)
        super.init(frame: .zero)
        clipsToBounds = true
        for scroll in scrolls {
            addSubview(scroll)
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView
                .boundsDidChangeNotification, object: scroll.contentView)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Keeps the `anchor` file (else the top one) where it was on the screen: as far into it, or at its header when
    /// it got shorter than that (folded).
    func show(_ files: [DiffFile], folded: Set<String>, sideBySide: Bool, look: Look, anchor: String? = nil) {
        let path = anchor ?? (paths.indices.contains(current) ? paths[current] : nil)
        let into = path.flatMap(paths.firstIndex).flatMap(headerTop).map { top - $0 }
        paths = files.map(\.path)
        self.sideBySide = sideBySide
        // Unified keeps no copy of Side by Side's new column.
        for (text, side) in zip(texts, sideBySide ? [DiffRow.Side.old, .new] : [.unified, nil]) {
            let (rows, string) = side.map { DiffRow.layout(files, folded: folded, side: $0, look: look) }
                ?? ([], NSAttributedString())
            text.show(rows, string, columns: side == .unified ? 2 : 1, look: look)
        }
        scrolls[1].isHidden = !sideBySide
        starts = texts[0].rows.indices.filter { texts[0].rows[$0].kind == .header }
        headers.values.forEach { $0.removeFromSuperview() }
        headers = [:]
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let into, let file = path.flatMap(paths.firstIndex), let header = headerTop(file) {
            let end = starts.first { texts[0].tops[$0] > header }.map { texts[0].tops[$0] } ?? texts[0].tops.last ?? 0
            scroll(to: header + min(into, max(0, end - header - DiffRow.headerHeight)))
        }
    }

    /// Scrolls the file's header to the top.
    func reveal(_ file: Int) {
        if let header = headerTop(file) {
            scroll(to: header)
        }
    }

    /// The next (1) or previous (-1) run of changed lines, under its file's pinned header.
    func step(_ direction: Int) {
        let text = texts[0], top = top + DiffRow.headerHeight
        let runs = text.rows.indices.filter { index in
            let changed = { (kind: DiffRow.Kind) in kind == .added || kind == .removed || kind == .filler }
            return changed(text.rows[index].kind) && (index == 0 || !changed(text.rows[index - 1].kind))
        }.map { text.tops[$0] }
        if let start = direction > 0 ? runs.first(where: { $0 > top + 1 }) : runs.last(where: { $0 < top - 1 }) {
            scroll(to: start - DiffRow.headerHeight)
        }
    }

    func takeKeyboard() {
        wantsKeyboard = true
        // After SwiftUI's update: a first responder set during one is undone.
        DispatchQueue.main.async { [weak self] in
            guard let self, wantsKeyboard, let window else { return }
            wantsKeyboard = false
            window.makeFirstResponder(texts[0])
        }
    }

    /// Out of a window, the header views go (they hold the card); the next layout makes them again.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            headers.values.forEach { $0.removeFromSuperview() }
            headers = [:]
        } else {
            needsLayout = true
            if wantsKeyboard {
                takeKeyboard()
            }
        }
    }

    override func layout() {
        super.layout()
        let half = (bounds.width / 2).rounded()
        scrolls[0].frame = sideBySide ? NSRect(x: 0, y: 0, width: half - 0.5, height: bounds.height) : bounds
        scrolls[1].frame = NSRect(x: half + 0.5, y: 0, width: bounds.width - half - 0.5, height: bounds.height)
        for (scroll, text) in zip(scrolls, texts) {
            text.fit(scroll.contentSize)
        }
        placeHeaders()
    }

    /// A wheel over a header view scrolls the diff.
    override func scrollWheel(with event: NSEvent) {
        scrolls[0].scrollWheel(with: event)
    }

    /// The left column's scroll offset.
    private var top: CGFloat {
        scrolls[0].contentView.bounds.minY
    }

    private func headerTop(_ file: Int) -> CGFloat? {
        let text = texts[0]
        return text.rows.firstIndex { $0.kind == .header && $0.file == file }.map { text.tops[$0] }
    }

    private func scroll(to offset: CGFloat) {
        let clip = scrolls[0].contentView
        let bottom = max(0, texts[0].frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(0, offset), bottom)))
        scrolls[0].reflectScrolledClipView(clip)
    }

    @objc private func scrolled(_ note: Notification) {
        guard !syncing else { return }
        if sideBySide, let moved = note.object as? NSClipView {
            syncing = true
            for scroll in scrolls where scroll.contentView !== moved {
                scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: moved.bounds.minY))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            syncing = false
        }
        placeHeaders()
    }

    private func placeHeaders() {
        let text = texts[0], top = top, height = bounds.height
        var shown: [Int: CGFloat] = [:]
        for (place, row) in starts.enumerated() {
            let own = text.tops[row] - top
            guard own < height else { break }
            let next = place + 1 < starts.count ? text.tops[starts[place + 1]] - top : .infinity
            if next > 0 {
                shown[text.rows[row].file] = min(max(own, 0), next - DiffRow.headerHeight)
            }
        }
        for (file, view) in headers where shown[file] == nil {
            view.removeFromSuperview()
            headers[file] = nil
        }
        for (file, offset) in shown {
            let view = headers[file] ?? header?(file) ?? NSView()
            if view.superview == nil {
                addSubview(view)
                headers[file] = view
            }
            view.frame = NSRect(x: 0, y: offset, width: bounds.width, height: DiffRow.headerHeight)
        }
        let pinned = starts.last { text.tops[$0] <= top + 1 }.map { text.rows[$0].file } ?? 0
        if pinned != current {
            current = pinned
            onCurrent?(pinned)
        }
    }
}
