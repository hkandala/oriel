import AppKit
import HerdrKit
import SwiftUI

/// A `field` with `"style": "path"` (File Explorer's root), as the browser's address: at rest the value with the home
/// as `~` on This Mac, its last parts when long; a click shows the whole path selected, to edit. Return sends it
/// (`submit`), tidied (`..`, `.` and `//` resolved; `~` on This Mac), Esc puts it back. A path the page refuses shakes
/// the field (a beep with Reduce Motion), which keeps the typed text. Its symbol is a button that sends no value
/// (Choose Folder…).
struct PathField: View {
    let control: PluginManifest.Control
    let plugin: Plugin
    let page: Page
    let identifier: String
    @State private var draft = ""
    @FocusState private var editing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var still: Bool {
        reduceMotion && !Animation.forceMotion
    }

    /// An absolute path's text with `.`, `..`, `//` and a last `/` resolved; links stay (`/private/tmp` is no `/tmp`).
    static func tidy(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        var parts: [Substring] = []
        for part in path.split(separator: "/") where part != "." {
            if part == ".." {
                _ = parts.popLast()
            } else {
                parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    var body: some View {
        let id = control.id ?? "", value = control.value?.text ?? "", remote = page.store.machine.isRemote
        let header = plugin.header, shown = remote ? value : (value as NSString).abbreviatingWithTildeInPath
        HStack(spacing: 6) {
            Button { header.send?(["id": id]) } label: {
                Image(systemName: control.symbol ?? "folder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Choose Folder…")
            .accessibilityLabel("Choose Folder…")
            .accessibilityIdentifier("\(identifier).choose")
            TextField(control.label ?? "", text: $draft)
                .focused($editing)
                // Hidden under the short path while not editing; not by opacity: SwiftUI focuses no view at 0.
                .foregroundStyle(editing ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear))
                .accessibilityIdentifier(identifier)
                .overlay(alignment: .leading) {
                    if !editing {
                        Text(shown).lineLimit(1).truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                            .onTapGesture { editing = true }
                            // The field's value is the whole path already.
                            .accessibilityHidden(true)
                    }
                }
                .onSubmit {
                    let path = Self.tidy(remote ? draft : (draft as NSString).expandingTildeInPath)
                    if path == value {
                        editing = false
                    } else {
                        header.send?(["id": id, "value": path, "submit": true])
                    }
                }
                .onExitCommand {
                    draft = value
                    editing = false
                    plugin.web.view.takeKeyboard()
                }
        }
        .fieldCapsule()
        .overlay { Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5).opacity(editing ? 1 : 0) }
        .focusEffectDisabled()
        .keyframeAnimator(initialValue: 0.0, trigger: still ? 0 : header.refused[id] ?? 0) { field, shift in
            field.offset(x: shift)
        } keyframes: { _ in
            KeyframeTrack {
                for shift in [-6.0, 6, -4, 4, 0] {
                    LinearKeyframe(shift, duration: 0.06)
                }
            }
        }
        .onChange(of: header.refused[id]) {
            if still {
                NSSound.beep()
            }
        }
        // A new root: the field shows it and lets go.
        .onChange(of: value, initial: true) {
            draft = value
            editing = false
        }
        .onChange(of: editing) {
            guard editing else {
                draft = value
                return
            }
            page.tookKeyboard(plugin.terminalID)
            // Selected whole once the field has the keyboard, as the browser's address.
            DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil) }
        }
    }
}
