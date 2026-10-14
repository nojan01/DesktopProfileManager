import CoreLocation
import CoreWLAN
import Foundation

/// Liest die aktuell verbundene WLAN-SSID. Seit macOS 14 liefert das System die
/// SSID nur Apps mit Ortungsdienst-Berechtigung; ohne sie geben auch
/// `networksetup`/`ipconfig` nur „<redacted>“ zurück.
enum WiFi {
    private static let permission = LocationPermission()

    /// Fragt die Ortungsdienst-Berechtigung einmalig an (nur im App-Bundle mit
    /// `NSLocationUsageDescription` möglich). Muss auf dem Main Thread laufen.
    static func requestPermissionIfNeeded() {
        permission.requestIfNeeded()
    }

    /// `nil`, wenn keine (lesbare) WLAN-Verbindung besteht.
    static func currentSSID() -> String? {
        if let ssid = CWWiFiClient.shared().interface()?.ssid(), let valid = validSSID(ssid) {
            return valid
        }

        var ports: [String] = CWWiFiClient.shared().interfaces()?.compactMap { $0.interfaceName } ?? []
        if ports.isEmpty {
            let (portsOut, _) = Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 5)
            ports = parseWiFiDevices(portsOut)
        }
        if ports.isEmpty { ports = ["en0", "en1"] }

        for dev in ports {
            let (out, _) = Shell.run("/usr/sbin/networksetup", ["-getairportnetwork", dev], timeout: 5)
            if let ssid = parseAirportNetwork(out) { return ssid }
            let (summary, _) = Shell.run("/usr/sbin/ipconfig", ["getsummary", dev], timeout: 5)
            if let ssid = parseIpconfigSummary(summary) { return ssid }
        }
        return nil
    }

    /// Verwirft leere und vom System geschwärzte Werte.
    static func validSSID(_ raw: String) -> String? {
        let ssid = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty, ssid.lowercased() != "<redacted>" else { return nil }
        return ssid
    }

    static func parseWiFiDevices(_ output: String) -> [String] {
        var ports: [String] = []
        for block in output.components(separatedBy: "Hardware Port:")
        where block.contains("Wi-Fi") || block.contains("AirPort") {
            for line in block.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("Device:") {
                    ports.append(String(trimmed.dropFirst("Device:".count)).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return ports
    }

    /// Erwartet „Current Wi-Fi Network: Name“.
    static func parseAirportNetwork(_ output: String) -> String? {
        let lower = output.lowercased()
        guard output.contains(":"), !lower.contains("not associated"),
              !lower.contains("not a wi-fi interface"), !lower.contains("error") else { return nil }
        return validSSID(output.components(separatedBy: ":").dropFirst().joined(separator: ":"))
    }

    static func parseIpconfigSummary(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("SSID :") || trimmed.hasPrefix("SSID:") else { continue }
            if let ssid = validSSID(trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":")) {
                return ssid
            }
        }
        return nil
    }
}

private final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?

    func requestIfNeeded() {
        // Ohne Bundle-ID bzw. Usage-Beschreibung (z. B. `swift run`) würde die
        // Anfrage still verworfen.
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.object(forInfoDictionaryKey: "NSLocationUsageDescription") != nil else { return }
        let manager = self.manager ?? CLLocationManager()
        self.manager = manager
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}
