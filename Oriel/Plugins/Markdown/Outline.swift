import Foundation
import Markdown

/// A heading in the Markdown card's outline: its 1-based line, and where that starts in the file's text in UTF-16
/// (NSString) units.
nonisolated struct OutlineHeading: Hashable {
    let level: Int
    let title: String
    let line: Int
    let offset: Int
    /// Not inside a list or a quote: Read's sections start at one.
    let topLevel: Bool

    /// The file's headings, with swift-markdown (cmark-gfm, as GitHub reads them), but front matter's (its closing
    /// `---` makes its last line a heading).
    static func parse(_ text: String) -> [OutlineHeading] {
        var walker = Walker()
        walker.visit(Document(parsing: text))
        let starts = lineStarts(text)
        let front = frontMatter(text)
        return walker.headings.compactMap { heading in
            let line = heading.range?.lowerBound.line ?? 0
            guard line > 0, line <= starts.count, starts[line - 1] >= front else { return nil }
            return OutlineHeading(level: heading.level, title: heading.plainText, line: line, offset: starts[line - 1],
                                  topLevel: heading.parent is Document)
        }
    }

    /// Read's sections, each named by its first line: the text after the front matter, cut before each top-level
    /// heading (a ScrollViewReader reaches only its scroll view's own children). Each gets the file's link
    /// reference definitions, which may sit in another.
    static func sections(_ text: String) -> [(line: Int, text: String)] {
        let source = text as NSString, all = NSRange(location: 0, length: source.length)
        let definitions = definitionPattern?.matches(in: text, range: all).map { source.substring(with: $0.range) }
            .joined(separator: "\n") ?? ""
        let cuts = [(line: 0, offset: frontMatter(text))] + parse(text).filter(\.topLevel).map { (
            line: $0.line,
            offset: $0.offset,
        ) }
        return cuts.indices.compactMap { index in
            let end = index + 1 < cuts.count ? cuts[index + 1].offset : source.length
            guard end > cuts[index].offset else { return nil }
            let range = NSRange(location: cuts[index].offset, length: end - cuts[index].offset)
            return (cuts[index].line, source.substring(with: range) + "\n\n" + definitions)
        }
    }

    private static let definitionPattern = try? NSRegularExpression(pattern: #"^ {0,3}\[[^\]\n]+\]:[ \t]*\S.*$"#,
                                                                    options: .anchorsMatchLines)

    /// The length of the front matter, YAML between `---` lines at the top, in UTF-16 units; 0 for none.
    static func frontMatter(_ text: String) -> Int {
        frontMatterPattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.range.length ?? 0
    }

    private static let frontMatterPattern = try? NSRegularExpression(pattern: #"\A---\r?\n(.*?\r?\n)?---(\r?\n|\z)"#,
                                                                     options: .dotMatchesLineSeparators)

    /// Where each line starts, in UTF-16 units.
    static func lineStarts(_ text: String) -> [Int] {
        [0] + text.utf16.enumerated().compactMap { $0.element == 10 ? $0.offset + 1 : nil }
    }

    /// GitHub's anchor for the heading, which `#anchor` links name: lowercased, spaces to dashes, no punctuation.
    var anchor: String {
        String(title.lowercased()
            .compactMap { $0 == " " ? "-" : $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : nil })
    }
}

private nonisolated struct Walker: MarkupWalker {
    var headings: [Heading] = []

    mutating func visitHeading(_ heading: Heading) {
        headings.append(heading)
    }
}
