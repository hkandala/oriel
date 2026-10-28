import HerdrKit
import SwiftUI

/// One row of the chat (future-work/chat-view#detail-levels).
struct ChatRowView: View, Equatable {
    let row: ChatRow
    let paneID: String
    let open: Bool
    let toggle: () -> Void
    @Environment(\.look) private var look

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.open == rhs.open && lhs.paneID == rhs.paneID
    }

    var body: some View {
        switch row {
        case let .user(_, text): UserBubble(text: text, paneID: paneID)
        case let .summary(_, text, since):
            HStack(spacing: 6) {
                if let since {
                    WorkingDots()
                    // Its time goes on while it works.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(text + " " + ChatHistory.duration(context.date.timeIntervalSince(since)))
                    }
                } else {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                    Text(text)
                }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityValue(text)
            .accessibilityIdentifier("chat.\(paneID).summary")
        case let .reply(_, text):
            Markdown(text: text).accessibilityIdentifier("chat.\(paneID).reply")
        case .thinking:
            Text("Thought").font(.system(size: 12)).italic().foregroundStyle(.tertiary)
        case let .stack(_, tools): ToolStack(tools: tools, open: open, paneID: paneID, toggle: toggle)
        case let .todos(_, todos): Plan(todos: todos)
        case let .note(_, text, failed):
            Label(text, systemImage: failed ? "exclamationmark.triangle.fill" : "stop.circle")
                .font(.system(size: 12)).foregroundStyle(failed ? AnyShapeStyle(look.error) : AnyShapeStyle(.secondary))
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityValue(text)
                .accessibilityIdentifier("chat.\(paneID).note")
        }
    }
}

/// The user's message, as in Messages: the accent color, on the right.
struct UserBubble: View {
    let text: String
    let paneID: String
    /// On its way: not in the history yet.
    var sending = false

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .foregroundStyle(Look.onAccent)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.accentColor, in: .rect(cornerRadius: 16))
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityValue(text)
            .accessibilityIdentifier("chat.\(paneID).\(sending ? "sending" : "user")")
    }
}

/// A run of tool calls as a stacked glass card: a summary and the latest call on its front, one or two edges under it
/// for the calls inside; open, a row per call, with an edit's diff. A click opens or closes it.
private struct ToolStack: View {
    let tools: [ChatTool]
    let open: Bool
    let paneID: String
    let toggle: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        let running = tools.contains { $0.result == nil }
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(ChatTool.summary(tools)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if running {
                    WorkingDots()
                } else if let start = tools.first?.started, let end = tools.last?.ended,
                          end.timeIntervalSince(start) >= 1
                {
                    Text(ChatHistory.duration(end.timeIntervalSince(start))).font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            ForEach(Array((open ? tools : Array(tools.suffix(1))).enumerated()), id: \.offset) { _, tool in
                ToolRow(tool: tool, diff: open)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: shape)
        .background(alignment: .bottom) {
            // The calls inside: one edge for two, two for more.
            if !open, tools.count > 1 {
                ForEach(1 ... min(2, tools.count - 1), id: \.self) { edge in
                    shape.fill(.primary.opacity(0.06))
                        .padding(.horizontal, CGFloat(edge) * 7)
                        .frame(height: 12).offset(y: CGFloat(edge) * 4)
                }
            }
        }
        .padding(.bottom, !open && tools.count > 1 ? CGFloat(min(2, tools.count - 1)) * 4 : 0)
        .contentShape(.rect)
        .onTapGesture(perform: toggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(open ? "open" : "closed")
        .accessibilityAction(named: open ? "Close" : "Open", toggle)
        .accessibilityIdentifier("chat.\(paneID).stack")
    }
}

/// `bash npm test · exit 1   4.2s`: the tool, its target, its result, its time.
private struct ToolRow: View {
    let tool: ChatTool
    let diff: Bool
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if tool.result == nil {
                    ProgressView().controlSize(.mini)
                }
                Text(tool.name).italic().foregroundStyle(.secondary)
                Text(tool.target).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                if let result = tool.result, !result.isEmpty {
                    Text("· " + result)
                        .foregroundStyle(tool.failed ? AnyShapeStyle(look.error) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                } else if tool.result == nil {
                    Text("· running").foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                if diff, let start = tool.started, let end = tool.ended, end.timeIntervalSince(start) >= 1 {
                    Text(ChatHistory.duration(end.timeIntervalSince(start))).foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 12))
            if diff, !tool.diff.isEmpty {
                Diff(lines: tool.diff)
            }
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

/// A todo list: done items struck through, the one in progress in the accent color.
private struct Plan: View {
    let todos: [ChatTodo]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Plan").foregroundStyle(.secondary)
                Spacer()
                Text("\(todos.count(where: \.done)) of \(todos.count)").foregroundStyle(.tertiary)
            }
            ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                Label {
                    Text(todo.text).strikethrough(todo.done).foregroundStyle(todo.done ? .secondary : .primary)
                } icon: {
                    Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
        }
        .font(.system(size: 12))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}

/// Claude's question with its options; a click answers once every question has an answer.
struct QuestionCard: View {
    let question: ChatQuestion
    let paneID: String
    let answer: ([String: String]) -> Void
    @State private var answers: [String: String] = [:]
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(question.items, id: \.text) { item in
                Label(item.text, systemImage: "questionmark.circle.fill").font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(look.needsYou)
                FlowButtons(options: item.options, chosen: answers[item.text], paneID: paneID) { option in
                    guard !question.answered else { return }
                    answers[item.text] = option
                    if answers.count == question.items.count {
                        answer(answers)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(look.needsYou.opacity(0.12)), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.\(paneID).question")
    }
}

private struct FlowButtons: View {
    let options: [String]
    let chosen: String?
    let paneID: String
    let pick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button { pick(option) } label: {
                    Text(option).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
                .tint(chosen == option ? .accentColor : nil)
                .accessibilityIdentifier("chat.\(paneID).option.\(option)")
            }
        }
    }
}
