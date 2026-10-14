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
    /// „Kabel“ schaltet das WLAN aus, „WLAN“ und „Beides“ schalten es ein.
    var canSwitchWiFi: Bool { self != .none }

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

/// Schaltet das WLAN passend zur Netzwerk-Zuordnung eines Profils: „Kabel“
/// schaltet es aus, „WLAN“ und „Beides“ ein. Hat die App das WLAN
/// ausgeschaltet, schaltet jedes andere Profil es wieder ein. Das Kabel bleibt
/// immer unangetastet, weil macOS dafür bei jeder Änderung ein
/// Administratorpasswort verlangt.
enum WiFiSwitch {
    enum Action: Equatable { case none, turnOn, turnOff, keepNoCable }

    enum Outcome: Equatable {
        /// Für dieses Profil wird das WLAN nicht geschaltet.
        case unchanged
        /// Das WLAN ist eingeschaltet (war es schon oder wurde eingeschaltet).
        case wifiOn
        /// Die App hat das WLAN ausgeschaltet.
        case wifiOff
        /// Kabel-Profil ohne verbundenes Kabel: Das WLAN bleibt an.
        case keptNoCable
        case failed
    }

    /// Was beim Überwachen nach dem Ausschalten zu tun ist.
    enum FailoverAction: Equatable { case keepWatching, stopWatching, turnOnWiFi }

    static let settingsKey = "network_switch_wifi"

    /// Für das Schalten zählt „Beides“ auch ohne WLAN-Namen als WLAN-Nutzung,
    /// damit es das WLAN nie ausschaltet.
    static func switchMode(settings: [String: Any]) -> NetworkMode {
        if settings["network_mode"] as? String == NetworkMode.both.rawValue { return .both }
        return NetworkMode.from(settings: settings)
    }

    static func isEnabled(settings: [String: Any]) -> Bool {
        settings[settingsKey] as? Bool == true && switchMode(settings: settings).canSwitchWiFi
    }

    /// WLAN wird nur ausgeschaltet, wenn das Kabel tatsächlich verbunden ist –
    /// sonst stünde der Mac ohne Netzwerk da. Hat die App das WLAN zuvor
    /// ausgeschaltet (`wifiOffByApp`), schaltet jedes Profil, das es nicht
    /// selbst ausschaltet, es wieder ein.
    static func action(mode: NetworkMode, switchEnabled: Bool, ethernetConnected: Bool,
                       wifiOffByApp: Bool) -> Action {
        if switchEnabled {
            switch mode {
            case .wifi, .both: return .turnOn
            case .ethernet: return ethernetConnected ? .turnOff : .keepNoCable
            case .none: break
            }
        }
        return wifiOffByApp ? .turnOn : .none
    }

    /// Prüfungen in Folge ohne Kabel, bevor das WLAN zurückkommt. Nach dem
    /// Aufwachen braucht der Kabel-Link einige Sekunden.
    static let requiredMissedChecks = 4

    /// Hat der Nutzer das WLAN selbst wieder eingeschaltet, endet die
    /// Überwachung; fehlt das Kabel dauerhaft, kommt das WLAN zurück.
    static func failoverAction(wifiPoweredOn: Bool, ethernetConnected: Bool,
                               previousMissedChecks: Int) -> FailoverAction {
        if wifiPoweredOn { return .stopWatching }
        if ethernetConnected { return .keepWatching }
        return previousMissedChecks + 1 >= requiredMissedChecks ? .turnOnWiFi : .keepWatching
    }

    /// Kann Hilfsprozesse starten – nicht auf dem Main Thread aufrufen.
    static func apply(settings: [String: Any], wifiOffByApp: Bool) -> Outcome {
        guard WiFi.isAvailable else { return .unchanged }
        let mode = switchMode(settings: settings)
        let enabled = isEnabled(settings: settings)
        let wired = enabled && mode == .ethernet && Ethernet.isConnected()
        switch action(mode: mode, switchEnabled: enabled, ethernetConnected: wired, wifiOffByApp: wifiOffByApp) {
        case .none: return .unchanged
        case .keepNoCable:
            // Ein von der App ausgeschaltetes WLAN kommt ohne Kabel sofort zurück.
            if wifiOffByApp && !WiFi.isPoweredOn && !WiFi.setPower(true) { return .failed }
            return .keptNoCable
        case .turnOn:
            return WiFi.isPoweredOn || WiFi.setPower(true) ? .wifiOn : .failed
        case .turnOff:
            // War das WLAN schon aus, hat es nicht die App ausgeschaltet.
            guard WiFi.isPoweredOn else { return .unchanged }
            return WiFi.setPower(false) ? .wifiOff : .failed
        }
    }
}
