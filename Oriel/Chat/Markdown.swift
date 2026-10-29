import SwiftUI

/// A reply's Markdown (ui/chat-view#where-messages-come-from), drawn block by block: `Text` draws a block's inline
/// styles but runs the blocks together.
struct Markdown: View {
    let text: String

    enum Kind: Equatable {
        case text, code, quote
        case heading(Int)
    }

    struct Block {
        let kind: Kind
        var text: AttributedString
        /// A list item's bullet or number; nil outside a list.
        var marker: String?
        /// How many lists hold it.
        var depth = 0
    }

    var body: some View {
        let blocks = Self.blocks(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let marker = block.marker {
                        Text(marker).foregroundStyle(.secondary).frame(minWidth: 12, alignment: .trailing)
                    }
                    content(block)
                }
                // Under its list's bullets; a list item's later paragraph also under the item's text.
                .padding(.leading, CGFloat(max(0, block.depth - (block.marker == nil ? 0 : 1))) * 18)
                .padding(.top, index == 0 ? 0 : Self.space(blocks[index - 1], block))
            }
        }
        .font(.system(size: Self.size(.text)))
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

    @ViewBuilder private func content(_ block: Block) -> some View {
        switch block.kind {
        case .code:
            ScrollView(.horizontal) {
                Text(block.text).font(.system(size: 12.5, design: .monospaced)).lineSpacing(2).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .scrollIndicators(.never)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 8))
        case let .heading(level):
            Text(block.text).font(.system(size: Self.size(block.kind), weight: level < 3 ? .bold : .semibold))
        case .quote:
            Text(block.text).foregroundStyle(.secondary).padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(.tertiary).frame(width: 3) }
        case .text: Text(block.text)
        }
    }

    /// A block's font size: 14 pt, and headings by their level.
    private static func size(_ kind: Kind) -> CGFloat {
        if case let .heading(level) = kind {
            [22, 18, 16][min(max(level, 1), 3) - 1]
        } else {
            14
        }
    }

    /// The space above a block: wide before a heading, narrow under one and between list items.
    private static func space(_ above: Block, _ block: Block) -> CGFloat {
        switch (above.kind, block.kind) {
        case (_, .heading(1)), (_, .heading(2)): 22
        case (_, .heading): 16
        case (.heading, _): 8
        default: above.marker != nil && block.marker != nil ? 6 : 12
        }
    }

    /// Runs of the same innermost block (a paragraph, a list item, a code block) make one block.
    static func blocks(_ text: String) -> [Block] {
        guard let parsed = try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible,
        )) else { return [Block(kind: .text, text: AttributedString(text))] }
        var blocks: [Block] = []
        var last: Int?, items: Set<Int> = []
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let identity = components.first?.identity
            var piece = AttributedString(parsed[run.range])
            piece.presentationIntent = nil
            if identity == last, identity != nil, !blocks.isEmpty {
                blocks[blocks.count - 1].text += piece
                continue
            }
            last = identity
            var block = block(components.map(\.kind), piece)
            // A list item's later paragraphs line up under its first, with no bullet of their own.
            if let item = components.first(where: { $0.kind.isListItem })?.identity, !items.insert(item).inserted {
                block.marker = nil
            }
            blocks.append(block)
        }
        return blocks.map { block in
            var block = block
            switch block.kind {
            // A code block's last newline is no line of its own.
            case .code where block.text.characters.last == "\n": block.text.characters.removeLast()
            case .code: break
            // Inline code at 0.9 of its block's size (a monospaced face reads larger), on a faint fill.
            default:
                for run in block.text.runs where run.inlinePresentationIntent?.contains(.code) == true {
                    block.text[run.range].font = .system(size: size(block.kind) * 0.9, design: .monospaced)
                    block.text[run.range].backgroundColor = .primary.opacity(0.08)
                }
            }
            return block
        }
    }

    /// A new block of its innermost kind; a list item gets its bullet or number.
    private static func block(_ kinds: [PresentationIntent.Kind], _ piece: AttributedString) -> Block {
        let depth = kinds.count { $0 == .unorderedList || $0 == .orderedList }
        var kind = Kind.text, marker: String?
        for (index, component) in kinds.enumerated() {
            switch component {
            case .codeBlock where kind == .text: kind = .code
            case let .header(level) where kind == .text: kind = .heading(level)
            // A quote keeps its bar around a heading too.
            case .blockQuote where kind != .code: kind = .quote
            case let .listItem(ordinal) where marker == nil:
                // The list that holds this item, the next component out.
                marker = kinds.dropFirst(index + 1)
                    .first == .orderedList ? "\(ordinal)." : ["•", "◦", "▪"][(depth - 1) % 3]
            default: break
            }
        }
        return Block(kind: kind, text: piece, marker: marker, depth: depth)
    }
}

private extension PresentationIntent.Kind {
    var isListItem: Bool {
        if case .listItem = self {
            true
        } else {
            false
        }
    }
}
