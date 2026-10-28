import SwiftUI

/// A reply's Markdown (ui/chat-view#where-messages-come-from): `AttributedString(markdown:)` with the full
/// syntax, split into its blocks, since `Text` draws a block's inline styles but runs the blocks together. Code
/// blocks are monospaced and scroll sideways; list items get their bullet or number.
struct Markdown: View {
    let text: String

    enum Kind: Equatable {
        case text, heading, code, quote
    }

    struct Block {
        let kind: Kind
        let text: AttributedString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .code:
                    ScrollView(.horizontal) {
                        Text(block.text).font(.system(size: 12, design: .monospaced)).fixedSize().padding(8)
                    }
                    .scrollIndicators(.never)
                    .background(.primary.opacity(0.05), in: .rect(cornerRadius: 6))
                case .heading: Text(block.text).fontWeight(.semibold)
                case .quote: Text(block.text).foregroundStyle(.secondary).padding(.leading, 10)
                    .overlay(alignment: .leading) { Capsule().fill(.tertiary).frame(width: 2) }
                case .text: Text(block.text)
                }
            }
        }
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

    /// Runs of the same innermost block (a paragraph, a list item, a code block) make one block.
    static func blocks(_ text: String) -> [Block] {
        guard let parsed = try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible,
        )) else { return [Block(kind: .text, text: AttributedString(text))] }
        var blocks: [Block] = []
        var last: Int?
        for run in parsed.runs {
            let intent = run.presentationIntent
            let identity = intent?.components.first?.identity
            var piece = AttributedString(parsed[run.range])
            piece.presentationIntent = nil
            if identity == last, identity != nil, let block = blocks.popLast() {
                blocks.append(Block(kind: block.kind, text: block.text + piece))
                continue
            }
            last = identity
            blocks.append(block(intent?.components.map(\.kind) ?? [], piece))
        }
        // A code block's last newline is no line of its own.
        return blocks.map { block in
            guard block.kind == .code, block.text.characters.last == "\n" else { return block }
            var text = block.text
            text.characters.removeLast()
            return Block(kind: .code, text: text)
        }
    }

    /// A new block of its innermost kind; a list item starts with its bullet or number, indented by its depth.
    private static func block(_ kinds: [PresentationIntent.Kind], _ piece: AttributedString) -> Block {
        var kind = Kind.text, prefix = ""
        for (index, component) in kinds.enumerated() {
            switch component {
            case .codeBlock: kind = .code
            case .header: kind = .heading
            case .blockQuote: kind = .quote
            case let .listItem(ordinal) where prefix.isEmpty:
                // The list that holds this item, the next component out.
                let ordered = kinds.dropFirst(index + 1).first == .orderedList
                prefix = ordered ? "\(ordinal). " : "• "
            default: break
            }
        }
        let depth = kinds.count {
            if case .listItem = $0 {
                true
            } else {
                false
            }
        }
        let indent = String(repeating: "    ", count: max(0, depth - 1))
        return Block(kind: kind, text: AttributedString(indent + prefix) + piece)
    }
}
