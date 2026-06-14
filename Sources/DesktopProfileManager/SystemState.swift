import Foundation

/// Systemzustand: Erscheinungsbild, Lautstärke, Dock, Icon-Anzeige usw.
/// Werte werden als `Any` (Bool/Int/String/[String:Any]) gehalten – kompatibel
/// zum JSON-Format der Python-App.
enum SystemState {

    /// Reihenfolge + Labels der Optionen (Schlüssel identisch zur Python-App).
    static let optionOrder: [(key: String, de: String, en: String)] = [
        ("appearance", "Erscheinungsbild (hell/dunkel)", "Appearance (light/dark)"),
        ("volume", "Lautstärke", "Volume"),
        ("brightness", "Bildschirmhelligkeit", "Screen brightness"),
        ("dnd", "Nicht stören / Fokus", "Do Not Disturb / Focus"),
        ("dock", "Dock-Konfiguration", "Dock configuration"),
        ("desktop_view", "Icon-Anzeige (Größe/Anordnung)", "Icon view (size/arrangement)"),
    ]

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
        for (key, value) in state {
            setValue(key, value)
        }
    }

    private static func getValue(_ key: String) -> Any? {
        switch key {
        case "appearance": return getDarkMode()
        case "volume": return getVolume()
        case "brightness": return getBrightness()
        case "dnd": return nil // nicht zuverlässig lesbar
        case "dock": return getDockSettings()
        case "desktop_view": return getDesktopView()
        default: return nil
        }
    }

    private static func setValue(_ key: String, _ value: Any) {
        switch key {
        case "appearance": if let b = value as? Bool { setDarkMode(b) }
        case "volume": if let v = value as? Int { setVolume(v) }
        case "brightness": if let v = value as? Double { setBrightness(v) }
                           else if let v = value as? Int { setBrightness(Double(v)) }
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

    // MARK: - Nicht stören / Fokus (best effort)

    static func setDoNotDisturb(_ enabled: Bool) {
        let shortcut = enabled ? "Fokus ein" : "Fokus aus"
        if let sc = which("shortcuts") {
            if Shell.run(sc, ["run", shortcut], timeout: 10).code == 0 { return }
        }
        let val = enabled ? "true" : "false"
        Shell.run("/usr/bin/defaults", ["-currentHost", "write",
            "com.apple.notificationcenterui", "doNotDisturb", "-bool", val])
        Shell.run("/usr/bin/killall", ["NotificationCenter"])
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

    static func setDockSettings(_ settings: [String: Any]) {
        var changed = false
        func write(_ key: String, _ type: String, _ arg: String) {
            Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", key, "-\(type)", arg])
            changed = true
        }
        if let o = settings["orientation"] as? String { write("orientation", "string", o) }
        if let t = settings["tilesize"] as? Int { write("tilesize", "int", String(t)) }
        if let a = settings["autohide"] as? Bool { write("autohide", "bool", a ? "true" : "false") }
        if let m = settings["magnification"] as? Bool { write("magnification", "bool", m ? "true" : "false") }
        if changed { Shell.run("/usr/bin/killall", ["Dock"]) }
    }

    // MARK: - Desktop-Icon-Anzeige

    static func getDesktopView() -> [String: Any]? {
        let script = """
        tell application "Finder"
            set o to icon view options of desktop
            set ag to (arrangement of o) as string
            set isize to (icon size of o) as string
            return ag & "||" & isize
        end tell
        """
        guard let raw = Shell.runAppleScript(script) else { return nil }
        let parts = raw.components(separatedBy: "||")
        if parts.count != 2 { return nil }
        var result: [String: Any] = ["arrangement": parts[0].trimmingCharacters(in: .whitespaces)]
        if let s = Double(parts[1]) { result["icon_size"] = Int(s) }
        return result
    }

    static func setDesktopView(_ settings: [String: Any]) {
        var lines = ["tell application \"Finder\"", "  set o to icon view options of desktop"]
        if let arr = settings["arrangement"] as? String, !arr.isEmpty {
            lines.append("  try")
            lines.append("    set arrangement of o to \(arr)")
            lines.append("  end try")
        }
        if let size = settings["icon_size"] as? Int {
            lines.append("  set icon size of o to \(size)")
        }
        lines.append("end tell")
        _ = Shell.runAppleScript(lines.joined(separator: "\n"))
    }

    // MARK: - Helfer

    private static func which(_ tool: String) -> String? {
        let r = Shell.run("/usr/bin/which", [tool])
        return r.code == 0 && !r.output.isEmpty ? r.output : nil
    }
}
