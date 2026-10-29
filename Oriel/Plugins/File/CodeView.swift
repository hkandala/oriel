import AppKit
import Grammars
import SwiftUI

/// A file's text in an editable TextKit 2 view: syntax colors for the lines on screen, line numbers, the current
/// line, the system find bar and undo; the jump bar's symbol at the caret.
struct CodeView: NSViewRepresentable {
    let file: FileText
    let page: Page

    /// The newest host adopts the editor, as a terminal's does: an overview tile borrows it, and the card takes it
    /// back after.
    func makeNSView(context _: Context) -> SettlingHost {
        let host = SettlingHost(), editor = file.editor ?? CodeEditor(file: file, page: page)
        file.editor = editor
        host.clipsToBounds = true
        editor.scroll.frame = host.bounds
        host.addSubview(editor.scroll)
        return host
    }

    func updateNSView(_: SettlingHost, context: Context) {
        // Only an overview's tile disables its card.
        if context.environment.isEnabled {
            file.editor?.update()
        }
    }
}

/// The text view, its gutter and its tree, and what goes between them and the file's text.
final class CodeEditor: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSTextContentStorageDelegate {
    let scroll = CodeTextView.scrollableTextView()
    /// Weak: the file text keeps this.
    private weak var file: FileText?
    private let text: CodeTextView
    private let grammar: Grammar?
    private let parser = Parser()
    private var tree: MutableTree?
    /// The file's text as the view last had it.
    private var shown: String?
    private let undo = UndoManager()
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    /// A space's width: tabs stop every four.
    private let space: CGFloat

    init(file: FileText, page: Page) {
        self.file = file
        space = " ".size(withAttributes: [.font: font]).width
        text = scroll.documentView as? CodeTextView ?? CodeTextView()
        // ponytail: no colors over 4 MB, where a parse takes about a second; parse off the main actor then. The
        // grammar and the cap hold for the first path and size.
        grammar = file.text.utf8.count <= 4 << 20 ? Grammar.of(file.path) : nil
        super.init()
        if let grammar {
            try? parser.setLanguage(grammar.language)
        }
        text.delegate = self
        text.textStorage?.delegate = self
        text.textContentStorage?.delegate = self
        text.font = font
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = space * 4
        text.defaultParagraphStyle = paragraph
        text.textColor = .labelColor
        text.drawsBackground = false
        text.isRichText = false
        text.allowsUndo = true
        text.usesFindBar = true
        text.isIncrementalSearchingEnabled = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.smartInsertDeleteEnabled = false
        text.textContainerInset = NSSize(width: 4, height: 6)
        text.textLayoutManager?.renderingAttributesValidator = { [weak self] manager, fragment in
            self?.color(fragment, manager)
        }
        text.focused = { [weak terminals = page.terminals, id = file.plugin?.terminalID ?? ""] in
            terminals?.claimed(id)
        }
        scroll.drawsBackground = false
        scroll.verticalRulerView = Gutter(text)
        scroll.rulersVisible = true
    }

    /// The file's state into the view: a reload's text, read only, the keyboard, a linked open's line.
    func update() {
        guard let file, let plugin = file.plugin else { return }
        if file.text != shown {
            // The caret and the scroll stay where they were.
            let selection = text.selectedRange(), origin = scroll.contentView.bounds.origin
            shown = file.text
            text.string = file.text
            undo.removeAllActions()
            let length = (file.text as NSString).length
            text.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        text.isEditable = !file.readOnly
        text.setAccessibilityIdentifier("file.\(plugin.paneID).text")
        text.takeKeyboard(plugin)
        if let place = plugin.place {
            Task {
                plugin.place = nil
                if let line = Int(place) {
                    show(line: line)
                }
            }
        }
    }

    private func show(line: Int) {
        let string = text.string as NSString
        var start = 0
        for _ in 1 ..< max(line, 1) where start < string.length {
            start = NSMaxRange(string.lineRange(for: NSRange(location: start, length: 0)))
        }
        let range = string.lineRange(for: NSRange(location: start, length: 0))
        text.setSelectedRange(NSRange(location: range.location, length: 0))
        text.scrollRangeToVisible(range)
    }

    // MARK: Edits

    func textDidChange(_: Notification) {
        shown = text.string
        file?.text = shown ?? ""
    }

    /// A wrapped line goes on at its own indent, as in Xcode.
    func textContentStorage(_ storage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let source = storage.textStorage, range.length > 0 else { return nil }
        let line = NSMutableAttributedString(attributedString: source.attributedSubstring(from: range))
        let indent = line.string.prefix { $0 == " " || $0 == "\t" }.reduce(CGFloat(0)) { $0 + ($1 == "\t" ? 4 : 1) }
        guard indent > 0 else { return nil }
        let style = (line.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle ?? text
            .defaultParagraphStyle ?? .default).mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.headIndent = indent * space
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        return NSTextParagraph(attributedString: line)
    }

    func undoManager(for _: NSTextView) -> UndoManager? {
        undo
    }

    func textViewDidChangeSelection(_: Notification) {
        text.setNeedsDisplay(text.visibleRect)
        scroll.verticalRulerView?.needsDisplay = true
        let symbol = symbol(at: text.selectedRange().location)
        if let file, file.symbol != symbol {
            file.symbol = symbol
        }
    }

    /// The tree follows each edit, and the lines on screen color again.
    /// ponytail: the edit's points are zero, as only byte offsets place colors; bash's heredoc scanner reads columns,
    /// so a heredoc edited on its own line may color wrong. Pass rows and columns when that shows.
    func textStorage(_ storage: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions, range: NSRange,
                     changeInLength delta: Int)
    {
        guard mask.contains(.editedCharacters) else { return }
        if let gutter = scroll.verticalRulerView as? Gutter, range.location < gutter.counted.offset {
            gutter.counted = (0, 0)
        }
        guard grammar != nil else { return }
        let zero = Point(row: 0, column: 0)
        tree?.edit(InputEdit(startByte: range.location * 2, oldEndByte: (range.upperBound - delta) * 2,
                             newEndByte: range.upperBound * 2, startPoint: zero, oldEndPoint: zero, newEndPoint: zero))
        let characters = storage.mutableString
        tree = parser.parse(tree: tree) { byte, _ in
            let start = byte / 2, length = min(characters.length - start, 4096)
            guard length > 0 else { return nil }
            var buffer = [unichar](repeating: 0, count: length)
            characters.getCharacters(&buffer, range: NSRange(location: start, length: length))
            return buffer.withUnsafeBytes { Data($0) }
        }
        if let manager = text.textLayoutManager {
            manager.invalidateRenderingAttributes(for: manager.documentRange)
        }
    }

    // MARK: Colors and symbols

    /// Colors one paragraph as TextKit lays it out: the lines on screen only. Of two captures of one node the
    /// query's first wins, as tree-sitter's highlighter does; a node inside another wins over it.
    private func color(_ fragment: NSTextLayoutFragment, _ manager: NSTextLayoutManager) {
        guard let grammar, let tree, let storage = manager.textContentManager as? NSTextContentStorage,
              let characters = text.textStorage?.mutableString else { return }
        let document = storage.documentRange.location, element = fragment.rangeInElement
        let start = storage.offset(from: document, to: element.location)
        let line = NSRange(location: start, length: storage.offset(from: element.location, to: element.endLocation))
        let cursor = grammar.highlights.execute(in: tree)
        cursor.setRange(line)
        let context = Predicate.Context(textProvider: { range, _ in characters.substring(with: range) })
        let captures = cursor.resolve(with: context).flatMap(\.captures).sorted {
            ($0.range.location, -$0.range.length, $0.patternIndex) < (
                $1.range.location,
                -$1.range.length,
                $1.patternIndex,
            )
        }
        manager.removeRenderingAttribute(.foregroundColor, for: element)
        var last: NSRange?
        for capture in captures where capture.range != last {
            guard let name = capture.name, let color = Grammar.color(name) else { continue }
            last = capture.range
            let range = NSIntersectionRange(capture.range, line)
            guard range.length > 0, let from = storage.location(document, offsetBy: range.location),
                  let end = storage.location(from, offsetBy: range.length),
                  let textRange = NSTextRange(location: from, end: end) else { continue }
            manager.addRenderingAttribute(.foregroundColor, value: color, for: textRange)
        }
    }

    /// The innermost declaration around the caret: a type, function, method or property.
    private func symbol(at location: Int) -> String {
        let characters = text.string as NSString
        var node = tree?.rootNode?.descendant(in: UInt32(location * 2) ..< UInt32(location * 2))
        while let current = node {
            let type = current.nodeType ?? ""
            if ["declaration", "definition", "_item", "_spec", "specifier"].contains(where: type.hasSuffix)
                || ["class", "module", "method", "singleton_method"].contains(type),
               !["parameter", "local", "import"].contains(where: type.contains),
               let name = Self.name(of: current)
            {
                return characters.substring(with: name.range)
            }
            node = current.parent
        }
        return ""
    }

    /// A declaration's name: its `name` field, the end of its C declarator, or its first identifier (Kotlin).
    private static func name(of node: Node) -> Node? {
        if let name = node.child(byFieldName: "name") {
            return name
        }
        if let declarator = node.child(byFieldName: "declarator") {
            return name(of: declarator) ?? declarator
        }
        return (0 ..< node.namedChildCount).lazy.compactMap { node.namedChild(at: $0) }
            .first { $0.nodeType?.hasSuffix("identifier") == true }
    }
}

/// The text view: the current line under the text, and the keyboard's claim.
final class CodeTextView: NSTextView {
    var focused: () -> Void = {}

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            focused()
        }
        return became
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if let line = caretLine {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            line.fill()
        }
    }

    /// The caret's paragraph, the width of the view.
    var caretLine: NSRect? {
        guard let manager = textLayoutManager, let storage = textContentStorage,
              let location = storage.location(storage.documentRange.location, offsetBy: selectedRange().location),
              let fragment = manager.textLayoutFragment(for: location) else { return nil }
        let frame = fragment.layoutFragmentFrame
        return NSRect(x: 0, y: frame.minY + textContainerOrigin.y, width: bounds.width, height: frame.height)
    }
}

/// Line numbers beside the text, for the paragraphs on screen; the caret's brighter.
private final class Gutter: NSRulerView {
    private let text: CodeTextView
    /// The last count, which the next starts from: scrolling counts only the lines scrolled past. An edit starts
    /// it again.
    var counted = (offset: 0, lines: 0)

    init(_ text: CodeTextView) {
        self.text = text
        super.init(scrollView: text.enclosingScrollView, orientation: .verticalRuler)
        clientView = text
        ruleThickness = 36
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_: NSRect) {
        guard let manager = text.textLayoutManager, let storage = text.textContentStorage,
              let viewport = manager.textViewportLayoutController.viewportRange else { return }
        let document = storage.documentRange.location
        var line = lines(before: storage.offset(from: document, to: viewport.location)) + 1
        let caret = text.caretLine?.minY
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        var widest: CGFloat = 0
        manager.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let top = frame.minY + text.textContainerOrigin.y
            let label = NSAttributedString(string: "\(line)", attributes: [
                .font: font,
                .foregroundColor: top == caret ? NSColor.labelColor : NSColor.tertiaryLabelColor,
            ])
            let size = label.size()
            let baseline = fragment.textLineFragments.first.map { $0.typographicBounds.minY + $0.glyphOrigin.y } ?? 0
            let origin = convert(NSPoint(x: 0, y: top), from: text).y + baseline - font.ascender
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: origin))
            widest = max(widest, size.width)
            line += 1
            return fragment.rangeInElement.endLocation.compare(viewport.endLocation) == .orderedAscending
        }
        if widest + 16 > ruleThickness {
            Task { ruleThickness = (widest + 16).rounded(.up) }
        }
    }

    /// Line breaks before the offset.
    /// ponytail: counts the characters between this offset and the last, all of them after an edit or a scroll up;
    /// keep line starts when big files scroll slowly.
    private func lines(before offset: Int) -> Int {
        let characters = text.textStorage?.mutableString ?? NSMutableString()
        if counted.offset > offset {
            counted = (0, 0)
        }
        var buffer = [unichar](repeating: 0, count: 65536)
        var scanned = counted.offset
        while scanned < offset {
            let length = min(buffer.count, offset - scanned)
            characters.getCharacters(&buffer, range: NSRange(location: scanned, length: length))
            counted.lines += buffer[..<length].count(where: { $0 == 10 })
            scanned += length
        }
        counted.offset = offset
        return counted.lines
    }
}
