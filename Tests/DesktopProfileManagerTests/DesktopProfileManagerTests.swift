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

    func testFinderVisibilityArgumentsDisableShowingHiddenFiles() {
        XCTAssertEqual(DesktopIcons.finderVisibilityArguments(showHiddenFiles: false), [
            "write", "com.apple.finder", "AppleShowAllFiles", "-bool", "false",
        ])
    }

    func testFinderRefreshScriptEscapesDesktopPath() {
        let script = DesktopIcons.finderRefreshScript(
            desktopPath: #"/Users/Test/Desktop "quoted""#)

        XCTAssertTrue(script.contains(
            #"set desktopFolder to (POSIX file "/Users/Test/Desktop \"quoted\"") as alias"#))
        XCTAssertTrue(script.contains("update desktopFolder"))
    }

    func testBrowserTabsAcceptOnlyUniqueWebAndLocalFileURLs() {
        let urls = BrowserTabs.validURLs([
            "https://example.com",
            "https://example.com",
            "http://localhost:8080/path",
            "file:///Users/nojan/Documents/GitHub/streaming-selector/index.html",
            "file:///Users/nojan/Documents/GitHub/streaming-selector/index.html",
            "file://remote-host/Shared/index.html",
            "file:relative/index.html",
            "not a url",
        ])
        XCTAssertEqual(urls, [
            "https://example.com",
            "http://localhost:8080/path",
            "file:///Users/nojan/Documents/GitHub/streaming-selector/index.html",
        ])
    }

    func testBrowserTabsParseSkipsUnsupportedValues() {
        let parsed = BrowserTabs.parse([
            "com.apple.Safari": ["https://example.com", "file:///Users/nojan/index.html", "invalid"],
            "com.google.Chrome": "not an array",
        ])
        XCTAssertEqual(parsed, ["com.apple.Safari": ["https://example.com", "file:///Users/nojan/index.html"]])
    }

    func testBrowserTabsCreateTabsInsideTheCurrentWindow() {
        let commands = BrowserTabs.tabCreationCommands(["https://example.com"])
        XCTAssertEqual(commands,
                       "    make new tab at end of tabs with properties {URL:\"https://example.com\"}")
        XCTAssertFalse(commands.contains("tabs of front window"))
    }

    func testBrowserTabsReplaceExistingWindowsAndTabs() {
        let script = BrowserTabs.restoreScript(browserName: "Safari",
                                               urls: ["file:///Users/nojan/index.html", "https://example.com"])
        XCTAssertTrue(script.contains("delay 0.5"))
        XCTAssertTrue(script.contains("set URL of tab 1 to \"file:///Users/nojan/index.html\""))
        XCTAssertTrue(script.contains("make new tab at end of tabs with properties {URL:\"https://example.com\"}"))
        XCTAssertTrue(script.contains("repeat while (count of windows) > 1"))
        XCTAssertTrue(script.contains("close window 2"))
        XCTAssertTrue(script.contains("repeat while (count of tabs) > 1"))
        XCTAssertTrue(script.contains("close tab 2"))
        XCTAssertGreaterThanOrEqual(script.components(separatedBy: "on error").count, 3)
    }

    func testUpdateReleaseUsesDMGAssetAndIgnoresOtherAssets() throws {
        let data = try XCTUnwrap("""
        {
          "tag_name": "v1.4.0",
          "assets": [
            {"name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt"},
            {"name": "DesktopProfileManager-1.4.0.dmg", "browser_download_url": "https://example.com/app.dmg"}
          ]
        }
        """.data(using: .utf8))

        let release = try XCTUnwrap(UpdateManager.release(from: data))
        XCTAssertEqual(release.version, "1.4.0")
        XCTAssertEqual(release.assetName, "DesktopProfileManager-1.4.0.dmg")
        XCTAssertEqual(release.downloadURL, URL(string: "https://example.com/app.dmg"))
    }

    func testUpdateReleaseWithoutDMGCanStillReportVersion() throws {
        let data = try XCTUnwrap("""
        {"tag_name": "v1.4.0", "assets": []}
        """.data(using: .utf8))

        let release = try XCTUnwrap(UpdateManager.release(from: data))
        XCTAssertEqual(release.version, "1.4.0")
        XCTAssertNil(release.downloadURL)
        XCTAssertNil(release.assetName)
    }
}
