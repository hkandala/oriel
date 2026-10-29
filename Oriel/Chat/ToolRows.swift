import HerdrKit
import SwiftUI

/// A run of tool calls as one quiet line (ui/chat-view#detail-levels), so the replies stand out; open, a row per call
/// and per thinking.
struct ToolStack<Header: View>: View {
    let steps: [ChatEntry]
    let open: Bool
    let paneID: String
    let toggle: () -> Void
    /// The calls opened to their input and output.
    let opened: Set<String>
    let toggleTool: (String) -> Void
    @ViewBuilder let header: Header

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    header.lineLimit(1).layoutPriority(1)
                    Chevron(open: open)
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 6).frame(height: 24)
            }
            .buttonStyle(ChromeStyle(radius: 6))
            .accessibilityValue(open ? "open" : "closed")
            .accessibilityIdentifier("chat.\(paneID).stack")
            if open {
                ForEach(steps) { step in
                    if let tool = step.tool {
                        ToolRow(tool: tool, open: opened.contains(tool.id), paneID: paneID) { toggleTool(tool.id) }
                    } else {
                        // Lined up with the tool rows around it: their icon and height. A lone thought between
                        // replies (`ChatRowView`) has neither.
                        HStack(spacing: 6) {
                            Icon(symbol: "text.bubble")
                            Text("Thought").italic().foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 6).frame(height: 22)
                    }
                }
                .padding(.leading, 12)
            }
        }
        .font(.system(size: 12))
        // The header's text lines up with the replies; the hover fill reaches past it.
        .padding(.horizontal, -6)
    }
}

/// `terminal  bash npm test · exit 1   4.2s`; open, its input (an edit's diff) and its output.
private struct ToolRow: View {
    let tool: ChatTool
    let open: Bool
    let paneID: String
    let toggle: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Icon(symbol: Self.symbol(tool.category))
                    Text(tool.name).foregroundStyle(.secondary)
                    Text(tool.target).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if let result = tool.result, !result.isEmpty {
                        Text(result).foregroundStyle(tool.failed ? AnyShapeStyle(look.error) : AnyShapeStyle(.tertiary))
                            .lineLimit(1)
                    } else if tool.result == nil {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer(minLength: 4)
                    Time(start: tool.started, end: tool.ended)
                    Chevron(open: open)
                }
                .padding(.horizontal, 6).frame(height: 22)
            }
            .buttonStyle(ChromeStyle(radius: 6))
            .accessibilityValue(open ? "open" : "closed")
            .accessibilityIdentifier("chat.\(paneID).tool")
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    if !tool.diff.isEmpty {
                        Diff(lines: tool.diff)
                    } else if !tool.input.isEmpty {
                        ToolDetail(title: "Input", text: tool.input, id: "chat.\(paneID).tool.input")
                    }
                    if !tool.output.isEmpty {
                        ToolDetail(title: "Output", text: tool.output, id: "chat.\(paneID).tool.output")
                    }
                }
                .padding(.leading, 26).padding(.bottom, 4)
            }
        }
    }

    /// Squares and upright or wide rectangles only, so they read as one size.
    static func symbol(_ category: ChatTool.Category) -> String {
        switch category {
        case .read: "doc.text"
        case .edit: "square.and.pencil"
        case .command: "terminal"
        case .search: "doc.text.magnifyingglass"
        case .other: "curlybraces.square"
        }
    }
}

private struct Icon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(.tertiary).frame(width: 13, height: 13)
            .frame(width: 14).accessibilityHidden(true)
    }
}

/// A call's input or output: monospaced, selectable, at most 180 pt tall, then it scrolls.
private struct ToolDetail: View {
    let title: String
    let text: String
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            // One scroll view per axis: inside the strip's sideways one, a scroll view of both axes lost every vertical
            // scroll (only its scroll bar moved it).
            ScrollView {
                ScrollView(.horizontal) {
                    // The id on the text, which moves as it scrolls.
                    Text(text).font(.system(size: 11, design: .monospaced)).lineSpacing(2).textSelection(.enabled)
                        .fixedSize().accessibilityIdentifier(id).padding(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180).fixedSize(horizontal: false, vertical: true)
            .background(.primary.opacity(0.04), in: .rect(cornerRadius: 6))
        }
    }
}

private struct Chevron: View {
    let open: Bool

    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(open ? 90 : 0))
            .accessibilityHidden(true)
    }
}

/// How long it took, from a second on.
struct Time: View {
    let start: Date?
    let end: Date?

    var body: some View {
        if let start, let end, end.timeIntervalSince(start) >= 1 {
            Text(ChatHistory.duration(end.timeIntervalSince(start))).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}

/// An edit's changed lines, numbered, at most 40.
private struct Diff: View {
    let lines: [ChatTool.DiffLine]
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.prefix(40).enumerated()), id: \.offset) { _, line in
                HStack(spacing: 8) {
                    Text("\(line.number)").foregroundStyle(.tertiary).frame(minWidth: 24, alignment: .trailing)
                    Text("\(String(line.mark)) \(line.text)").lineLimit(1)
                    Spacer(minLength: 0)
                }
                .background(line.mark == "+" ? look.finished.opacity(0.15)
                    : line.mark == "-" ? look.error.opacity(0.15) : .clear)
            }
            if lines.count > 40 {
                Text("\(lines.count - 40) more lines").foregroundStyle(.tertiary).padding(.leading, 32)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 4)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 6))
    }
}
