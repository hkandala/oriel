import Markdown
import SwiftUI

/// swift-markdown has its own `Text`, `Image`, `Link` and `Table`: SwiftUI's `Text` here, the others by module.
private typealias Text = SwiftUI::Text

/// A reply's Markdown (ui/chat-view#what-it-looks-like), parsed by swift-markdown (cmark-gfm, with tables, task lists
/// and strikethrough) and drawn block by block.
struct Markdown: View {
    let text: String

    var body: some View {
        Blocks(container: Document(parsing: text))
            .font(.system(size: 14))
            .lineSpacing(4)
            .textSelection(.enabled)
            // Web and mail links only: a transcript (or a page the agent quotes) could hold `file:` or `oriel:` ones.
            .environment(\.openURL, OpenURLAction { url in
                ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
            })
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityValue(text)
    }
}

/// A document's, a quote's or a list item's blocks, one under the other.
private struct Blocks: View {
    let container: any Markup

    var body: some View {
        let blocks = Array(container.children)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                let space = index == 0 ? 0 : Self.space(blocks[index - 1], blocks[index])
                Block(markup: blocks[index]).padding(.top, space)
            }
        }
    }

    /// Wide before a heading, narrow under one and inside a list item, 12 pt between other blocks.
    private static func space(_ above: any Markup, _ block: any Markup) -> CGFloat {
        if let heading = block as? Heading {
            heading.level < 3 ? 22 : 16
        } else if above is Heading {
            8
        } else {
            block.parent is ListItem ? 6 : 12
        }
    }
}

private struct Block: View {
    let markup: any Markup

    var body: some View {
        switch markup {
        case let heading as Heading:
            let size: CGFloat = [22, 18, 16][min(max(heading.level, 1), 3) - 1]
            let weight: Font.Weight = heading.level < 3 ? .bold : .semibold
            Text(Inline.text(heading, size: size)).font(.system(size: size, weight: weight))
        case let paragraph as Paragraph:
            let images = paragraph.children.compactMap { $0 as? Markdown::Image }
            if !images.isEmpty, images.count == paragraph.childCount {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(images.indices, id: \.self) { Picture(image: images[$0]) }
                }
            } else {
                Text(Inline.text(paragraph, size: 14))
            }
        case let code as CodeBlock:
            ScrollView(.horizontal) {
                // A code block's last newline is no line of its own.
                Text(code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)
                    .font(.system(size: 12.5, design: .monospaced)).lineSpacing(2).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .scrollIndicators(.never)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 8))
        case is BlockQuote:
            Blocks(container: markup).foregroundStyle(.secondary).padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(.tertiary).frame(width: 3) }
        case let list as ListItemContainer:
            ListBlock(list: list)
        case let table as Markdown::Table:
            TableGrid(table: table)
        case is ThematicBreak:
            Divider().padding(.vertical, 4)
        case let html as HTMLBlock:
            Text(html.rawHTML.trimmingCharacters(in: .newlines)).font(.system(size: 12.5, design: .monospaced))
        default:
            Text(markup.format())
        }
    }
}

/// Items hang behind their bullet (•, ◦, ▪ by depth), number or checkbox, 18 pt in per level.
private struct ListBlock: View {
    let list: any ListItemContainer

    var body: some View {
        let items = Array(list.listItems)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(items[index], index).foregroundStyle(.secondary).frame(minWidth: 12, alignment: .trailing)
                    Blocks(container: items[index])
                }
            }
        }
    }

    @ViewBuilder private func marker(_ item: ListItem, _ index: Int) -> some View {
        if let checkbox = item.checkbox {
            SwiftUI::Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
        } else if let ordered = list as? OrderedList {
            Text("\(Int(ordered.startIndex) + index).")
        } else {
            Text(["•", "◦", "▪"][depth % 3])
        }
    }

    /// How many lists hold this one.
    private var depth: Int {
        sequence(first: list.parent) { $0?.parent }.prefix { $0 != nil }.count { $0 is ListItemContainer }
    }
}

/// A table on a faint frame: the head on a fill, a line between rows, each column aligned as written.
private struct TableGrid: View {
    let table: Markdown::Table

    var body: some View {
        let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows.indices, id: \.self) { row in
                if row > 0 {
                    Divider()
                }
                GridRow {
                    ForEach(rows[row].indices, id: \.self) { column in
                        let alignment = alignment(column)
                        Text(Inline.text(rows[row][column], size: 14)).fontWeight(row == 0 ? .semibold : nil)
                            .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                            .background(row == 0 ? AnyShapeStyle(.primary.opacity(0.05)) : AnyShapeStyle(.clear))
                            .gridColumnAlignment(alignment)
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        switch column < table.columnAlignments.count ? table.columnAlignments[column] : nil {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }
}

/// An image alone in its paragraph, from the web only: a path is on the pane's machine, which may be another one.
private struct Picture: View {
    let image: Markdown::Image

    var body: some View {
        let alt = Text(Inline.text(image, size: 14)).foregroundStyle(.secondary)
        if let url = image.source.flatMap(URL.init(string:)), ["http", "https"].contains(url.scheme?.lowercased()) {
            AsyncImage(url: url) { $0.resizable().scaledToFit().frame(maxHeight: 400) } placeholder: { alt }
        } else {
            alt
        }
    }
}

/// A block's inline styles as one string: `Text` draws its emphasis, strikethrough and links.
private enum Inline {
    static func text(_ markup: any Markup, size: CGFloat) -> AttributedString {
        markup.children.reduce(into: AttributedString()) { result, child in
            switch child {
            case let text as Markdown::Text: result += linked(text.string)
            case let code as InlineCode:
                // At 0.9 of its block's size (a monospaced face reads larger), on a faint fill.
                var code = AttributedString(code.code)
                code.font = .system(size: size * 0.9, design: .monospaced)
                code.backgroundColor = .primary.opacity(0.08)
                result += code
            case is Emphasis: result += styled(child, size, .emphasized)
            case is Strong: result += styled(child, size, .stronglyEmphasized)
            case is Strikethrough: result += styled(child, size, .strikethrough)
            case let link as Markdown::Link:
                var label = Self.text(link, size: size)
                label.link = link.destination.flatMap(URL.init(string:))
                result += label
            case let image as Markdown::Image:
                // Inside text, its description, a link to it.
                var label = Self.text(image, size: size)
                label.link = image.source.flatMap(URL.init(string:))
                result += label
            // A break as a space or a newline, HTML as written.
            default: result += AttributedString((child as? InlineMarkup)?.plainText ?? "")
            }
        }
    }

    private static func styled(_ markup: any Markup, _ size: CGFloat,
                               _ intent: InlinePresentationIntent) -> AttributedString
    {
        var text = text(markup, size: size)
        for run in text.runs {
            text[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(intent)
        }
        return text
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// A bare web address as a link (GFM's autolinks, which swift-markdown leaves as text); not a bare name such as
    /// `Oriel.app`.
    private static func linked(_ string: String) -> AttributedString {
        var text = AttributedString(string)
        for match in detector?.matches(in: string, range: NSRange(string.startIndex..., in: string)) ?? [] {
            guard let range = Range(match.range, in: string), let url = match.url,
                  ["http://", "https://", "www."].contains(where: string[range].lowercased().hasPrefix),
                  let start = AttributedString.Index(range.lowerBound, within: text),
                  let end = AttributedString.Index(range.upperBound, within: text) else { continue }
            text[start ..< end].link = url
        }
        return text
    }
}
