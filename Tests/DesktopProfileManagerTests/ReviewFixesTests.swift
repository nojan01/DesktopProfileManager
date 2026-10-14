import AppKit
import XCTest
@testable import DesktopProfileManager

final class ReviewFixesTests: XCTestCase {

    // MARK: - Profilnamen

    func testProfileNamesMustNotCollideWithInternalFiles() {
        XCTAssertNil(Profiles.validatedName("_config"))
        XCTAssertNil(Profiles.profilePath("_config"))
        XCTAssertEqual(Profiles.validatedName("Work_2"), "Work_2")
        XCTAssertEqual(Profiles.importName("_config"), "config")
        XCTAssertEqual(Profiles.importName("_ _Work"), "Work")
        XCTAssertNil(Profiles.importName("___"))
    }

    func testUniqueImportNameNumbersConflicts() {
        let taken: Set<String> = ["Work", "Work 2"]
        XCTAssertEqual(Profiles.uniqueImportName(base: "Home", exists: taken.contains), "Home")
        XCTAssertEqual(Profiles.uniqueImportName(base: "Work", exists: taken.contains), "Work 3")
        // Das Ergebnis muss selbst ein gültiger Name sein.
        XCTAssertNotNil(Profiles.validatedName(Profiles.uniqueImportName(base: "Work", exists: taken.contains)))
    }

    func testProfileIdentityComesFromFileName() {
        XCTAssertEqual(Profiles.profileName(forFileName: "Work.json"), "Work")
        XCTAssertNil(Profiles.profileName(forFileName: "_config.json"))
        XCTAssertNil(Profiles.profileName(forFileName: " Work.json"))
        XCTAssertNil(Profiles.profileName(forFileName: "Work.txt"))
    }

    // MARK: - Systemzustand / Injection

    func testDesktopViewScriptRejectsInjectedArrangement() {
        let script = SystemState.desktopViewScript([
            "arrangement": "not arranged\ndo shell script \"touch /tmp/pwned\"",
            "icon_size": 64,
        ])
        XCTAssertNotNil(script)
        XCTAssertFalse(script!.contains("do shell script"))
        XCTAssertFalse(script!.contains("arrangement of o"))
        XCTAssertTrue(script!.contains("set icon size of o to 64"))
    }

    func testDesktopViewScriptUsesConstantsAndClampsSize() {
        let script = SystemState.desktopViewScript(["arrangement": "not arranged", "icon_size": 9999])
        XCTAssertTrue(script!.contains("«constant ****narr»"))
        XCTAssertTrue(script!.contains("icon view options of window of desktop"))
        XCTAssertTrue(script!.contains("set icon size of o to 512"))
        XCTAssertNil(SystemState.desktopViewScript(["icon_size": "64; beep"]))
    }

    func testSystemStateSanitizeDropsInvalidValues() {
        let state = SystemState.sanitize([
            "appearance": 1,
            "volume": 250,
            "brightness": -3.0,
            "dock": ["orientation": "top\"; do shell script \"x", "tilesize": 64.4, "autohide": true],
            "unknown": "x",
        ])
        XCTAssertNil(state["appearance"], "Zahlen sind kein Wahrheitswert")
        XCTAssertEqual(state["volume"] as? Int, 100)
        XCTAssertEqual(state["brightness"] as? Double, 0.0)
        let dock = state["dock"] as? [String: Any]
        XCTAssertNil(dock?["orientation"])
        XCTAssertEqual(dock?["tilesize"] as? Int, 64)
        XCTAssertEqual(dock?["autohide"] as? Bool, true)
        XCTAssertNil(state["unknown"])
    }

    func testDoNotDisturbIsNoLongerOfferedButStillKnownForImports() {
        XCTAssertFalse(SystemState.optionOrder.contains { $0.key == "dnd" })
        let imported = Profiles.sanitizedImport([
            "positions": [:],
            "settings": ["system_state_keys": ["dnd", "volume", "evil"]],
            "system_state": ["dnd": true, "volume": 30],
            "hidden": ["a.txt", 5],
        ], name: "Imported")
        XCTAssertEqual(imported["profile"] as? String, "Imported")
        XCTAssertEqual((imported["settings"] as? [String: Any])?["system_state_keys"] as? [String], ["dnd", "volume"])
        XCTAssertEqual(imported["hidden"] as? [String], ["a.txt"])
    }

    func testDockChangesSkipUnchangedValues() {
        let current: [String: Any] = ["orientation": "bottom", "tilesize": 48, "autohide": false]
        XCTAssertTrue(SystemState.dockChanges(
            desired: ["orientation": "bottom", "tilesize": 48, "autohide": false], current: current).isEmpty)
        let changes = SystemState.dockChanges(
            desired: ["orientation": "left", "tilesize": 48, "magnification": true], current: current)
        XCTAssertEqual(Set(changes.keys), ["orientation", "magnification"])
    }

    func testDoNotDisturbShortcutNames() {
        XCTAssertEqual(SystemState.doNotDisturbShortcutNames(enabled: true), ["Fokus ein", "Focus On"])
        XCTAssertEqual(SystemState.doNotDisturbShortcutNames(enabled: false), ["Fokus aus", "Focus Off"])
    }

    // MARK: - JSON-Zahlen

    func testJSONNumberAcceptsFloatingPointButNotBooleans() throws {
        let json = try JSONSerialization.jsonObject(
            with: Data(#"{"x": 10.6, "y": 20, "flag": true, "w": "5"}"#.utf8)) as! [String: Any]
        XCTAssertEqual(JSONNumber.int(json["x"]), 11)
        XCTAssertEqual(JSONNumber.int(json["y"]), 20)
        XCTAssertNil(JSONNumber.int(json["flag"]))
        XCTAssertNil(JSONNumber.int(json["w"]))
        XCTAssertEqual(JSONNumber.bool(json["flag"]), true)
        XCTAssertNil(JSONNumber.bool(json["y"]))
    }

    func testPositionsFromOlderProfilesWithFloatsAreRestored() throws {
        let json = try JSONSerialization.jsonObject(
            with: Data(#"{"a.txt": {"x": 100.0, "y": 200.4}, "b.txt": {"x": "1"}}"#.utf8))
        let positions = Profiles.parsePositions(json)
        XCTAssertEqual(positions["a.txt"]?.x, 100)
        XCTAssertEqual(positions["a.txt"]?.y, 200)
        XCTAssertNil(positions["b.txt"])
    }

    // MARK: - Wiederherstellung

    func testAutomaticTriggersNeverLaunchOrQuitApps() {
        XCTAssertTrue(RestoreTrigger.manual.allowsAppLaunch)
        XCTAssertTrue(RestoreTrigger.manual.allowsQuitOthers)
        XCTAssertTrue(RestoreTrigger.login.allowsAppLaunch)
        XCTAssertFalse(RestoreTrigger.login.allowsQuitOthers)
        for trigger in [RestoreTrigger.timer, .wake, .autoSwitch] {
            XCTAssertFalse(trigger.allowsAppLaunch)
            XCTAssertFalse(trigger.allowsQuitOthers)
        }
        XCTAssertTrue(RestoreTrigger.autoSwitch.allowsHideOthers)
        XCTAssertFalse(RestoreTrigger.timer.allowsHideOthers)
        XCTAssertFalse(RestoreTrigger.wake.allowsHideOthers)
        XCTAssertFalse(RestoreTrigger.login.allowsHideOthers)
    }

    func testProfileSettingsCanOnlyRestrictGlobalSwitches() {
        let all: [String: Any] = [:]
        let plan = Profiles.restorePlan(settings: all, includeWallpaper: false,
                                        includeApps: false, iconsOnly: false)
        XCTAssertFalse(plan.apps)
        XCTAssertFalse(plan.browserTabs)
        XCTAssertFalse(plan.wallpaper)
        XCTAssertTrue(plan.positions)

        let restricted = Profiles.restorePlan(
            settings: ["restore_apps": false, "capture_hidden": false],
            includeWallpaper: true, includeApps: true, iconsOnly: false)
        XCTAssertFalse(restricted.apps)
        XCTAssertFalse(restricted.hiddenIcons)
        XCTAssertTrue(restricted.wallpaper)

        let iconsOnly = Profiles.restorePlan(settings: all, includeWallpaper: true,
                                             includeApps: true, iconsOnly: true)
        XCTAssertFalse(iconsOnly.apps || iconsOnly.wallpaper || iconsOnly.systemStateAndCleanup)
    }

    func testBrowsersWithSavedTabsAreKeptWhenHidingOthers() {
        let mail = Apps.AppInfo(name: "Mail", bundleID: "com.apple.mail", path: "/System/Applications/Mail.app")
        let keep = Profiles.appsToKeep(profileApps: [mail],
                                       browserTabs: ["com.google.Chrome": ["https://example.com"]])
        XCTAssertEqual(keep.compactMap(\.bundleID), ["com.apple.mail", "com.google.Chrome"])
    }

    func testVisibilityChangesOnlyContainDifferences() {
        let current = [
            DesktopIcons.DesktopItem(name: "a.txt", hidden: false),
            DesktopIcons.DesktopItem(name: "b.txt", hidden: true),
        ]
        let changes = DesktopIcons.visibilityChanges(
            desired: [("a.txt", false), ("b.txt", false), ("gone.txt", true)], current: current)
        XCTAssertEqual(changes.map(\.name), ["b.txt", "gone.txt"])
    }

    func testFinderDefaultsTruthiness() {
        XCTAssertTrue(DesktopIcons.isTruthyDefaultsValue("1\n"))
        XCTAssertTrue(DesktopIcons.isTruthyDefaultsValue("YES"))
        XCTAssertFalse(DesktopIcons.isTruthyDefaultsValue("0"))
    }

    // MARK: - Bearbeiten / Speichern

    func testEditKeepsStoredSystemStateAndCapturesOnlyNewKeys() {
        var captured: [String] = []
        let merged = Profiles.mergedSystemState(
            existing: ["volume": 20, "appearance": true],
            keys: ["volume", "dock"],
            capture: { keys in captured = keys; return ["dock": ["autohide": true]] })
        XCTAssertEqual(captured, ["dock"])
        XCTAssertEqual(merged["volume"] as? Int, 20)
        XCTAssertNil(merged["appearance"])
        XCTAssertNotNil(merged["dock"])
    }

    func testBrowserTabsArePreservedPerBrowser() {
        let result = BrowserTabs.tabsForSave(
            captured: ["com.google.Chrome": ["https://new.example"]],
            existing: [
                "com.apple.Safari": ["https://old.example"],
                "com.microsoft.edgemac": ["https://edge.example"],
            ],
            captureRequested: true,
            runningBundleIDs: ["com.apple.Safari", "com.google.Chrome"])
        XCTAssertEqual(result.tabs, [
            "com.google.Chrome": ["https://new.example"],
            "com.apple.Safari": ["https://old.example"],
        ])
        XCTAssertEqual(result.preserved, ["Safari"])
    }

    func testBrowserCaptureSkipsIncognitoWindows() {
        let script = BrowserTabs.captureScript(browserName: "Google Chrome")
        XCTAssertTrue(script.contains(#"(mode of w as string) is "incognito""#))
        XCTAssertTrue(script.contains("if not isPrivate then"))
        XCTAssertTrue(script.contains(#"tell application "Google Chrome""#))
    }

    func testWindowGeometryIsMappedByProcessID() {
        let parsed = Apps.parseWindowLines("101||10||20||800||600\n101||0||0||1.5||2\ninvalid\n")
        XCTAssertEqual(parsed[101]?.count, 2)
        XCTAssertEqual(parsed[101]?.first, ["x": 10, "y": 20, "w": 800, "h": 600])
    }

    func testWindowRestorePrefersBundleIdentifier() {
        let app = Apps.AppInfo(name: "Na\"me", bundleID: "com.example.app", path: "",
                               windows: [["x": 1, "y": 2, "w": 3, "h": 4]])
        let script = Apps.windowRestoreScript(app)!
        XCTAssertTrue(script.contains(#"first process whose bundle identifier is "com.example.app""#))
        XCTAssertFalse(script.contains("Na"))
        XCTAssertNil(Apps.windowRestoreScript(Apps.AppInfo(name: "x", bundleID: nil, path: "")))
    }

    // MARK: - Automatik

    func testTimeRangesIncludingMidnight() {
        XCTAssertTrue(AppDelegate.timeInRange("08:00-17:00", nowMinutes: 8 * 60))
        XCTAssertFalse(AppDelegate.timeInRange("08:00-17:00", nowMinutes: 17 * 60))
        XCTAssertTrue(AppDelegate.timeInRange("22:00-06:00", nowMinutes: 23 * 60))
        XCTAssertTrue(AppDelegate.timeInRange("22:00-06:00", nowMinutes: 5 * 60))
        XCTAssertFalse(AppDelegate.timeInRange("22:00-06:00", nowMinutes: 12 * 60))
        XCTAssertFalse(AppDelegate.timeInRange("25:00-06:00", nowMinutes: 0))
        XCTAssertFalse(AppDelegate.timeInRange("garbage", nowMinutes: 0))
    }

    func testAutoSwitchTargets() {
        let rules: [[String: Any]] = [
            ["type": "time", "value": "09:00-12:00", "profile": "Work"],
            ["type": "wifi", "value": "Cafe", "profile": "Travel"],
        ]
        XCTAssertEqual(AppDelegate.timeRuleTarget(rules, nowMinutes: 10 * 60), "Work")
        XCTAssertNil(AppDelegate.timeRuleTarget(rules, nowMinutes: 13 * 60))
        let profiles = [(name: "Home", ssid: "HomeNet")]
        XCTAssertEqual(AppDelegate.wifiTarget(ssid: "HomeNet", profiles: profiles, rules: rules), "Home")
        XCTAssertEqual(AppDelegate.wifiTarget(ssid: "Cafe", profiles: profiles, rules: rules), "Travel")
        XCTAssertNil(AppDelegate.wifiTarget(ssid: nil, profiles: profiles, rules: rules))
    }

    func testDeletedProfileRulesAreRemoved() {
        let rules: [[String: Any]] = [["profile": "A"], ["profile": "B"]]
        XCTAssertEqual(Profiles.autoSwitchRules(rules, removingProfile: "A").compactMap { $0["profile"] as? String }, ["B"])
    }

    func testLoginRestoreOnlyAfterLoginLaunch() {
        XCTAssertTrue(AppDelegate.shouldRestoreOnLogin(
            arguments: ["app", LaunchAgentManager.loginArgument], systemUptime: 99_999))
        XCTAssertTrue(AppDelegate.shouldRestoreOnLogin(arguments: ["app"], systemUptime: 120))
        XCTAssertFalse(AppDelegate.shouldRestoreOnLogin(arguments: ["app"], systemUptime: 99_999))
    }

    func testLaunchAgentPlistContainsEscapedArguments() {
        let plist = LaunchAgentManager.plistContents(
            programArguments: ["/usr/bin/open", "-g", "/Apps/A&B.app", "--args", LaunchAgentManager.loginArgument])
        XCTAssertTrue(plist.contains("<string>/Apps/A&amp;B.app</string>"))
        XCTAssertTrue(plist.contains("<string>--launched-at-login</string>"))
    }

    // MARK: - WLAN

    func testRedactedSSIDIsIgnored() {
        XCTAssertNil(WiFi.validSSID("<redacted>"))
        XCTAssertNil(WiFi.parseIpconfigSummary("  BSSID : <redacted>\n  SSID : <redacted>\n"))
        XCTAssertEqual(WiFi.parseIpconfigSummary("  SSID : Home: Net\n"), "Home: Net")
        XCTAssertNil(WiFi.parseAirportNetwork("You are not associated with an AirPort network."))
        XCTAssertNil(WiFi.parseAirportNetwork("Error: en0 is not a Wi-Fi interface."))
        XCTAssertEqual(WiFi.parseAirportNetwork("Current Wi-Fi Network: HomeNet\n"), "HomeNet")
    }

    // MARK: - Fenster / Widget

    func testAppExclusionsKeepEntriesForAppsThatAreNotRunning() {
        let merged = AppSelectionWindow.mergedExclusions(
            previous: ["Zoom", "Mail"], shown: ["Mail", "Notes"], unchecked: ["Notes"])
        XCTAssertEqual(merged, ["Zoom", "Notes"])
    }

    func testWidgetPositionMustBeOnAScreen() {
        let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900)]
        let size = NSSize(width: 200, height: 300)
        XCTAssertTrue(ProfileWidget.isVisible(origin: NSPoint(x: 100, y: 100), size: size, screens: screens))
        XCTAssertFalse(ProfileWidget.isVisible(origin: NSPoint(x: 3000, y: 100), size: size, screens: screens))
        XCTAssertFalse(ProfileWidget.isVisible(origin: NSPoint(x: 1430, y: 100), size: size, screens: screens))
    }

    // MARK: - Update

    func testUpdateDigestIsParsedAndValidated() throws {
        let hex = String(repeating: "ab", count: 32)
        XCTAssertEqual(UpdateManager.sha256(fromDigest: "sha256:\(hex.uppercased())"), hex)
        XCTAssertNil(UpdateManager.sha256(fromDigest: "md5:\(hex)"))
        XCTAssertNil(UpdateManager.sha256(fromDigest: "sha256:xyz"))

        let data = Data("""
        {"tag_name": "v2.0.0", "assets": [{"name": "a.dmg",
          "browser_download_url": "https://example.com/a.dmg", "digest": "sha256:\(hex)"}]}
        """.utf8)
        XCTAssertEqual(UpdateManager.release(from: data)?.sha256, hex)
    }

    func testSHA256OfFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dpm-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try UpdateManager.sha256Hex(of: url),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
