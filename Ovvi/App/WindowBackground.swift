import AppKit
import SwiftUI

/// Glass: the desktop blurred behind the window, under the look's tint. Classic: the look's opaque color.
struct WindowBackground: View {
    let look: Look

    var body: some View {
        if look.style == .glass {
            Frosted().overlay(look.backdrop.blendMode(BlendMode.overlay))
                .overlay {
                    if let tint = look.glassTint {
                        Color.clear.glassEffect(.regular.tint(tint), in: .rect)
                    }
                }
                .overlay(look.window)
        } else {
            look.window
        }
    }
}

/// The Glass window's blur of the desktop. SwiftUI's materials blur only what is inside the window.
private struct Frosted: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        // Blurred in an inactive window too, so the look holds.
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
