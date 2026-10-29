import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The tree's view: tells the card when it takes the keyboard, and takes it once in a window.
final class Outline: NSOutlineView {
    var onKeyboard: () -> Void = {}
    var wantsKeyboard = false {
        didSet { viewDidMoveToWindow() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsKeyboard, let window else { return }
        wantsKeyboard = false
        // On the next turn: a first responder set during an update is undone.
        DispatchQueue.main.async { window.makeFirstResponder(self) }
    }

    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took {
            onKeyboard()
        }
        return took
    }
}

/// A tree row: the file's icon and name, its git letter (a dot for a folder with changes); dimmed when ignored.
final class FileRow: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("files.row")
    private let letter = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        let icon = NSImageView(), name = Name(labelWithString: "")
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        letter.setContentHuggingPriority(.required, for: .horizontal)
        letter.setAccessibilityElement(false)
        imageView = icon
        textField = name
        let stack = NSStackView(views: [icon, name, letter])
        stack.spacing = 6
        stack.distribution = .fill
        stack.edgeInsets.right = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func show(_ node: FileTree.Node, look: Look, id: String) {
        let type = node.isFolder ? .folder : UTType(filenameExtension: (node.name as NSString).pathExtension) ?? .data
        imageView?.image = NSWorkspace.shared.icon(for: type)
        textField?.stringValue = node.name
        textField?.textColor = node.ignored ? .tertiaryLabelColor : .labelColor
        imageView?.alphaValue = node.ignored ? 0.45 : 1
        letter.stringValue = node.letter.map { node.isFolder ? "●" : String($0) } ?? ""
        letter.font = .systemFont(ofSize: node.isFolder ? 7 : 11, weight: .semibold)
        letter.textColor = node.letter.map { NSColor(look.git($0)) }
        // On the name: the outline's own cell element stands in for this view.
        textField?.setAccessibilityIdentifier(id)
        (textField as? Name)?.value = node.ignored ? "Ignored" : node.letter.map(String.init) ?? ""
    }
}

/// A row's name, whose accessibility value is the row's git letter, or Ignored.
private final class Name: NSTextField {
    var value = ""

    override func accessibilityValue() -> String? {
        value
    }
}
