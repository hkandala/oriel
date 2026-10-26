import AppKit
import UniformTypeIdentifiers
import XCTest

/// The About panel (phase 33): one short line per credit, and a link to the full license texts bundled in the app.
extension OrielUITests {
    func testAboutPanelListsShortCreditsAndLinksTheLicenseTexts() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        app.menuBarItems["Oriel"].menuItems["About Oriel"].click()
        let panel = app.dialogs.firstMatch
        XCTAssertTrue(panel.exists(within: 3))
        let attachment = XCTAttachment(screenshot: panel.screenshot())
        attachment.name = "about"
        attachment.lifetime = .keepAlways
        add(attachment)
        let credits = panel.textViews.firstMatch
        let lines = (credits.value as? String ?? "").split(separator: "\n")
        XCTAssertTrue(lines.contains("Ghostty · MIT"), "\(lines)")
        XCTAssertTrue(lines.contains("Simple Icons · CC0-1.0"), "\(lines)")
        XCTAssertTrue(lines.allSatisfy { $0.count <= 40 }, "\(lines)")

        // The link opens the bundled texts in TextEdit, where it opens .txt files and is not open already: the test
        // quits it after.
        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        let opener = NSWorkspace.shared.urlForApplication(toOpen: .plainText)
        guard opener?.lastPathComponent == "TextEdit.app", textEdit.state == .notRunning else { return }
        addTeardownBlock { textEdit.terminate() }
        credits.links["License Texts"].click()
        let texts = textEdit.windows.matching(NSPredicate(format: "title BEGINSWITH 'Acknowledgements'")).firstMatch
        XCTAssertTrue(texts.exists(within: 10))
    }
}
