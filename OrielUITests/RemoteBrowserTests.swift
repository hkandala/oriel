import XCTest

/// Browser cards and their machine (ui/browser#remote-localhost). The test server names the
/// process that connected to it: WebKit on This Mac, sshd through a remote machine's proxy. On CI Key Host is this Mac
/// over SSH (`scripts/ci-sshd.sh`), so one port serves both machines.
extension OrielUITests {
    /// A server on `port` in the pane's shell, which answers "via=‹the process that connected› host=‹Host›". Its
    /// script goes as base64: the runner is sandboxed, and a shell of the session writes it.
    func serveWho(_ port: Int, from pane: String) async throws {
        let script = """
        import http.server, subprocess, sys
        class Who(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                end = "127.0.0.1:%d->" % self.client_address[1]
                out = subprocess.run(["lsof", "+c", "0", "-nP", "-iTCP@" + end[:-2], "-Fcn"],
                                     capture_output=True, text=True).stdout.split("\\n")
                who = command = ""
                for line in out:
                    if line.startswith("c"):
                        command = line[1:]
                    elif line.startswith("n" + end):
                        who = command
                body = ("via=%s host=%s" % (who, self.headers["Host"])).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        # Threads: WebKit keeps a spare connection open, which held a one-thread server's next page for 30 s.
        server = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Who)
        print("oriel-who-ready", flush=True)
        server.serve_forever()
        """
        let file = "/tmp/oriel-e2e-who.py", encoded = Data(script.utf8).base64EncodedString()
        try await send("echo \(encoded) | base64 -d >\(file) && clear && python3 \(file) \(port)\r", to: pane)
        // The first python3 on CI starts slowly (xcrun).
        try await waitFor(pane, times: 300) { $0.contains("oriel-who-ready") }
    }

    func whoText(_ prefix: String, in window: XCUIElement) -> XCUIElement {
        window.webViews.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", prefix)).firstMatch
    }

    /// One browser pane on two machines at once: This Mac's window loads This Mac's `localhost:<port>` directly, Key
    /// Host's loads Key Host's through its proxy (sshd connects) as `key-host.localhost`, and shows `localhost` with
    /// the machine's name.
    func testARemoteBrowserCardLoadsItsMachinesLocalhost() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        let first = app.windows[identifier]
        let (tab, left) = try await createWorkspace("remote localhost")
        let workspace = workspace(of: tab)
        element("workspace.\(workspace)").click()
        try await waitForPrompt(left)
        let port = Int.random(in: 47100 ... 47900)
        try await serveWho(port, from: left)
        let browser = try await split(left)
        try await Self.call(
            one,
            "pane.rename",
            ["pane_id": browser, "label": "oriel:browser#e2erem http://localhost:\(port)/"],
        )
        XCTAssertTrue(whoText("via=com.apple.WebKit", in: first).exists(within: 10))
        XCTAssertFalse(element("browser.\(browser).machine", in: first).exists)

        element("titlebar.machine", in: first).click()
        app.menuItems["Key Host"].firstMatch.click()
        let remote = try otherWindow(than: identifier)
        element("workspace.\(workspace)", in: remote).click()
        element("tab.\(tab)", in: remote).click()
        let page = whoText("via=sshd", in: remote)
        XCTAssertTrue(page.exists(within: connect))
        XCTAssertTrue((page.value as? String ?? "").hasSuffix("host=key-host.localhost:\(port)"), "\(page.value ?? "")")
        XCTAssertEqual(element("browser.\(browser).address", in: remote).value as? String, "http://localhost:\(port)/")
        XCTAssertTrue(element("browser.\(browser).machine", in: remote).exists)
        keepScreenshot("remote browser card", of: remote)

        // A port nothing listens on: the proxy's refusal at once (ssh's own close made WebKit wait 60 s).
        element("browser.\(browser).address", in: remote).click()
        app.typeText("localhost:\(port + 1)\r")
        let message = element("browser.\(browser).message", in: remote)
        XCTAssertTrue(until(5) { message.value as? String == "Nothing answers on localhost:\(port + 1) on Key Host" },
                      "\(message.value ?? "")")
    }
}
