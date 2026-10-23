import HerdrKit
import SwiftUI

/// The program icon catalog (`resources/icons/catalog.json`, bundled).
let programIcons: [ProgramIcon] = {
    // Without it every pane would draw the neutral tile: loud in a debug build.
    guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
        assertionFailure("no catalog.json in the app")
        return []
    }
    do {
        return try JSONDecoder().decode([ProgramIcon].self, from: Data(contentsOf: url))
    } catch {
        assertionFailure("program icon catalog: \(error)")
        return []
    }
}()

/// A program's colored tile, as in Rex: the catalog's tile and glyph colors, a dark outline and a faint highlight
/// at the top.
struct ProgramTile: View {
    let icon: String
    /// The placeholder's: the program's first letter.
    var letter: String?
    @Environment(\.displayScale) private var scale

    var body: some View {
        let colors = programIcons.first { $0.id == icon }?.tile
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        // The glyphs carry their own padding in a 24 pt box.
        ProgramMark(icon: icon, letter: letter, size: 17)
            .foregroundStyle(Color(hex: colors?.glyph))
            .frame(width: 22, height: 18)
            .background(Color(hex: colors?.background), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top,
                                                       endPoint: .center), lineWidth: 1))
            .overlay(shape.inset(by: -0.5 / scale).stroke(.black.opacity(0.45), lineWidth: 1 / scale))
            .accessibilityHidden(true)
    }
}

/// The program's glyph alone, for card headers.
struct ProgramGlyph: View {
    let icon: String
    var letter: String?

    var body: some View {
        ProgramMark(icon: icon, letter: letter, size: 16).foregroundStyle(.secondary).accessibilityHidden(true)
    }
}

/// The catalog's template image, or the placeholder's letter.
private struct ProgramMark: View {
    let icon: String
    let letter: String?
    let size: CGFloat

    var body: some View {
        if icon == "placeholder", let letter {
            Text(letter).font(.system(size: size * 0.65, weight: .bold, design: .rounded))
        } else {
            Image("program.\(icon)").resizable().frame(width: size, height: size)
        }
    }
}

/// A tab's panes as overlapping tiles, the first in front and each next one 4 pt to the right behind it. A ring cut
/// around each tile in front keeps the layers apart on any background.
struct IconStack: View {
    let panes: [HostStore.Pane]
    /// The front tile's badge: the tab's state.
    var badge: AgentState?

    var body: some View {
        ZStack(alignment: .leading) {
            // Back to front.
            ForEach(Array(panes.enumerated()).reversed(), id: \.element.id) { index, pane in
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).frame(width: 24, height: 20)
                        .blendMode(.destinationOut)
                    ProgramTile(icon: pane.iconID, letter: pane.letter)
                        .overlay(alignment: .topTrailing) { StatusBadge(state: index == 0 ? badge : nil) }
                }
                .frame(width: 22, height: 18)
                .offset(x: CGFloat(index) * 4)
            }
        }
        .compositingGroup()
        .frame(width: 22 + CGFloat(max(panes.count - 1, 0)) * 4, alignment: .leading)
    }
}
