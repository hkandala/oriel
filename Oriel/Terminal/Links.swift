#if os(macOS)
    import AppKit
    import Observation

    /// Links ⌘-clicked in a terminal (a URL libghostty found, or OSC 8) open in the default browser: http and https
    /// only (design: links).
    @MainActor @Observable
    final class Links {
        static let shared = Links()
        /// With `-recordLinks YES` (e2e), links are kept here instead of opened.
        private(set) var recorded: [String] = []

        func open(_ text: String) {
            guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()) else { return }
            if UserDefaults.standard.bool(forKey: "recordLinks") {
                recorded.append(text)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }
#endif
