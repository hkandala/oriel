import HerdrKit
import SwiftUI

/// One row of the chat (ui/chat-view#messages).
struct ChatRowView: View, Equatable {
    let row: ChatRow
    let paneID: String
    /// A run's counts: "Ran 3 commands, read 2 files".
    let counts: String
    /// An open run's steps, copied from the history only while it is open; nil: closed.
    let steps: [ChatEntry]?
    let toggle: () -> Void
    /// The tool calls opened to their input and output.
    let opened: Set<String>
    let toggleTool: (String) -> Void
    @Environment(\.look) private var look

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        // Only an open run reads `opened`.
        lhs.row == rhs.row && lhs.counts == rhs.counts && lhs.steps == rhs.steps && lhs.paneID == rhs.paneID
            && (lhs.steps == nil || lhs.opened == rhs.opened)
    }

    var body: some View {
        switch row {
        // More room between a turn and the user's messages than between a turn's rows.
        case let .user(_, text): UserBubble(text: text, paneID: paneID).padding(.vertical, 8)
        case .stack:
            ToolStack(counts: counts, steps: steps, paneID: paneID, toggle: toggle, opened: opened,
                      toggleTool: toggleTool)
        case let .worked(_, seconds):
            let text = seconds.map { "Worked " + ChatHistory.duration($0) } ?? "Worked"
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityValue(text)
                .accessibilityIdentifier("chat.\(paneID).worked")
        case let .reply(_, text):
            Markdown(text: text).accessibilityIdentifier("chat.\(paneID).reply")
                .bubble(look.receivedBubble).padding(.leading, -Composer.inset).padding(.trailing, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
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

/// The chat's loader, under the running turn: Working's icon and "Working 29s".
struct WorkingRow: View {
    let since: Date?

    var body: some View {
        HStack(spacing: 6) {
            StateIcon(state: .working)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(since.map { "Working " + ChatHistory.duration(context.date.timeIntervalSince($0)) } ?? "Working")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }
}

/// The user's message, as in Messages: blue, on the right.
struct UserBubble: View {
    let text: String
    let paneID: String
    /// On its way: not in the history yet.
    var sending = false
    @Environment(\.look) private var look

    var body: some View {
        // Its own line breaks kept: Markdown joins a paragraph's lines.
        Markdown(text: text.replacingOccurrences(of: "\n", with: "  \n"))
            .foregroundStyle(Look.onAccent)
            // Its links in its own text color, not the accent it sits on.
            .tint(Look.onAccent)
            .bubble(look.sentBubble)
            .padding(.trailing, -Composer.inset)
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityValue(text)
            .accessibilityIdentifier("chat.\(paneID).\(sending ? "sending" : "user")")
    }
}

extension View {
    /// A message's bubble, as in Messages (ui/chat-view#what-it-looks-like). Its text sits as far in as the reply
    /// box's, and its outer side reaches as far out as the box: the caller pulls it out by `Composer.inset`, so its
    /// text keeps the messages' edge.
    func bubble(_ color: Color) -> some View {
        padding(.horizontal, Composer.inset).padding(.vertical, 8).background(color, in: .rect(cornerRadius: 18))
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
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.options, id: \.self) { option in
                        Button { pick(option, for: item) } label: {
                            Text(option).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.glass)
                        .tint(answers[item.text] == option ? .accentColor : nil)
                        .accessibilityIdentifier("chat.\(paneID).option.\(option)")
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

    private func pick(_ option: String, for item: ChatQuestion.Item) {
        guard !question.answered else { return }
        answers[item.text] = option
        if answers.count == question.items.count {
            answer(answers)
        }
    }
}
