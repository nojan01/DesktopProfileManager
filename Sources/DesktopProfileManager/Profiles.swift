import Foundation

/// Profil-Verwaltung – speichert/lädt JSON-Dateien im Format der Python-App,
/// damit Profile zwischen beiden Varianten austauschbar bleiben.
enum Profiles {

    /// Kurzinfo eines Profils für Menü-/Widget-Anzeige.
    struct Summary {
        let name: String
        let count: Int
        let hiddenCount: Int
        let appCount: Int
        let hasWallpaper: Bool
        let savedAt: String
        let emoji: String
        let wifiSSID: String
        let url: URL
    }

    /// Valider Profilname. Namen werden nicht stillschweigend verändert, damit
    /// unterschiedliche Eingaben nie in derselben Datei landen können.
    static func validatedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || "-_ ".contains($0) }) else {
            return nil
        }
        return trimmed
    }

    /// Bereinigt einen Namen aus einer importierten Datei zu einem gültigen
    /// lokalen Profilnamen. Die interaktive UI verwendet dagegen `validatedName`.
    static func importName(_ name: String) -> String? {
        let cleaned = name.filter { $0.isLetter || $0.isNumber || "-_ ".contains($0) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return validatedName(cleaned)
    }

    static func profilePath(_ name: String) -> URL? {
        guard let validName = validatedName(name) else { return nil }
        return Paths.profilesDir.appendingPathComponent("\(validName).json")
    }

    static func list() -> [Summary] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: Paths.profilesDir,
                                                        includingPropertiesForKeys: nil) else { return [] }
        var result: [Summary] = []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard name.hasSuffix(".json"), !name.hasPrefix("_") else { continue }
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let settings = obj["settings"] as? [String: Any] ?? [:]
            let hidden = obj["hidden"] as? [Any] ?? []
            let apps = obj["apps"] as? [Any] ?? []
            // Für ältere Dateien mit einem inzwischen ungültigen `profile`-
            // Feld den Dateinamen verwenden, damit das Profil weiter ladbar ist.
            let fileStem = String(name.dropLast(5))
            let storedName = obj["profile"] as? String ?? fileStem
            let displayName = validatedName(storedName) ?? fileStem
            result.append(Summary(
                name: displayName,
                count: obj["icon_count"] as? Int ?? 0,
                hiddenCount: hidden.count,
                appCount: apps.count,
                hasWallpaper: (obj["wallpaper"] != nil) && !(obj["wallpaper"] is NSNull),
                savedAt: obj["saved_at"] as? String ?? "",
                emoji: settings["emoji"] as? String ?? "",
                wifiSSID: settings["wifi_ssid"] as? String ?? "",
                url: url
            ))
        }
        return result
    }

    static func load(_ name: String) -> [String: Any]? {
        guard let url = profilePath(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func atomicWrite(_ obj: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: Paths.profilesDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
        try data.write(to: url, options: .atomic)
    }

    private static func nowISO() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    struct SaveOptions {
        var withPositions = true
        var withHidden = true
        var withWallpaper = true
        var withApps = true
        var withBrowserTabs = false
        var includedApps: [String]? = nil
        var systemStateKeys: [String] = []
        var emoji = ""
        var wifiSSID = ""
    }

    /// Speichert ein Profil mit den gewählten Inhalten. Gibt (count, path) zurück.
    @discardableResult
    static func save(_ name: String, appExclusions: [String], options: SaveOptions,
                     overwrite: Bool = false) -> (count: Int, url: URL?, error: String?, preservedBrowserTabs: Bool) {
        let positions = options.withPositions ? DesktopIcons.getPositions() : [:]
        let hidden = options.withHidden ? DesktopIcons.getHiddenItems() : []
        let wallpaper = options.withWallpaper ? Wallpaper.get() : []
        let capturedBrowserTabs = options.withBrowserTabs ? BrowserTabs.capture() : [:]
        let displayLayout = Displays.getLayout().map { ["x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h] }
        let systemState = SystemState.capture(keys: options.systemStateKeys)

        var apps: [Apps.AppInfo] = []
        if options.withApps {
            let exclusions: Set<String>
            if let included = options.includedApps {
                let includedSet = Set(included)
                exclusions = Set(Apps.getRunning().map { $0.name }.filter { !includedSet.contains($0) })
            } else {
                exclusions = Set(appExclusions)
            }
            apps = Apps.capture(exclusions: exclusions)
        }

        if positions.isEmpty && hidden.isEmpty && wallpaper.isEmpty && apps.isEmpty &&
            capturedBrowserTabs.isEmpty && systemState.isEmpty {
            return (0, nil, L("Keine Daten zum Speichern gefunden", "No data found to save"), false)
        }
        guard let url = profilePath(name) else {
            return (0, nil, L("Ungültiger Profilname. Erlaubt sind Buchstaben, Zahlen, Leerzeichen, - und _.",
                              "Invalid profile name. Only letters, numbers, spaces, - and _ are allowed."), false)
        }
        if !overwrite && FileManager.default.fileExists(atPath: url.path) {
            return (0, nil, L("Ein Profil '\(name)' existiert bereits.", "A profile '\(name)' already exists."), false)
        }
        let savedTabs = BrowserTabs.tabsForSave(
            captured: capturedBrowserTabs,
            existing: overwrite ? load(name)?["browser_tabs"] : nil,
            captureRequested: options.withBrowserTabs)

        var positionsObj: [String: [String: Int]] = [:]
        for (k, v) in positions { positionsObj[k] = ["x": v.x, "y": v.y] }

        let appsObj: [[String: Any]] = apps.map { a in
            var d: [String: Any] = ["name": a.name, "path": a.path, "windows": a.windows]
            d["bundle_id"] = a.bundleID ?? NSNull()
            return d
        }

        let data: [String: Any] = [
            "profile": name,
            "saved_at": nowISO(),
            "icon_count": positions.count + hidden.count,
            "positions": positionsObj,
            "hidden": hidden,
            "wallpaper": wallpaper,
            "apps": appsObj,
            "browser_tabs": savedTabs.tabs,
            "system_state": systemState,
            "display_layout": displayLayout,
            "settings": [
                "capture_positions": options.withPositions,
                "capture_hidden": options.withHidden,
                "capture_wallpaper": options.withWallpaper,
                "capture_apps": options.withApps,
                "capture_browser_tabs": options.withBrowserTabs,
                "restore_positions": options.withPositions,
                "restore_wallpaper": options.withWallpaper,
                "restore_apps": options.withApps,
                "restore_browser_tabs": options.withBrowserTabs,
                "included_apps": options.includedApps ?? NSNull(),
                "system_state_keys": options.systemStateKeys,
                "emoji": options.emoji,
                "wifi_ssid": options.wifiSSID,
            ]
        ]
        do {
            try atomicWrite(data, to: url)
            return (positions.count + hidden.count, url, nil, savedTabs.preserved)
        } catch {
            return (0, nil, error.localizedDescription, false)
        }
    }

    /// Übernimmt Änderungen an einem bestehenden Profil, OHNE den Desktop neu zu
    /// erfassen: gespeicherte Icon-Positionen, versteckte Icons und das
    /// Hintergrundbild bleiben erhalten. Aktualisiert werden Name, Optionen,
    /// App-Auswahl, Systemzustand, Emoji und WLAN. Spiegelt das Python-Verhalten
    /// von `_apply_profile_edit`.
    static func applyEdit(oldName: String, newName: String, options: SaveOptions) -> String? {
        guard let oldURL = profilePath(oldName),
              var data = load(oldName) else {
            return L("Profil '\(oldName)' nicht gefunden.", "Profile '\(oldName)' not found.")
        }
        guard let newURL = profilePath(newName) else {
            return L("Ungültiger Profilname.", "Invalid profile name.")
        }
        let renamed = newURL != oldURL
        if renamed && FileManager.default.fileExists(atPath: newURL.path) {
            return L("Ein Profil '\(newName)' existiert bereits.", "A profile '\(newName)' already exists.")
        }

        // App-Auswahl: bestehende Einträge behalten, neu hinzugefügte laufende
        // Apps frisch erfassen.
        let desired = options.includedApps ?? []
        var seen = Set<String>()
        let uniqueDesired = desired.filter { seen.insert($0).inserted }
        let existingApps = (data["apps"] as? [[String: Any]]) ?? []
        var existingByName: [String: [String: Any]] = [:]
        for a in existingApps { if let n = a["name"] as? String { existingByName[n] = a } }
        var runningByName: [String: [String: Any]] = [:]
        for a in Apps.capture(exclusions: []) {
            var d: [String: Any] = ["name": a.name, "path": a.path, "windows": a.windows]
            d["bundle_id"] = a.bundleID ?? NSNull()
            runningByName[a.name] = d
        }
        var newApps: [[String: Any]] = []
        for n in uniqueDesired {
            if let a = existingByName[n] { newApps.append(a) }
            else if let a = runningByName[n] { newApps.append(a) }
        }
        data["apps"] = newApps

        // Systemzustand neu erfassen, falls Optionen gewählt
        data["system_state"] = SystemState.capture(keys: options.systemStateKeys)
        let capturedBrowserTabs = options.withBrowserTabs ? BrowserTabs.capture() : [:]
        let savedTabs = BrowserTabs.tabsForSave(captured: capturedBrowserTabs,
                                                existing: data["browser_tabs"],
                                                captureRequested: options.withBrowserTabs)
        data["browser_tabs"] = savedTabs.tabs

        data["settings"] = [
            "capture_positions": options.withPositions,
            "capture_hidden": options.withHidden,
            "capture_wallpaper": options.withWallpaper,
            "capture_apps": options.withApps,
            "capture_browser_tabs": options.withBrowserTabs,
            "restore_positions": options.withPositions,
            "restore_wallpaper": options.withWallpaper,
            "restore_apps": options.withApps,
            "restore_browser_tabs": options.withBrowserTabs,
            "included_apps": uniqueDesired,
            "system_state_keys": options.systemStateKeys,
            "emoji": options.emoji,
            "wifi_ssid": options.wifiSSID,
        ]
        data["profile"] = newName
        data["saved_at"] = nowISO()

        do {
            try atomicWrite(data, to: newURL)
            if renamed {
                try FileManager.default.removeItem(at: oldURL)
            }
        } catch {
            return error.localizedDescription
        }
        return nil
    }


    struct RestoreResult { let success: Int; let failed: Int; let error: String?; let warning: String? }

    static func restore(_ name: String, includeWallpaper: Bool = true, includeApps: Bool = false,
                        hideOthers: Bool = false, quitOthers: Bool = false,
                        launchDelay: Double = 1.5, iconsOnly: Bool = false) -> RestoreResult {
        guard let data = load(name) else {
            return RestoreResult(success: 0, failed: 0,
                                 error: L("Profil '\(name)' nicht gefunden", "Profile '\(name)' not found"),
                                 warning: nil)
        }
        let hiddenList = Set(data["hidden"] as? [String] ?? [])
        let settings = data["settings"] as? [String: Any] ?? [:]
        let restorePositions = settings["restore_positions"] as? Bool ?? true
        // Im „Nur-Desktop-Symbole“-Modus werden Hintergrund, Apps und Systemzustand übersprungen.
        var incWallpaper = iconsOnly ? false : includeWallpaper
        var incApps = iconsOnly ? false : includeApps
        var incBrowserTabs = iconsOnly ? false : includeApps
        if !iconsOnly {
            if let w = settings["restore_wallpaper"] as? Bool { incWallpaper = w }
            if let a = settings["restore_apps"] as? Bool { incApps = a }
            if let b = settings["restore_browser_tabs"] as? Bool { incBrowserTabs = b && includeApps }
        }

        // Sichtbarkeit wiederherstellen
        let visibility = DesktopIcons.getAllItems().map {
            (name: $0.name, hidden: hiddenList.contains($0.name))
        }
        DesktopIcons.applyVisibility(visibility)

        var success = 0, failed = 0
        if restorePositions, let posObj = data["positions"] as? [String: [String: Int]] {
            var positions: [String: (x: Int, y: Int)] = [:]
            for (k, v) in posObj { positions[k] = (v["x"] ?? 0, v["y"] ?? 0) }
            let r = DesktopIcons.setPositions(positions)
            success = r.success; failed = r.failed
        }

        if incWallpaper {
            if let arr = data["wallpaper"] as? [String], !arr.isEmpty { Wallpaper.set(arr) }
            else if let s = data["wallpaper"] as? String, !s.isEmpty { Wallpaper.set([s]) }
        }

        let profileApps = parseApps(data["apps"])
        if incApps && !profileApps.isEmpty {
            Apps.launch(profileApps, staggerDelay: launchDelay)
        }
        var warnings: [String] = []
        if incBrowserTabs {
            let browserResult = BrowserTabs.restore(BrowserTabs.parse(data["browser_tabs"]))
            if !browserResult.failedBrowsers.isEmpty {
                let browsers = browserResult.failedBrowsers.joined(separator: ", ")
                warnings.append(L("Browser-Tabs konnten nicht geöffnet werden (\(browsers)). Prüfe die Automatisierungsfreigabe.",
                                  "Browser tabs could not be opened (\(browsers)). Check the Automation permission."))
            }
        }
        if !iconsOnly {
            if quitOthers { _ = Apps.quitOthers(keep: profileApps) }
            else if hideOthers { _ = Apps.hideOthers(keep: profileApps) }

            if let state = data["system_state"] as? [String: Any] { SystemState.restore(state) }
        }

        if restorePositions, let saved = data["display_layout"] as? [[String: Int]], !saved.isEmpty {
            if !Displays.layoutsMatch(saved, Displays.getLayout()) {
                warnings.append(L("Bildschirm-Anordnung weicht ab – Symbolpositionen passen evtl. nicht.",
                                  "Display arrangement differs – icon positions may not match."))
            }
        }
        let warning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        return RestoreResult(success: success, failed: failed, error: nil, warning: warning)
    }

    static func parseApps(_ raw: Any?) -> [Apps.AppInfo] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.map { d in
            Apps.AppInfo(
                name: d["name"] as? String ?? "",
                bundleID: d["bundle_id"] as? String,
                path: d["path"] as? String ?? "",
                windows: (d["windows"] as? [[String: Int]]) ?? []
            )
        }
    }

    @discardableResult
    static func delete(_ name: String) -> Bool {
        guard let url = profilePath(name) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }
}
