import Foundation

/// Systemzustand: Erscheinungsbild, Lautstärke, Dock, Icon-Anzeige usw.
/// Werte werden als `Any` (Bool/Int/String/[String:Any]) gehalten – kompatibel
/// zum JSON-Format der Python-App.
enum SystemState {

    /// Reihenfolge + Labels der Optionen (Schlüssel identisch zur Python-App).
    /// „Nicht stören" ist nicht mehr auswählbar: macOS bietet dafür keine
    /// zuverlässige Schnittstelle mehr. Ältere Profile mit `dnd` werden beim
    /// Wiederherstellen weiterhin über Kurzbefehle bedient.
    static let optionOrder: [(key: String, de: String, en: String)] = [
        ("appearance", "Erscheinungsbild (hell/dunkel)", "Appearance (light/dark)"),
        ("volume", "Lautstärke", "Volume"),
        ("brightness", "Bildschirmhelligkeit", "Screen brightness"),
        ("dock", "Dock-Konfiguration", "Dock configuration"),
        ("desktop_view", "Icon-Anzeige (Größe/Anordnung)", "Icon view (size/arrangement)"),
    ]

    /// Gültige Finder-Anordnungen (Finder-Skriptterminologie). Nur diese Werte
    /// werden in AppleScript übernommen – Profile sind importierbare Dateien.
    /// Die Vier-Zeichen-Codes vermeiden Mehrdeutigkeiten wie `is not arranged`.
    static let desktopArrangementCodes: [(name: String, code: String)] = [
        ("not arranged", "narr"), ("snap to grid", "grda"), ("arranged by name", "nama"),
        ("arranged by modification date", "mdta"), ("arranged by creation date", "cdta"),
        ("arranged by size", "siza"), ("arranged by kind", "kina"), ("arranged by label", "laba"),
    ]
    static var desktopArrangements: [String] { desktopArrangementCodes.map(\.name) }
    static let dockOrientations: Set<String> = ["left", "bottom", "right"]
    static let iconSizeRange = 16...512
    static let dockTileSizeRange = 16...128

    // MARK: - Erfassen / Wiederherstellen

    static func capture(keys: [String]) -> [String: Any] {
        var state: [String: Any] = [:]
        for key in keys {
            if let value = getValue(key) {
                state[key] = value
            }
        }
        return state
    }

    static func restore(_ state: [String: Any]) {
        for (key, value) in sanitize(state) {
            setValue(key, value)
        }
    }

    /// Prüft einen (ggf. importierten) Systemzustand auf Typ und Wertebereich.
    /// Unbekannte Schlüssel und ungültige Werte werden verworfen.
    static func sanitize(_ state: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in state {
            switch key {
            case "appearance", "dnd":
                if let b = JSONNumber.bool(value) { result[key] = b }
            case "volume":
                if let v = JSONNumber.int(value) { result[key] = max(0, min(100, v)) }
            case "brightness":
                if let v = JSONNumber.double(value) { result[key] = max(0.0, min(1.0, v)) }
            case "dock":
                if let d = value as? [String: Any] {
                    let dock = sanitizeDock(d)
                    if !dock.isEmpty { result[key] = dock }
                }
            case "desktop_view":
                if let d = value as? [String: Any] {
                    let view = sanitizeDesktopView(d)
                    if !view.isEmpty { result[key] = view }
                }
            default:
                break
            }
        }
        return result
    }

    static func sanitizeDock(_ settings: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        if let o = settings["orientation"] as? String, dockOrientations.contains(o) {
            result["orientation"] = o
        }
        if let t = JSONNumber.int(settings["tilesize"]) {
            result["tilesize"] = clamp(t, dockTileSizeRange)
        }
        if let a = JSONNumber.bool(settings["autohide"]) { result["autohide"] = a }
        if let m = JSONNumber.bool(settings["magnification"]) { result["magnification"] = m }
        return result
    }

    static func sanitizeDesktopView(_ settings: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        if let a = settings["arrangement"] as? String, desktopArrangements.contains(a) {
            result["arrangement"] = a
        }
        if let s = JSONNumber.int(settings["icon_size"]) {
            result["icon_size"] = clamp(s, iconSizeRange)
        }
        return result
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(range.upperBound, value))
    }

    private static func getValue(_ key: String) -> Any? {
        switch key {
        case "appearance": return getDarkMode()
        case "volume": return getVolume()
        case "brightness": return getBrightness()
        case "dock": return getDockSettings()
        case "desktop_view": return getDesktopView()
        default: return nil
        }
    }

    /// Erwartet bereits über `sanitize` geprüfte Werte.
    private static func setValue(_ key: String, _ value: Any) {
        switch key {
        case "appearance": if let b = value as? Bool { setDarkMode(b) }
        case "volume": if let v = value as? Int { setVolume(v) }
        case "brightness": if let v = value as? Double { setBrightness(v) }
        case "dnd": if let b = value as? Bool { setDoNotDisturb(b) }
        case "dock": if let d = value as? [String: Any] { setDockSettings(d) }
        case "desktop_view": if let d = value as? [String: Any] { setDesktopView(d) }
        default: break
        }
    }

    // MARK: - Erscheinungsbild

    static func getDarkMode() -> Bool? {
        guard let raw = Shell.runAppleScript(
            "tell application \"System Events\" to tell appearance preferences to return dark mode"
        )?.lowercased() else { return nil }
        if ["true", "wahr", "1"].contains(raw) { return true }
        if ["false", "falsch", "0"].contains(raw) { return false }
        return nil
    }

    static func setDarkMode(_ dark: Bool) {
        let val = dark ? "true" : "false"
        _ = Shell.runAppleScript(
            "tell application \"System Events\" to tell appearance preferences to set dark mode to \(val)")
    }

    // MARK: - Lautstärke

    static func getVolume() -> Int? {
        guard let raw = Shell.runAppleScript("return output volume of (get volume settings)") else { return nil }
        return Int(raw)
    }

    static func setVolume(_ vol: Int) {
        let v = max(0, min(100, vol))
        _ = Shell.runAppleScript("set volume output volume \(v)")
    }

    // MARK: - Helligkeit (benötigt `brightness`-CLI)

    static func getBrightness() -> Double? {
        guard let exe = which("brightness") else { return nil }
        let out = Shell.run(exe, ["-l"]).output
        for line in out.split(separator: "\n") where line.lowercased().contains("brightness") {
            if let last = line.split(separator: " ").last, let v = Double(last) { return v }
        }
        return nil
    }

    static func setBrightness(_ value: Double) {
        guard let exe = which("brightness") else { return }
        let v = max(0.0, min(1.0, value))
        Shell.run(exe, [String(v)])
    }

    // MARK: - Nicht stören / Fokus (nur ältere Profile, best effort)

    /// Kurzbefehle, die der Nutzer selbst anlegen kann. Seit macOS 12 gibt es
    /// keine dokumentierte Schnittstelle mehr; der frühere `defaults`-Weg samt
    /// Neustart des NotificationCenter wirkt nicht mehr und entfällt daher.
    static func doNotDisturbShortcutNames(enabled: Bool) -> [String] {
        enabled ? ["Fokus ein", "Focus On"] : ["Fokus aus", "Focus Off"]
    }

    static func setDoNotDisturb(_ enabled: Bool) {
        guard let sc = which("shortcuts") else { return }
        for name in doNotDisturbShortcutNames(enabled: enabled) {
            if Shell.run(sc, ["run", name], timeout: 10).code == 0 { return }
        }
    }

    // MARK: - Dock

    static func getDockSettings() -> [String: Any] {
        func read(_ key: String) -> String? {
            let r = Shell.run("/usr/bin/defaults", ["read", "com.apple.dock", key])
            return r.code == 0 ? r.output : nil
        }
        var result: [String: Any] = [:]
        if let o = read("orientation") { result["orientation"] = o }
        if let t = read("tilesize"), let i = Double(t) { result["tilesize"] = Int(i) }
        if let a = read("autohide") { result["autohide"] = ["1", "true", "YES"].contains(a) }
        if let m = read("magnification") { result["magnification"] = ["1", "true", "YES"].contains(m) }
        return result
    }

    /// Liefert nur die Dock-Werte, die vom aktuellen Zustand abweichen. Ohne
    /// diese Prüfung würde jeder Timer-Lauf das Dock per `killall` neu starten.
    static func dockChanges(desired: [String: Any], current: [String: Any]) -> [String: Any] {
        let desired = sanitizeDock(desired)
        let current = sanitizeDock(current)
        return desired.filter { key, value in
            switch (value, current[key]) {
            case let (a as String, b as String): return a != b
            case let (a as Int, b as Int): return a != b
            case let (a as Bool, b as Bool): return a != b
            default: return true
            }
        }
    }

    static func setDockSettings(_ settings: [String: Any]) {
        let changes = dockChanges(desired: settings, current: getDockSettings())
        guard !changes.isEmpty else { return }
        func write(_ key: String, _ type: String, _ arg: String) {
            Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", key, "-\(type)", arg])
        }
        if let o = changes["orientation"] as? String { write("orientation", "string", o) }
        if let t = changes["tilesize"] as? Int { write("tilesize", "int", String(t)) }
        if let a = changes["autohide"] as? Bool { write("autohide", "bool", a ? "true" : "false") }
        if let m = changes["magnification"] as? Bool { write("magnification", "bool", m ? "true" : "false") }
        Shell.run("/usr/bin/killall", ["Dock"])
    }

    // MARK: - Desktop-Icon-Anzeige

    /// `icon view options of desktop` ist nicht lesbar; nur das Fenster des
    /// Schreibtischs liefert die Optionen. Die Anordnung wird über einen
    /// Vergleich ermittelt, weil sich der Aufzählungswert nicht in Text
    /// umwandeln lässt.
    static func getDesktopView() -> [String: Any]? {
        var lines = [
            "tell application \"Finder\"",
            "  set o to icon view options of window of desktop",
            "  set ag to arrangement of o",
            "  set s to \"\"",
        ]
        for (index, entry) in desktopArrangementCodes.enumerated() {
            lines.append("  \(index == 0 ? "if" : "else if") ag is «constant ****\(entry.code)» then")
            lines.append("    set s to \"\(entry.name)\"")
        }
        lines.append("  end if")
        lines.append("  return s & \"||\" & ((icon size of o) as integer as string)")
        lines.append("end tell")
        guard let raw = Shell.runAppleScript(lines.joined(separator: "\n")) else { return nil }
        let parts = raw.components(separatedBy: "||")
        if parts.count != 2 { return nil }
        var result: [String: Any] = [:]
        let arrangement = parts[0].trimmingCharacters(in: .whitespaces)
        if desktopArrangements.contains(arrangement) { result["arrangement"] = arrangement }
        if let s = Double(parts[1].trimmingCharacters(in: .whitespaces)) { result["icon_size"] = Int(s) }
        return result.isEmpty ? nil : result
    }

    static func setDesktopView(_ settings: [String: Any]) {
        guard let script = desktopViewScript(settings) else { return }
        _ = Shell.runAppleScript(script)
    }

    /// Baut das Finder-Skript ausschließlich aus geprüften Werten (Whitelist bzw.
    /// begrenzte Ganzzahl) – Profilinhalte werden nie als AppleScript-Code
    /// übernommen.
    static func desktopViewScript(_ settings: [String: Any]) -> String? {
        let view = sanitizeDesktopView(settings)
        if view.isEmpty { return nil }
        var lines = ["tell application \"Finder\"", "  set o to icon view options of window of desktop"]
        if let arr = view["arrangement"] as? String,
           let code = desktopArrangementCodes.first(where: { $0.name == arr })?.code {
            lines.append("  try")
            lines.append("    set arrangement of o to «constant ****\(code)»")
            lines.append("  end try")
        }
        if let size = view["icon_size"] as? Int {
            lines.append("  set icon size of o to \(size)")
        }
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    // MARK: - Helfer

    /// Aus dem Finder gestartete Apps erben nur den minimalen System-PATH;
    /// Homebrew-Werkzeuge werden deshalb zusätzlich direkt gesucht.
    private static func which(_ tool: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let path = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        let r = Shell.run("/usr/bin/which", [tool])
        return r.code == 0 && !r.output.isEmpty ? r.output : nil
    }
}
