import XCTest
@testable import DesktopProfileManager

final class NetworkAssignmentTests: XCTestCase {

    func testNetworkModeFromSettings() {
        // Ältere Profile kennen nur `wifi_ssid`.
        XCTAssertEqual(NetworkMode.from(settings: ["wifi_ssid": "Home"]), .wifi)
        XCTAssertEqual(NetworkMode.from(settings: ["wifi_ssid": ""]), .none)
        XCTAssertEqual(NetworkMode.from(settings: [:]), .none)
        XCTAssertEqual(NetworkMode.from(settings: ["network_mode": "ethernet", "wifi_ssid": ""]), .ethernet)
        XCTAssertEqual(NetworkMode.from(settings: ["network_mode": "both", "wifi_ssid": "Home"]), .both)
        XCTAssertEqual(NetworkMode.from(settings: ["network_mode": "none", "wifi_ssid": "Home"]), .none)
        // Ohne WLAN-Namen kann der WLAN-Teil nicht greifen.
        XCTAssertEqual(NetworkMode.from(settings: ["network_mode": "wifi", "wifi_ssid": " "]), .none)
        XCTAssertEqual(NetworkMode.from(settings: ["network_mode": "both", "wifi_ssid": ""]), .ethernet)
        // Unbekannte Werte fallen auf das alte Verhalten zurück.
        XCTAssertEqual(NetworkMode.from(settings: ["network_mode": "lan", "wifi_ssid": "Home"]), .wifi)
    }

    func testCableWinsWhenBothConnected() {
        let profiles = [
            NetworkAssignment(name: "Sofa", mode: .wifi, ssid: "HomeNet"),
            NetworkAssignment(name: "Desk", mode: .ethernet, ssid: ""),
        ]
        XCTAssertEqual(AppDelegate.networkTarget(ssid: "HomeNet", ethernetConnected: true, profiles: profiles, rules: []), "Desk")
        XCTAssertEqual(AppDelegate.networkTarget(ssid: "HomeNet", ethernetConnected: false, profiles: profiles, rules: []), "Sofa")
        XCTAssertEqual(AppDelegate.networkTarget(ssid: nil, ethernetConnected: true, profiles: profiles, rules: []), "Desk")
        XCTAssertNil(AppDelegate.networkTarget(ssid: "Other", ethernetConnected: false, profiles: profiles, rules: []))
    }

    func testBothMatchesCableOrWiFi() {
        let profiles = [NetworkAssignment(name: "Home", mode: .both, ssid: "HomeNet")]
        XCTAssertEqual(AppDelegate.networkTarget(ssid: nil, ethernetConnected: true, profiles: profiles, rules: []), "Home")
        XCTAssertEqual(AppDelegate.networkTarget(ssid: "HomeNet", ethernetConnected: false, profiles: profiles, rules: []), "Home")
        XCTAssertNil(AppDelegate.networkTarget(ssid: "Cafe", ethernetConnected: false, profiles: profiles, rules: []))
    }

    func testExactModesBeatBoth() {
        let profiles = [
            NetworkAssignment(name: "A", mode: .both, ssid: "HomeNet"),
            NetworkAssignment(name: "B", mode: .ethernet, ssid: ""),
            NetworkAssignment(name: "C", mode: .wifi, ssid: "HomeNet"),
        ]
        XCTAssertEqual(AppDelegate.networkTarget(ssid: "HomeNet", ethernetConnected: true, profiles: profiles, rules: []), "B")
        XCTAssertEqual(AppDelegate.networkTarget(ssid: "HomeNet", ethernetConnected: false, profiles: profiles, rules: []), "C")
    }

    func testProfileAssignmentBeatsLegacyRule() {
        let rules: [[String: Any]] = [["type": "wifi", "value": "HomeNet", "profile": "Legacy"]]
        let profiles = [NetworkAssignment(name: "Home", mode: .both, ssid: "HomeNet")]
        XCTAssertEqual(AppDelegate.networkTarget(ssid: "HomeNet", ethernetConnected: false, profiles: profiles, rules: rules), "Home")
        XCTAssertEqual(AppDelegate.networkTarget(ssid: "HomeNet", ethernetConnected: false, profiles: [], rules: rules), "Legacy")
    }

    func testAvailableModesOnlyOfferExistingHardware() {
        XCTAssertEqual(ProfileSetupWindow.availableNetworkModes(hasWiFi: true, hasEthernet: true, saved: .none),
                       [.none, .wifi, .ethernet, .both])
        XCTAssertEqual(ProfileSetupWindow.availableNetworkModes(hasWiFi: true, hasEthernet: false, saved: .none),
                       [.none, .wifi])
        XCTAssertEqual(ProfileSetupWindow.availableNetworkModes(hasWiFi: false, hasEthernet: true, saved: .none),
                       [.none, .ethernet])
        // Gespeicherte Zuordnung bleibt beim Bearbeiten wählbar.
        XCTAssertEqual(ProfileSetupWindow.availableNetworkModes(hasWiFi: true, hasEthernet: false, saved: .both),
                       [.none, .wifi, .both])
    }

    func testWiFiChoicesOrder() {
        XCTAssertEqual(ProfileSetupWindow.wifiChoices(current: "B", known: ["A", "B", "C"], saved: "Old"),
                       ["B", "Old", "A", "C"])
        XCTAssertEqual(ProfileSetupWindow.wifiChoices(current: nil, known: ["A"], saved: ""), ["A"])
    }

    func testParsePreferredNetworks() {
        let output = "Preferred networks on en1:\n\tHome Net\n\tiPhone (2)\n\t<redacted>\n"
        XCTAssertEqual(WiFi.parsePreferredNetworks(output), ["Home Net", "iPhone (2)"])
        XCTAssertEqual(WiFi.parsePreferredNetworks("en0 is not a Wi-Fi interface.\n"), [])
    }

    func testWiredServiceFilter() {
        XCTAssertTrue(Ethernet.isWiredService(type: "Ethernet", displayName: "Ethernet"))
        XCTAssertTrue(Ethernet.isWiredService(type: "Ethernet", displayName: "USB 10/100/1000 LAN"))
        XCTAssertFalse(Ethernet.isWiredService(type: "Ethernet", displayName: "iPhone USB"))
        XCTAssertFalse(Ethernet.isWiredService(type: "IEEE80211", displayName: "Wi-Fi"))
        XCTAssertFalse(Ethernet.isWiredService(type: "Bridge", displayName: "Thunderbolt Bridge"))
    }

    func testImportDropsInvalidNetworkMode() {
        let valid = Profiles.sanitizedImport(["settings": ["network_mode": "both", "wifi_ssid": "X"]], name: "A")
        XCTAssertEqual((valid["settings"] as? [String: Any])?["network_mode"] as? String, "both")
        let invalid = Profiles.sanitizedImport(["settings": ["network_mode": 42]], name: "A")
        XCTAssertNil((invalid["settings"] as? [String: Any])?["network_mode"])
    }
}
