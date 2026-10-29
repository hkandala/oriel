import SwiftUI

/// Markdown's controls in row 2: Read | Edit and the outline's toggle. The page (`web/src/markdown.ts`) shows what
/// they ask for and reports it back, so a page loaded again starts in Read with the row in step.
struct MarkdownBar: View {
    let plugin: Plugin
    @Environment(\.look) private var look

    var body: some View {
        let web = plugin.web, id = "pane.\(plugin.paneID)"
        Segments(id: "\(id).mode", options: [("Read", false), ("Edit", true)],
                 selection: Binding { web.markdown.edit } set: { web.show(edit: $0) })
        IconButton(symbol: "sidebar.left", help: "Outline", size: 22) { web.show(outline: !web.markdown.outline) }
            .foregroundStyle(web.markdown.outline ? AnyShapeStyle(.tint) : AnyShapeStyle(look.paneButton))
            .accessibilityAddTraits(web.markdown.outline ? .isSelected : [])
            .accessibilityIdentifier("\(id).outline")
    }
}

extension WebCard {
    /// Asks the Markdown page for Read or Edit and the outline shown or not: row 2 and ⌘E.
    func show(edit: Bool? = nil, outline: Bool? = nil) {
        send(["op": "markdown", "edit": edit ?? markdown.edit, "outline": outline ?? markdown.outline])
    }
}

extension CommandList {
    /// ⌘E, Edit Mode in the View menu: Read or Edit on the Markdown card with the keyboard, checked while editing.
    /// The action asks `target` when it runs: the menu bar may be older than the last keyboard move. No key over
    /// another card: a disabled item would swallow its ⌘E.
    static func editMode(_ target: @escaping @MainActor () -> Plugin?) -> Command {
        let markdown = { target().flatMap { $0.kind == .markdown ? $0.web : nil } }
        return Command(section: .view, title: "Edit Mode", key: markdown() == nil ? nil : .init("e"), symbol: "pencil",
                       keywords: "markdown read", enabled: markdown() != nil,
                       checked: markdown()?.markdown.edit == true, action: {
                           if let web = markdown() {
                               web.show(edit: !web.markdown.edit)
                           }
                       })
    }
}
