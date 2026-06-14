import Foundation

/// Liest die aktuell verbundene WLAN-SSID – kompatibel zur Python-Variante
/// (zuerst `networksetup`, dann `ipconfig getsummary` als Fallback).
enum WiFi {
    static func currentSSID() -> String? {
        var ports: [String] = []
        let (portsOut, _) = Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 5)
        for block in portsOut.components(separatedBy: "Hardware Port:") {
            if block.contains("Wi-Fi") || block.contains("AirPort") {
                for line in block.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("Device:") {
                        ports.append(String(trimmed.dropFirst("Device:".count)).trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        }
        if ports.isEmpty { ports = ["en0", "en1"] }

        for dev in ports {
            let (out, _) = Shell.run("/usr/sbin/networksetup", ["-getairportnetwork", dev], timeout: 5)
            if out.contains(":"), !out.lowercased().contains("not associated") {
                let ssid = out.components(separatedBy: ":").dropFirst().joined(separator: ":")
                    .trimmingCharacters(in: .whitespaces)
                if !ssid.isEmpty { return ssid }
            }
            let (summary, _) = Shell.run("/usr/sbin/ipconfig", ["getsummary", dev], timeout: 5)
            for line in summary.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("SSID :") || trimmed.hasPrefix("SSID:") {
                    let ssid = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":")
                        .trimmingCharacters(in: .whitespaces)
                    if !ssid.isEmpty { return ssid }
                }
            }
        }
        return nil
    }
}
