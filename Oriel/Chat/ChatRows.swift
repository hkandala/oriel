import HerdrKit
import SwiftUI

/// One row of the chat (ui/chat-view#detail-levels).
struct ChatRowView: View, Equatable {
    let row: ChatRow
    let paneID: String
    let open: Bool
    let toggle: () -> Void
    /// The tool calls opened to their input and output.
    let opened: Set<String>
    let toggleTool: (String) -> Void
    @Environment(\.look) private var look

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.open == rhs.open && lhs.paneID == rhs.paneID && lhs.opened == rhs.opened
    }

    var body: some View {
        switch row {
        case let .user(_, text): UserBubble(text: text, paneID: paneID)
        case let .summary(_, text, since, tools) where tools.isEmpty:
            Summary(text: text, since: since)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityValue(text)
                .accessibilityIdentifier("chat.\(paneID).summary")
        case let .summary(_, text, since, tools):
            stack(tools) { Summary(text: text, since: since) }
        case let .reply(_, text):
            Markdown(text: text).accessibilityIdentifier("chat.\(paneID).reply")
        case .thinking:
            Text("Thought").font(.system(size: 12)).italic().foregroundStyle(.tertiary)
        case let .stack(_, tools):
            stack(tools) {
                if tools.contains(where: { $0.result == nil }) {
                    WorkingDots()
                }
                Text(ChatTool.summary(tools)).foregroundStyle(.secondary)
                Time(start: tools.first?.started, end: tools.last?.ended)
            }
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

    private func stack(_ tools: [ChatTool], @ViewBuilder header: () -> some View) -> some View {
        ToolStack(tools: tools, open: open, paneID: paneID, toggle: toggle, opened: opened, toggleTool: toggleTool,
                  header: header)
    }
}

/// A turn's quiet line: "Worked 1m 48s · 2 files edited", or the working dots and its time going on.
private struct Summary: View {
    let text: String
    let since: Date?

    var body: some View {
        HStack(spacing: 6) {
            if let since {
                WorkingDots()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(text + " " + ChatHistory.duration(context.date.timeIntervalSince(since)))
                }
            } else {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
                Text(text)
            }
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
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
            .font(.system(size: 14))
            .lineSpacing(3)
            .textSelection(.enabled)
            .foregroundStyle(Look.onAccent)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.accentColor, in: .rect(cornerRadius: 18))
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityValue(text)
            .accessibilityIdentifier("chat.\(paneID).\(sending ? "sending" : "user")")
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
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 8))
    }
}

/// A question the chat can answer, with its options; a click answers once every question has an answer.
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
