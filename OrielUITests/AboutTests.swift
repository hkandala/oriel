import AppKit
import UniformTypeIdentifiers
import XCTest

/// Oriel's About window (phase 33): one line per credit, its name a link and its license beside it, and a button that
/// opens the full license texts bundled in the app.
extension OrielUITests {
    func testAboutWindowListsTheCreditsAndOpensTheLicenseTexts() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        app.menuBarItems["Oriel"].menuItems["About Oriel"].click()
        let about = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'about'")).firstMatch
        XCTAssertTrue(about.exists(within: 3))
        keepScreenshot("about", of: about)
        for (name, license) in [("Ghostty", "MIT"), ("bash-preexec", "MIT"), ("Simple Icons", "CC0-1.0"),
                                ("jj", "Apache-2.0")]
        {
            XCTAssertTrue(element("about.\(name)", in: about).links[name].exists, name)
            XCTAssertTrue(element("about.\(name)", in: about).staticTexts[license].exists, name)
        }
        XCTAssertTrue(element("about.Drawn for Oriel", in: about).staticTexts["CC0-1.0"].exists)
        about.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(about.vanishes(within: 2))
        app.menuBarItems["Oriel"].menuItems["About Oriel"].click()
        XCTAssertTrue(about.exists(within: 3))

        // The button opens the bundled texts in TextEdit, where it opens .txt files and is not open already: the test
        // quits it after.
        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        let opener = NSWorkspace.shared.urlForApplication(toOpen: .plainText)
        guard opener?.lastPathComponent == "TextEdit.app", textEdit.state == .notRunning else { return }
        addTeardownBlock { textEdit.terminate() }
        element("about.licenses", in: about).click()
        let texts = textEdit.windows.matching(NSPredicate(format: "title BEGINSWITH 'Acknowledgements'")).firstMatch
        XCTAssertTrue(texts.exists(within: 10))
    }
}
