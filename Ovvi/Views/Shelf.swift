import SwiftUI

/// A folded shelf at the foot of the Agents view (Settled, Archived), as T3 Code's: a quiet header with the count at
/// its end and a chevron, folded at first; open, at most five rows tall, then its rows scroll inside.
struct Shelf<Accessory: View, Content: View>: View {
    let label: String
    /// None while unknown (Archived reads lazily).
    let count: Int?
    let page: Page
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content
    /// The open shelves (`Page.openShelves`), kept across relaunches.
    @AppStorage(Page.openShelves) private var opened = ""
    @State private var under = (top: false, bottom: false)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Five 48 pt rows, 4 pt apart.
    static var tallest: Double {
        5 * 48 + 4 * 4
    }

    var body: some View {
        let key = page.shelfKey(label)
        let open = opened.split(separator: "\n").contains { $0 == key }
        VStack(spacing: 4) {
            header(key, open: open)
            if open {
                // Lazy, for Archived's pages; as tall as its rows, up to five.
                ScrollView {
                    LazyVStack(spacing: 4) { content() }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: Self.tallest)
                .fixedSize(horizontal: false, vertical: true)
                .onScrollGeometryChange(for: [Bool].self) { geometry in
                    [geometry.contentOffset.y > 0.5,
                     geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 0.5]
                } action: {
                    under = ($1[0], $1[1])
                }
                .fadeEdges(.vertical, start: under.top ? 18 : 0, end: under.bottom ? 18 : 0)
            }
        }
    }

    private func header(_ key: String, open: Bool) -> some View {
        Button {
            var lines = opened.split(separator: "\n").map(String.init)
            if open {
                lines.removeAll { $0 == key }
            } else {
                lines.append(key)
            }
            withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)) {
                opened = lines.joined(separator: "\n")
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                Spacer(minLength: 0)
                accessory()
                if let count {
                    Text("\(count)").monospacedDigit().foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
        .buttonStyle(ChromeStyle(radius: 7))
        .accessibilityLabel(count.map { "\(label) \($0)" } ?? label)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(open ? "expanded" : "collapsed")
        .accessibilityIdentifier("agents.shelf.\(label)")
    }
}

extension Shelf where Accessory == EmptyView {
    init(label: String, count: Int?, page: Page, @ViewBuilder content: @escaping () -> Content) {
        self.init(label: label, count: count, page: page, accessory: { EmptyView() }, content: content)
    }
}

extension Page {
    /// The defaults key of the open shelves, a line each (`shelfKey`).
    static let openShelves = "agentsOpen"

    /// "‹machine› ‹session› ‹label›".
    func shelfKey(_ label: String) -> String {
        "\(store.machine.id) \(id) \(label)"
    }

    func opens(_ label: String) -> Bool {
        let lines = UserDefaults.standard.string(forKey: Self.openShelves) ?? ""
        return lines.split(separator: "\n").contains { $0 == shelfKey(label) }
    }
}
