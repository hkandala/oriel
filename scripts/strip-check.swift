// Run by scripts/strip-check.sh: launches Oriel on the session, then three times shows the 4th tab of w1 (⌃⌘1, ⌘4)
// and switches to w2 (⌃⌘2), and checks w2's card is drawn. The second ⌘4 selects the tab in view again, which
// draws the strip again; on the old code the switch after it showed an empty strip.
// Usage: swift scripts/strip-check.swift <Oriel binary> <session> <folder for the captures>
import AppKit

let arguments = CommandLine.arguments
let (binary, session, out) = (arguments[1], arguments[2], arguments[3])
let app = Process()
app.executableURL = URL(fileURLWithPath: binary)
app.arguments = ["-session", session, "-ApplePersistenceIgnoreState", "YES"]
try app.run()
let pid = app.processIdentifier

func fail(_ text: String) -> Never {
    print("strip-check: \(text)")
    app.terminate()
    exit(1)
}

/// The app's main window: its number, its title and its frame in points.
struct Window {
    let id: CGWindowID, title: String, frame: CGRect
}

func window() -> Window? {
    let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    for info in list
        where info[kCGWindowOwnerPID as String] as? pid_t == pid && info[kCGWindowLayer as String] as? Int == 0
    {
        let bounds = info[kCGWindowBounds as String] as? NSDictionary
        let frame = bounds.flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
        if frame.width > 400, let id = info[kCGWindowNumber as String] as? CGWindowID {
            return Window(id: id, title: info[kCGWindowName as String] as? String ?? "", frame: frame)
        }
    }
    return nil
}

/// Waits up to `seconds` for the window's title to contain `text`.
func waitForTitle(_ text: String, _ seconds: Double) -> Bool {
    for _ in 0 ..< Int(seconds * 10) {
        if window()?.title.contains(text) == true {
            return true
        }
        usleep(100_000)
    }
    return false
}

func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.postToPid(pid)
        usleep(20000)
    }
}

/// How much the brightness varies in a band under the title row, across the strip: the card's header and the shell's
/// prompt make it vary; an empty strip is one flat color.
func spread(_ path: String, frame: CGRect) -> Double {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { fail("no capture at \(path)") }
    let rep = NSBitmapImageRep(cgImage: image), scale = Double(rep.pixelsWide) / frame.width
    var values: [Double] = []
    // Under the 46 pt title row, right of the 240 pt sidebar.
    for row in stride(from: Int(50 * scale), to: Int(130 * scale), by: 2) {
        for column in stride(from: Int(260 * scale), to: Int((frame.width - 20) * scale), by: 2) {
            if let color = rep.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) {
                values.append(color.brightnessComponent)
            }
        }
    }
    let mean = values.reduce(0, +) / Double(max(values.count, 1))
    return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(values.count, 1))).squareRoot()
}

// US layout key codes.
let one: CGKeyCode = 18, two: CGKeyCode = 19, four: CGKeyCode = 21
var shown: Window?
for _ in 0 ..< 300 where shown == nil {
    usleep(100_000)
    shown = window()
}

guard shown != nil else { fail("no window") }
NSRunningApplication(processIdentifier: pid)?.activate()
// The first snapshot.
guard waitForTitle(session, 30)
else { fail("no title with the session (\(window()?.title ?? "")): no screen recording?") }
// The app takes keys a moment after its window shows.
sleep(2)
var empty: [String] = []
for round in 1 ... 3 {
    key(one, [.maskCommand, .maskControl])
    usleep(300_000)
    key(four, .maskCommand)
    guard waitForTitle("strip-w1", 5)
    else { fail("⌘4 did not show strip-w1 (\(window()?.title ?? "")): no key events?") }
    usleep(600_000)
    key(two, [.maskCommand, .maskControl])
    guard waitForTitle("strip-w2", 5) else { fail("⌃⌘2 did not show strip-w2") }
    usleep(1_000_000)
    guard let window = window() else { fail("the window went") }
    let path = "\(out)/round-\(round).png"
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", "\(window.id)", path]
    try capture.run()
    capture.waitUntilExit()
    let value = spread(path, frame: window.frame)
    print(String(format: "strip-check: round %d, spread %.3f", round, value))
    if value < 0.01 {
        empty.append(path)
    }
}

app.terminate()
if !empty.isEmpty {
    fail("the strip was empty: \(empty.joined(separator: " "))")
}

print("strip-check: every switch showed the card")
