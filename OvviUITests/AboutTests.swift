import AppKit
import UniformTypeIdentifiers
import XCTest

/// Ovvi's About window: the icon, name and version, and a button that opens every credit and license text,
/// bundled in the app.
extension OvviUITests {
    func testAboutWindowOpensTheAcknowledgements() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        app.menuBarItems["Ovvi"].menuItems["About Ovvi"].click()
        let about = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'about'")).firstMatch
        XCTAssertTrue(about.exists(within: 3))
        keepScreenshot("about", of: about)
        XCTAssertTrue(about.staticTexts["Ovvi"].exists)
        XCTAssertTrue(about.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Version ' OR value BEGINSWITH 'Version '")).firstMatch
            .exists)
        about.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(about.vanishes(within: 2))
        app.menuBarItems["Ovvi"].menuItems["About Ovvi"].click()
        XCTAssertTrue(about.exists(within: 3))

        // The button opens the bundled texts in TextEdit, where it opens .txt files and is not open already: the test
        // quits it after.
        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        let opener = NSWorkspace.shared.urlForApplication(toOpen: .plainText)
        guard opener?.lastPathComponent == "TextEdit.app", textEdit.state == .notRunning else { return }
        addTeardownBlock { textEdit.terminate() }
        element("about.acknowledgements", in: about).click()
        let texts = textEdit.windows.matching(NSPredicate(format: "title BEGINSWITH 'Acknowledgements'")).firstMatch
        XCTAssertTrue(texts.exists(within: 10))
    }
}
