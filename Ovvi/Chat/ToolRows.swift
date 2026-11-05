import HerdrKit
import SwiftUI

/// A run of tool calls as one quiet line of its counts and a chevron (ui/chat-view#tool-calls), so the replies stand
/// out; open, a row per call and per thinking. Its rows are made only while it is open.
struct ToolStack: View {
    let counts: String
    /// Nil: closed.
    let steps: [ChatEntry]?
    let paneID: String
    let toggle: () -> Void
    /// The calls opened to their input and output.
    let opened: Set<String>
    let toggleTool: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Text(counts).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                    Chevron(open: steps != nil)
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, Composer.inset).frame(height: 24)
            }
            .buttonStyle(ChromeStyle(radius: 6))
            .accessibilityValue(steps != nil ? "open" : "closed")
            .accessibilityIdentifier("chat.\(paneID).stack")
            if let steps {
                ForEach(steps) { step in
                    if let tool = step.tool {
                        ToolRow(tool: tool, open: opened.contains(tool.id), paneID: paneID) { toggleTool(tool.id) }
                        // A codemode script's calls, under its name.
                        ForEach(tool.calls, id: \.id) { call in
                            ToolRow(tool: call, open: opened.contains(call.id), paneID: paneID) { toggleTool(call.id) }
                        }
                        .padding(.leading, 20)
                    } else {
                        // Lined up with the tool rows around it: their icon and height.
                        HStack(spacing: 6) {
                            Icon(symbol: "text.bubble")
                            Text("Thought").italic().foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, Composer.inset).frame(height: 22)
                    }
                }
                .padding(.leading, 12)
            }
        }
        .font(.system(size: 12))
        // On a reply bubble's place and width: its text on the replies' edge, its hover fill as far out as a bubble.
        .replyPlace()
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
                .padding(.horizontal, Composer.inset).frame(height: 22)
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
                // Under the tool's name: past its 14 pt icon and the row's 6 pt spacing.
                .padding(.leading, Composer.inset + 20).padding(.bottom, 4)
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
            ScrollView([.vertical, .horizontal]) {
                // The id on the text, which moves as it scrolls.
                Text(text).font(.system(size: 11, design: .monospaced)).lineSpacing(2).textSelection(.enabled)
                    .fixedSize().accessibilityIdentifier(id).padding(8)
            }
            // Text narrower than the box at its left.
            .defaultScrollAnchor(.topLeading)
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
private struct Time: View {
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
