import Foundation
import SystemConfiguration

/// Netzwerkbedingung eines Profils für das Auto-Umschalten.
/// Gespeichert als `network_mode` in den Profileinstellungen; ältere Profile
/// kennen nur `wifi_ssid`.
enum NetworkMode: String, CaseIterable {
    case none, wifi, ethernet, both

    /// Liest die wirksame Bedingung. Ohne WLAN-Namen kann der WLAN-Teil nie
    /// greifen: „WLAN“ entfällt dann ganz, „Beides“ wirkt nur noch per Kabel.
    static func from(settings: [String: Any]) -> NetworkMode {
        let ssid = (settings["wifi_ssid"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (settings["network_mode"] as? String).flatMap(NetworkMode.init(rawValue:))
        switch stored ?? (ssid.isEmpty ? .none : .wifi) {
        case .none: return .none
        case .ethernet: return .ethernet
        case .wifi: return ssid.isEmpty ? .none : .wifi
        case .both: return ssid.isEmpty ? .ethernet : .both
        }
    }

    var usesWiFi: Bool { self == .wifi || self == .both }
    var usesEthernet: Bool { self == .ethernet || self == .both }

    var title: String {
        switch self {
        case .none: return L("Keine Zuordnung", "No assignment")
        case .wifi: return L("WLAN", "Wi-Fi")
        case .ethernet: return L("Kabel (Ethernet)", "Cable (Ethernet)")
        case .both: return L("Beides (WLAN oder Kabel)", "Both (Wi-Fi or cable)")
        }
    }

    /// Kurzform für die Menü-Übersicht, z. B. „📶 Zuhause“ oder „🔌 Kabel“.
    func menuLabel(ssid: String) -> String {
        switch self {
        case .none: return ""
        case .wifi: return "📶 \(ssid)"
        case .ethernet: return "🔌 " + L("Kabel", "Cable")
        case .both: return "📶 \(ssid) / 🔌 " + L("Kabel", "Cable")
        }
    }
}

/// Netzwerk-Zuordnung eines Profils für das Auto-Umschalten.
struct NetworkAssignment: Equatable {
    let name: String
    let mode: NetworkMode
    let ssid: String
}

/// Kabelgebundene Netzwerkverbindungen (Ethernet, USB-/Thunderbolt-Adapter).
enum Ethernet {

    /// Nur echte Kabelanschlüsse zählen: Die Thunderbolt-Bridge ist vom Typ
    /// „Bridge“, iPhone/iPad per USB melden sich zwar als Ethernet, sind aber
    /// mobile Verbindungen.
    static func isWiredService(type: String, displayName: String) -> Bool {
        guard type == (kSCNetworkInterfaceTypeEthernet as String) else { return false }
        let lower = displayName.lowercased()
        return !lower.contains("iphone") && !lower.contains("ipad")
    }

    /// BSD-Namen (z. B. `en0`) aller aktivierten kabelgebundenen Netzwerkdienste.
    /// Thunderbolt-Ports und virtuelle Adapter ohne eigenen Dienst zählen nicht.
    static func serviceInterfaces() -> [String] {
        guard let prefs = SCPreferencesCreate(nil, "DesktopProfileManager" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else { return [] }
        var names: [String] = []
        for service in services where SCNetworkServiceGetEnabled(service) {
            guard let iface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(iface) as String?,
                  let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { continue }
            let display = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? ?? ""
            if isWiredService(type: type, displayName: display), !names.contains(bsd) {
                names.append(bsd)
            }
        }
        return names
    }

    /// Hat der Mac überhaupt einen Kabelanschluss (bzw. einen eingerichteten Adapter)?
    static var isAvailable: Bool { !serviceInterfaces().isEmpty }

    /// `true`, sobald an einem Kabelanschluss eine Verbindung (Link) besteht.
    static func isConnected() -> Bool {
        let interfaces = serviceInterfaces()
        guard !interfaces.isEmpty,
              let store = SCDynamicStoreCreate(nil, "DesktopProfileManager" as CFString, nil, nil) else { return false }
        return interfaces.contains { bsd in
            let key = "State:/Network/Interface/\(bsd)/Link" as CFString
            let link = SCDynamicStoreCopyValue(store, key) as? [String: Any]
            return link?["Active"] as? Bool ?? false
        }
    }
}
