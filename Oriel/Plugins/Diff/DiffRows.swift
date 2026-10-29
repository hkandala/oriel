import AppKit
import HerdrKit
import SwiftUI

/// One paragraph of the diff's text: what its background and gutter show.
struct DiffRow {
    enum Kind {
        case header, gap, hunk, note, context, added, removed, filler
    }

    let kind: Kind
    let file: Int
    var old: Int?
    var new: Int?
    /// The line of the file that ⌘-click opens.
    var line: Int?

    /// Unified, or one column of Side by Side.
    enum Side {
        case unified, old, new
    }

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let height: CGFloat = 18
    /// A file's header row, under its header view.
    static let headerHeight: CGFloat = 32

    /// The rows of one column and its text, a paragraph each.
    static func layout(_ files: [DiffFile], folded: Set<String>, side: Side, look: Look)
        -> ([DiffRow], NSAttributedString)
    {
        var column = Column(side: side, look: look)
        for (index, file) in files.enumerated() {
            column.add(DiffRow(kind: .header, file: index), file.path)
            guard !folded.contains(file.path) else { continue }
            if file.binary || file.hunks.isEmpty {
                column.add(DiffRow(kind: .note, file: index), file.binary ? "Binary file" : "No changes to the text")
            }
            var end = 0
            for hunk in file.hunks {
                let (start, last) = oldLines(hunk.header)
                if start - 1 > end {
                    let gap = start - 1 - end
                    column.add(DiffRow(kind: .gap, file: index), "\(gap) unmodified \(gap == 1 ? "line" : "lines")")
                }
                end = last
                column.add(DiffRow(kind: .hunk, file: index), hunk.header)
                column.add(hunk, file: index)
            }
        }
        if column.text.length > 0 {
            column.text.deleteCharacters(in: NSRange(location: column.text.length - 1, length: 1))
        }
        return (column.rows, column.text)
    }

    /// The old file's first and last line of a hunk, from its `@@ -start,count`: a count of 0 is after the start
    /// line, and no count is 1.
    static func oldLines(_ header: String) -> (Int, Int) {
        let numbers = header.split(separator: " ").dropFirst().first?.dropFirst().split(separator: ",")
            .map { Int($0) ?? 0 } ?? []
        let count = numbers.count > 1 ? numbers[1] : 1, start = (numbers.first ?? 0) + (count == 0 ? 1 : 0)
        return (start, start + count - 1)
    }

    /// A line's own paragraph and line breaks would make more paragraphs than rows: each is one UTF-16 unit, as the
    /// space that takes its place.
    static func clean(_ text: String) -> String {
        text.contains(where: { "\r\u{85}\u{2028}\u{2029}".contains($0) })
            ? String(text.map { "\r\u{85}\u{2028}\u{2029}".contains($0) ? " " : $0 }) : text
    }

    static func attributes(_ kind: Kind) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        let height = kind == .header ? headerHeight : height
        (style.minimumLineHeight, style.maximumLineHeight) = (height, height)
        style.defaultTabInterval = 4 * digitWidth
        style.tabStops = []
        // The header's text is the file's path, for copy, under its header view.
        let color: NSColor = switch kind {
        case .header: .clear
        case .gap, .hunk, .note: .secondaryLabelColor
        default: .labelColor
        }
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    static let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
}

/// One column's rows and text as they are built. Side by Side pairs each run of removed lines with the added run
/// after it and fills the shorter side with filler rows, so both columns keep the same rows.
private struct Column {
    let side: DiffRow.Side
    let look: Look
    var rows: [DiffRow] = []
    let text = NSMutableAttributedString()

    mutating func add(_ row: DiffRow, _ string: String, words: [Range<Int>] = []) {
        let start = text.length
        text.append(NSAttributedString(string: DiffRow.clean(string) + "\n", attributes: DiffRow.attributes(row.kind)))
        for word in words {
            text.addAttribute(.backgroundColor, value: NSColor((row.kind == .added ? look.finished : look.error)
                    .opacity(0.4)), range: NSRange(location: start + word.lowerBound, length: word.count))
        }
        rows.append(row)
    }

    /// A removed line opens the file where it was: at the next line the new file has.
    mutating func add(_ hunk: Hunk, file: Int) {
        var next = hunk.lines.first { $0.new != nil }?.new ?? 1
        var index = 0
        while index < hunk.lines.count {
            let line = hunk.lines[index]
            if side == .unified || line.kind == .context {
                add(line, file, at: next)
                next = line.new.map { $0 + 1 } ?? next
                index += 1
                continue
            }
            let removed = hunk.lines[index...].prefix { $0.kind == .removed }
            let added = hunk.lines[removed.endIndex...].prefix { $0.kind == .added }
            for pair in 0 ..< max(removed.count, added.count) {
                add(side == .old ? removed.dropFirst(pair).first : added.dropFirst(pair).first, file, at: next)
            }
            next = added.last?.new.map { $0 + 1 } ?? next
            index = added.endIndex
        }
    }

    private mutating func add(_ line: DiffLine?, _ file: Int, at next: Int) {
        guard let line else { return add(DiffRow(kind: .filler, file: file), "") }
        let kind: DiffRow.Kind = line.kind == .added ? .added : line.kind == .removed ? .removed : .context
        add(DiffRow(kind: kind, file: file, old: side == .new ? nil : line.old, new: side == .old ? nil : line.new,
                    line: line.new ?? next), line.text, words: line.words)
    }
}
