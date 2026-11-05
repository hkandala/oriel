import AppKit
import SwiftUI

/// Glass: the desktop blurred behind the window, under the look's tint. Classic: the look's opaque color.
struct WindowBackground: View {
    let look: Look

    var body: some View {
        if look.style == .glass {
            Frosted(blending: .behindWindow, material: .hudWindow)
                .overlay(look.backdrop.blendMode(BlendMode.overlay))
                .overlay {
                    // Not the system glass: macOS draws it without its tint and wide blur in an inactive window,
                    // so the window would turn lighter and greyer.
                    if let shade = look.blurShade {
                        Frosted(blending: .withinWindow, material: .fullScreenUI).overlay(shade)
                    }
                }
                .overlay(look.window)
        } else {
            look.window
        }
    }
}

/// A blur of the desktop behind the window (SwiftUI's materials blur only what is inside it), or of the window's own
/// background.
private struct Frosted: NSViewRepresentable {
    let blending: NSVisualEffectView.BlendingMode
    let material: NSVisualEffectView.Material

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = blending
        view.material = material
        // Blurred in an inactive window too, so the look holds.
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
