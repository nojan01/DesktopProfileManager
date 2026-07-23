import XCTest
@testable import DesktopProfileManager

final class DesktopProfileManagerTests: XCTestCase {
    func testProfileNamesAreValidatedWithoutSilentCollisions() {
        XCTAssertEqual(Profiles.validatedName("Work 2026"), "Work 2026")
        XCTAssertNil(Profiles.validatedName("Work/Home"))
        XCTAssertNil(Profiles.profilePath("Work/Home"))
    }

    func testImportedProfileNameIsNormalized() {
        XCTAssertEqual(Profiles.importName(" Work/Home "), "WorkHome")
        XCTAssertNil(Profiles.importName("///"))
    }

    func testShellReadsLargeStandardOutputBeforeWaitingForExit() {
        let result = Shell.run("/bin/sh", ["-c", "head -c 131072 /dev/zero | tr '\\0' x"], timeout: 5)
        XCTAssertEqual(result.code, 0)
        XCTAssertEqual(result.output.count, 131_072)
    }

    func testBrowserTabsAcceptOnlyUniqueHTTPURLs() {
        let urls = BrowserTabs.validURLs([
            "https://example.com",
            "https://example.com",
            "http://localhost:8080/path",
            "file:///private/secret",
            "not a url",
        ])
        XCTAssertEqual(urls, ["https://example.com", "http://localhost:8080/path"])
    }

    func testBrowserTabsParseSkipsUnsupportedValues() {
        let parsed = BrowserTabs.parse([
            "com.apple.Safari": ["https://example.com", "invalid"],
            "com.google.Chrome": "not an array",
        ])
        XCTAssertEqual(parsed, ["com.apple.Safari": ["https://example.com"]])
    }

    func testBrowserTabsCreateTabsInsideTheCurrentWindow() {
        let commands = BrowserTabs.tabCreationCommands(["https://example.com"])
        XCTAssertEqual(commands,
                       "    make new tab at end of tabs with properties {URL:\"https://example.com\"}")
        XCTAssertFalse(commands.contains("tabs of front window"))
    }
}
