import XCTest

extension OrielUITests {
    /// A click on an empty card or on an error makes the browser the keyboard card, as a click on a page does. A failed
    /// address stays in the field, and Reload loads that address again, not the page before it.
    func testABrowserKeepsAFailedAddressAndTakesClicksOffItsPage() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("browser clicks")
        try await waitForPrompt(left)
        let page = try await writePages(from: left)
        element("tab.\(tab)").click()
        element("terminal.\(left)").click()
        let (browser, _) = try await chooseBrowser(besides: left, in: tab)
        let address = element("browser.\(browser).address")
        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        element("browser.\(browser).empty").click()
        XCTAssertTrue(hasKeyboard(address))

        app.typeText("\(page)\r")
        XCTAssertTrue(pageText("oriel-page-one").exists(within: 5))
        let port = Int.random(in: 47100 ... 47900)
        address.click()
        app.typeText("localhost:\(port)\r")
        let message = element("browser.\(browser).message")
        XCTAssertTrue(message.has(\.stringValue, "Nothing answers on localhost:\(port)", within: 5),
                      message.stringValue)
        let failed = address.value as? String ?? ""
        XCTAssertTrue(failed.hasPrefix("http://localhost:\(port)"), failed)
        keepScreenshot("failed address")

        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        message.click()
        XCTAssertTrue(hasKeyboard("browser.\(browser)"))

        try await send("python3 -m http.server \(port) --bind 127.0.0.1 -d /tmp/oriel-e2e-browser\r", to: left)
        // The first python3 on CI starts slowly (xcrun).
        try await waitFor(left, times: 300) { $0.contains("Serving HTTP") }
        element("browser.\(browser).retry").click()
        XCTAssertTrue(pageText("Directory listing for /").exists(within: 5))
        XCTAssertEqual(address.value as? String, failed)
    }
}
