import Foundation

/// Auslöser einer Wiederherstellung. Nur eine ausdrückliche Nutzeraktion darf
/// fremde Apps beenden. Apps starten (inkl. Browser-Neustart) dürfen außerdem
/// der Login, bei dem die Arbeitsumgebung erst aufgebaut wird. Intervall-Timer,
/// Ruhemodus und Auto-Umschalten greifen nie in laufende Arbeit ein.
enum RestoreTrigger {
    case manual, autoSwitch, timer, wake, login

    var allowsAppLaunch: Bool { self == .manual || self == .login }
    var allowsQuitOthers: Bool { self == .manual }
    var allowsHideOthers: Bool { self == .manual || self == .autoSwitch }
    /// Nur echte Profilwechsel schalten das WLAN; Wiederherstellungen nach
    /// Login, Aufwachen oder Intervall überschreiben keine manuelle Wahl.
    var allowsWiFiSwitch: Bool { self == .manual || self == .autoSwitch }
}

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
        let networkMode: NetworkMode
        let url: URL
    }

    /// Valider Profilname. Namen werden nicht stillschweigend verändert, damit
    /// unterschiedliche Eingaben nie in derselben Datei landen können. Ein
    /// führender Unterstrich ist internen Dateien wie `_config.json` vorbehalten.
    static func validatedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("_"),
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || "-_ ".contains($0) }) else {
            return nil
        }
        return trimmed
    }

    /// Bereinigt einen Namen aus einer importierten Datei zu einem gültigen
    /// lokalen Profilnamen. Die interaktive UI verwendet dagegen `validatedName`.
    static func importName(_ name: String) -> String? {
        let filtered = name.filter { $0.isLetter || $0.isNumber || "-_ ".contains($0) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = String(filtered.drop(while: { $0 == "_" || $0.isWhitespace }))
        return validatedName(cleaned)
    }

    /// Liefert einen freien Namen für einen Import („Name“, „Name 2“, …).
    static func uniqueImportName(base: String, exists: (String) -> Bool) -> String {
        if !exists(base) { return base }
        var counter = 2
        while exists("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    static func profilePath(_ name: String) -> URL? {
        guard let validName = validatedName(name) else { return nil }
        return Paths.profilesDir.appendingPathComponent("\(validName).json")
    }

    static func exists(_ name: String) -> Bool {
        guard let url = profilePath(name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Der Dateiname ist die einzige Identität eines Profils. Nur Dateien, die
    /// über `profilePath` wieder exakt erreichbar sind, werden aufgelistet.
    static func profileName(forFileName fileName: String) -> String? {
        guard fileName.hasSuffix(".json") else { return nil }
        let stem = String(fileName.dropLast(5))
        guard let valid = validatedName(stem), valid == stem else { return nil }
        return stem
    }

    private static let listCacheLock = NSLock()
    private static var listCache: (signature: [String: String], summaries: [Summary])?

    /// Liest die Profilübersicht. Das Menü wird häufig neu aufgebaut; unveränderte
    /// Dateien (gleicher Name, Änderungsdatum und Größe) werden nicht erneut geparst.
    static func list() -> [Summary] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let entries = try? fm.contentsOfDirectory(at: Paths.profilesDir,
                                                        includingPropertiesForKeys: keys) else { return [] }
        let candidates = entries
            .compactMap { url -> (url: URL, name: String)? in
                profileName(forFileName: url.lastPathComponent).map { (url, $0) }
            }
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }

        var signature: [String: String] = [:]
        for candidate in candidates {
            let values = try? candidate.url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            signature[candidate.url.lastPathComponent] = "\(modified)|\(values?.fileSize ?? -1)"
        }
        listCacheLock.lock()
        if let cache = listCache, cache.signature == signature {
            listCacheLock.unlock()
            return cache.summaries
        }
        listCacheLock.unlock()

        var result: [Summary] = []
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate.url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let settings = obj["settings"] as? [String: Any] ?? [:]
            let hidden = obj["hidden"] as? [Any] ?? []
            let apps = obj["apps"] as? [Any] ?? []
            result.append(Summary(
                name: candidate.name,
                count: JSONNumber.int(obj["icon_count"]) ?? 0,
                hiddenCount: hidden.count,
                appCount: apps.count,
                hasWallpaper: (obj["wallpaper"] != nil) && !(obj["wallpaper"] is NSNull),
                savedAt: obj["saved_at"] as? String ?? "",
                emoji: settings["emoji"] as? String ?? "",
                wifiSSID: settings["wifi_ssid"] as? String ?? "",
                networkMode: NetworkMode.from(settings: settings),
                url: candidate.url
            ))
        }
        listCacheLock.lock()
        listCache = (signature, result)
        listCacheLock.unlock()
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

    /// Schreibt ein importiertes Profil. Fehler werden an den Aufrufer gemeldet.
    static func writeImported(_ obj: [String: Any], as name: String) throws {
        guard let url = profilePath(name) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try atomicWrite(sanitizedImport(obj, name: name), to: url)
    }

    /// Prüft eine importierte Profildatei strukturell. Inhalte, die später in
    /// Skripte oder Systemeinstellungen fließen, werden auf gültige Werte
    /// reduziert.
    static func sanitizedImport(_ obj: [String: Any], name: String) -> [String: Any] {
        var result = obj
        result["profile"] = name
        if let state = obj["system_state"] as? [String: Any] {
            result["system_state"] = SystemState.sanitize(state)
        } else {
            result.removeValue(forKey: "system_state")
        }
        if var settings = obj["settings"] as? [String: Any] {
            let knownKeys = Set(SystemState.optionOrder.map(\.key)).union(["dnd"])
            if let keys = settings["system_state_keys"] as? [String] {
                settings["system_state_keys"] = keys.filter { knownKeys.contains($0) }
            } else {
                settings.removeValue(forKey: "system_state_keys")
            }
            if let mode = settings["network_mode"], (mode as? String).flatMap(NetworkMode.init(rawValue:)) == nil {
                settings.removeValue(forKey: "network_mode")
            }
            if let flag = settings[WiFiSwitch.settingsKey], !(flag is Bool) {
                settings.removeValue(forKey: WiFiSwitch.settingsKey)
            }
            result["settings"] = settings
        } else {
            result.removeValue(forKey: "settings")
        }
        if let hidden = obj["hidden"] {
            result["hidden"] = (hidden as? [Any])?.compactMap { $0 as? String } ?? []
        }
        return result
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
        var networkMode: NetworkMode = .none
        var switchWiFi = false
    }

    private static func settingsObject(_ options: SaveOptions, includedApps: Any) -> [String: Any] {
        [
            "capture_positions": options.withPositions,
            "capture_hidden": options.withHidden,
            "capture_wallpaper": options.withWallpaper,
            "capture_apps": options.withApps,
            "capture_browser_tabs": options.withBrowserTabs,
            "restore_positions": options.withPositions,
            "restore_wallpaper": options.withWallpaper,
            "restore_apps": options.withApps,
            "restore_browser_tabs": options.withBrowserTabs,
            "included_apps": includedApps,
            "system_state_keys": options.systemStateKeys,
            "emoji": options.emoji,
            // Ohne WLAN-Bedingung bleibt `wifi_ssid` leer, damit ältere Versionen
            // ein Kabel-Profil nicht als WLAN-Profil deuten.
            "wifi_ssid": options.networkMode.usesWiFi ? options.wifiSSID : "",
            "network_mode": options.networkMode.rawValue,
            WiFiSwitch.settingsKey: options.switchWiFi && options.networkMode.canSwitchWiFi,
        ]
    }

    private static func appObject(_ app: Apps.AppInfo) -> [String: Any] {
        var d: [String: Any] = ["name": app.name, "path": app.path, "windows": app.windows]
        d["bundle_id"] = app.bundleID ?? NSNull()
        return d
    }

    /// Speichert ein Profil mit den gewählten Inhalten. `preservedBrowserTabs`
    /// nennt Browser, deren bisherige Tabs mangels Antwort beibehalten wurden.
    @discardableResult
    static func save(_ name: String, appExclusions: [String], options: SaveOptions,
                     overwrite: Bool = false)
        -> (count: Int, url: URL?, error: String?, preservedBrowserTabs: [String]) {
        // Name und Konflikte vor der langsamen Erfassung prüfen.
        guard let name = validatedName(name), let url = profilePath(name) else {
            return (0, nil, L("Ungültiger Profilname. Erlaubt sind Buchstaben, Zahlen, Leerzeichen, - und _ (nicht am Anfang).",
                              "Invalid profile name. Only letters, numbers, spaces, - and _ (not at the start) are allowed."), [])
        }
        if !overwrite && FileManager.default.fileExists(atPath: url.path) {
            return (0, nil, L("Ein Profil '\(name)' existiert bereits.", "A profile '\(name)' already exists."), [])
        }
        let existing = overwrite ? load(name) : nil

        let positions = options.withPositions ? DesktopIcons.getPositions() : [:]
        let hidden = options.withHidden ? DesktopIcons.getHiddenItems() : []
        let wallpaper = options.withWallpaper ? Wallpaper.get() : []
        let runningBrowsers = BrowserTabs.runningBundleIDs()
        let browserSelection = BrowserTabs.selectedBrowsers(
            appNames: options.includedApps,
            bundleIDs: Set(Apps.getRunning().filter { options.includedApps?.contains($0.name) ?? false }
                .compactMap(\.bundleID)))
        let capturedBrowserTabs = options.withBrowserTabs
            ? BrowserTabs.capture(selection: browserSelection) : [:]
        let capturedBrowserWindows = options.withBrowserTabs
            ? BrowserTabs.captureWindowPositions(selection: browserSelection) : [:]
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
            return (0, nil, L("Keine Daten zum Speichern gefunden", "No data found to save"), [])
        }
        let savedTabs = BrowserTabs.tabsForSave(
            captured: capturedBrowserTabs,
            existing: BrowserTabs.limited(BrowserTabs.parse(existing?["browser_tabs"]), to: browserSelection),
            captureRequested: options.withBrowserTabs,
            runningBundleIDs: runningBrowsers)
        let savedBrowserWindows = BrowserTabs.windowPositionsForSave(
            captured: capturedBrowserWindows,
            existing: BrowserTabs.limited(BrowserTabs.parseWindowPositions(existing?["browser_windows"]),
                                          to: browserSelection),
            captureRequested: options.withBrowserTabs,
            runningBundleIDs: runningBrowsers)

        var positionsObj: [String: [String: Int]] = [:]
        for (k, v) in positions { positionsObj[k] = ["x": v.x, "y": v.y] }

        let data: [String: Any] = [
            "profile": name,
            "saved_at": nowISO(),
            "icon_count": positions.count + hidden.count,
            "positions": positionsObj,
            "hidden": hidden,
            "wallpaper": wallpaper,
            "apps": apps.map(appObject),
            "browser_tabs": savedTabs.tabs,
            "browser_windows": savedBrowserWindows,
            "system_state": systemState,
            "display_layout": displayLayout,
            "settings": settingsObject(options, includedApps: options.includedApps ?? NSNull()),
        ]
        do {
            try atomicWrite(data, to: url)
            return (positions.count + hidden.count, url, nil, savedTabs.preserved)
        } catch {
            return (0, nil, error.localizedDescription, [])
        }
    }

    /// Übernimmt Systemzustände bereits gewählter Optionen unverändert und erfasst
    /// nur neu hinzugekommene Optionen. Abgewählte Optionen entfallen.
    static func mergedSystemState(existing: [String: Any], keys: [String],
                                  capture: ([String]) -> [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        var missing: [String] = []
        for key in keys {
            if let value = existing[key] { result[key] = value } else { missing.append(key) }
        }
        if !missing.isEmpty {
            for (key, value) in capture(missing) where result[key] == nil { result[key] = value }
        }
        return result
    }

    /// Übernimmt Änderungen an einem bestehenden Profil, OHNE den Desktop neu zu
    /// erfassen: gespeicherte Icon-Positionen, versteckte Icons, Hintergrundbild,
    /// bereits gespeicherte Systemzustände und Browser-Tabs bleiben erhalten.
    /// Aktualisiert werden Name, Optionen, App-Auswahl, Emoji und WLAN. Nur neu
    /// hinzugefügte Apps, Systemzustände bzw. Tabs neu ausgewählter Browser
    /// werden aktuell erfasst; abgewählte Browser verlieren ihre Tabs.
    static func applyEdit(oldName: String, newName: String, options: SaveOptions) -> String? {
        guard let oldURL = profilePath(oldName),
              var data = load(oldName) else {
            return L("Profil '\(oldName)' nicht gefunden.", "Profile '\(oldName)' not found.")
        }
        guard let newName = validatedName(newName), let newURL = profilePath(newName) else {
            return L("Ungültiger Profilname.", "Invalid profile name.")
        }
        let fm = FileManager.default
        let renamed = newURL != oldURL
        // Auf Dateisystemen ohne Groß-/Kleinschreibung ist „work“ → „Work“ dieselbe
        // Datei. Sie darf dann weder als Konflikt gelten noch gelöscht werden.
        let sameFile = renamed && isSameFile(oldURL, newURL)
        if renamed && !sameFile && fm.fileExists(atPath: newURL.path) {
            return L("Ein Profil '\(newName)' existiert bereits.", "A profile '\(newName)' already exists.")
        }

        // App-Auswahl: bestehende Einträge behalten, neu hinzugefügte laufende
        // Apps frisch erfassen. Ohne Auswahl bleiben die Apps unverändert.
        let existingApps = (data["apps"] as? [[String: Any]]) ?? []
        let includedApps: [String]
        if let desired = options.includedApps {
            var seen = Set<String>()
            includedApps = desired.filter { seen.insert($0).inserted }
            var existingByName: [String: [String: Any]] = [:]
            for a in existingApps { if let n = a["name"] as? String { existingByName[n] = a } }
            let missing = Set(includedApps.filter { existingByName[$0] == nil })
            var runningByName: [String: [String: Any]] = [:]
            if !missing.isEmpty {
                for a in Apps.capture(exclusions: []) where missing.contains(a.name) {
                    runningByName[a.name] = appObject(a)
                }
            }
            data["apps"] = includedApps.compactMap { existingByName[$0] ?? runningByName[$0] }
        } else {
            includedApps = existingApps.compactMap { $0["name"] as? String }
        }

        data["system_state"] = mergedSystemState(
            existing: data["system_state"] as? [String: Any] ?? [:],
            keys: options.systemStateKeys,
            capture: { SystemState.capture(keys: $0) })

        let browserSelection = options.includedApps == nil ? nil : BrowserTabs.selectedBrowsers(
            appNames: includedApps,
            bundleIDs: Set(parseApps(data["apps"]).compactMap(\.bundleID)))
        var tabs = BrowserTabs.limited(BrowserTabs.parse(data["browser_tabs"]), to: browserSelection)
        var windows = BrowserTabs.limited(BrowserTabs.parseWindowPositions(data["browser_windows"]),
                                          to: browserSelection)
        if options.withBrowserTabs {
            if let selection = browserSelection {
                let missing = selection.subtracting(tabs.keys)
                if !missing.isEmpty {
                    tabs.merge(BrowserTabs.capture(selection: missing)) { old, _ in old }
                    windows.merge(BrowserTabs.captureWindowPositions(selection: missing)) { old, _ in old }
                }
            } else if tabs.isEmpty {
                tabs = BrowserTabs.capture()
                windows = BrowserTabs.captureWindowPositions()
            }
        }
        data["browser_tabs"] = tabs
        data["browser_windows"] = windows

        data["settings"] = settingsObject(options, includedApps: includedApps)
        data["profile"] = newName
        data["saved_at"] = nowISO()

        do {
            if !renamed {
                try atomicWrite(data, to: oldURL)
            } else if sameFile {
                try atomicWrite(data, to: oldURL)
                let temp = Paths.profilesDir.appendingPathComponent(".rename-\(UUID().uuidString).json")
                try fm.moveItem(at: oldURL, to: temp)
                try fm.moveItem(at: temp, to: newURL)
            } else {
                try atomicWrite(data, to: newURL)
                try fm.removeItem(at: oldURL)
            }
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    private static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let idA = (try? a.resourceValues(forKeys: key))?.fileResourceIdentifier,
              let idB = (try? b.resourceValues(forKeys: key))?.fileResourceIdentifier else { return false }
        return idA.isEqual(idB)
    }

    struct RestoreResult { let success: Int; let failed: Int; let error: String?; let warning: String? }

    /// Was eine Wiederherstellung tatsächlich anwendet. Profil-Einstellungen
    /// können die globalen Schalter nur einschränken, nie erweitern.
    struct RestorePlan: Equatable {
        var positions: Bool
        var hiddenIcons: Bool
        var wallpaper: Bool
        var apps: Bool
        var browserTabs: Bool
        var systemStateAndCleanup: Bool
    }

    static func restorePlan(settings: [String: Any], includeWallpaper: Bool,
                            includeApps: Bool, iconsOnly: Bool) -> RestorePlan {
        func flag(_ key: String) -> Bool { settings[key] as? Bool ?? true }
        return RestorePlan(
            positions: flag("restore_positions"),
            hiddenIcons: flag("capture_hidden"),
            wallpaper: !iconsOnly && includeWallpaper && flag("restore_wallpaper"),
            apps: !iconsOnly && includeApps && flag("restore_apps"),
            browserTabs: !iconsOnly && includeApps && flag("restore_browser_tabs"),
            systemStateAndCleanup: !iconsOnly)
    }

    /// Apps, die beim Ausblenden/Beenden anderer Apps erhalten bleiben. Browser,
    /// die eben mit Profil-Tabs neu gestartet wurden, gehören immer dazu.
    static func appsToKeep(profileApps: [Apps.AppInfo],
                           browserTabs: [String: [String]]) -> [Apps.AppInfo] {
        profileApps + browserTabs.keys.sorted().map {
            Apps.AppInfo(name: "", bundleID: $0, path: "")
        }
    }

    static func parsePositions(_ raw: Any?) -> [String: (x: Int, y: Int)] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var result: [String: (x: Int, y: Int)] = [:]
        for (name, value) in dict {
            guard let pos = JSONNumber.intDict(value, keys: ["x", "y"]) else { continue }
            result[name] = (pos["x"] ?? 0, pos["y"] ?? 0)
        }
        return result
    }

    static func restore(_ name: String, includeWallpaper: Bool = true, includeApps: Bool = false,
                        hideOthers: Bool = false, quitOthers: Bool = false,
                        launchDelay: Double = 1.5, iconsOnly: Bool = false,
                        shouldCancel: @escaping () -> Bool = { false }) -> RestoreResult {
        guard let data = load(name) else {
            return RestoreResult(success: 0, failed: 0,
                                 error: L("Profil '\(name)' nicht gefunden", "Profile '\(name)' not found"),
                                 warning: nil)
        }
        let hiddenList = Set((data["hidden"] as? [Any])?.compactMap { $0 as? String } ?? [])
        let settings = data["settings"] as? [String: Any] ?? [:]
        let plan = restorePlan(settings: settings, includeWallpaper: includeWallpaper,
                               includeApps: includeApps, iconsOnly: iconsOnly)

        let profileApps = parseApps(data["apps"])
        // Nicht ausgewählte Browser werden nie neu gestartet, auch wenn ältere
        // Speicherstände noch Tabs für sie enthalten.
        let browserSelection = BrowserTabs.selectedBrowsers(
            appNames: settings["included_apps"] as? [String],
            bundleIDs: Set(profileApps.compactMap(\.bundleID)))
        let profileBrowserTabs = BrowserTabs.limited(BrowserTabs.parse(data["browser_tabs"]), to: browserSelection)
        let savedBrowserTabs = plan.browserTabs ? profileBrowserTabs : [:]
        var savedBrowserWindows = plan.browserTabs
            ? BrowserTabs.limited(BrowserTabs.parseWindowPositions(data["browser_windows"]), to: browserSelection)
            : [:]
        // Abwärtskompatibilität: ältere Profile haben Browser-Fenster nur
        // innerhalb der allgemeinen App-Daten gespeichert.
        if plan.browserTabs && savedBrowserWindows.isEmpty {
            for app in profileApps {
                guard let bundleID = app.bundleID,
                      savedBrowserTabs[bundleID] != nil,
                      !app.windows.isEmpty else { continue }
                savedBrowserWindows[bundleID] = app.windows
            }
        }
        let generalApps = appsForGeneralLaunch(profileApps, browserTabs: savedBrowserTabs)
        var warnings: [String] = []

        // Browser mit gespeicherten Tabs werden nie zusätzlich über
        // Apps.launch gestartet.
        if plan.browserTabs {
            let browserResult = BrowserTabs.restore(
                savedBrowserTabs,
                windowPositions: savedBrowserWindows,
                shouldCancel: shouldCancel)
            if !browserResult.failedBrowsers.isEmpty {
                let browsers = browserResult.failedBrowsers.joined(separator: ", ")
                warnings.append(L("Browser konnte nicht beendet oder mit den gespeicherten Tabs gestartet werden (\(browsers)).",
                                  "Browser could not be quit or started with the saved tabs (\(browsers))."))
            }
        }
        if shouldCancel() {
            return RestoreResult(success: 0, failed: 0, error: nil, warning: nil)
        }

        // Sichtbarkeit nur anwenden, wenn das Profil versteckte Icons erfasst
        // hat – sonst würde ein Profil ohne diese Option alles einblenden.
        if plan.hiddenIcons {
            let visibility = DesktopIcons.getAllItems().map {
                (name: $0.name, hidden: hiddenList.contains($0.name))
            }
            DesktopIcons.applyVisibility(visibility)
        }

        var success = 0, failed = 0
        if plan.positions {
            let positions = parsePositions(data["positions"])
            let r = DesktopIcons.setPositions(positions, shouldCancel: shouldCancel)
            success = r.success; failed = r.failed
        }

        if plan.wallpaper {
            if let arr = data["wallpaper"] as? [String], !arr.isEmpty { Wallpaper.set(arr) }
            else if let s = data["wallpaper"] as? String, !s.isEmpty { Wallpaper.set([s]) }
        }

        if shouldCancel() {
            return RestoreResult(success: success, failed: failed, error: nil, warning: nil)
        }
        if plan.apps && !generalApps.isEmpty {
            Apps.launch(generalApps, staggerDelay: launchDelay,
                        shouldCancel: shouldCancel)
        }
        if plan.systemStateAndCleanup {
            // Wie im stabilen GitHub-Stand erst ganz am Ende bereinigen. So kann
            // keine nachfolgende App- oder Browser-Wiederherstellung eine zuvor
            // ausgeblendete Anwendung (z. B. Thunderbird) wieder einblenden.
            // Browser mit gespeicherten Tabs gehören zum Profil, auch wenn die
            // Tabs bei diesem Auslöser nicht wiederhergestellt wurden.
            let keep = appsToKeep(profileApps: profileApps, browserTabs: profileBrowserTabs)
            if quitOthers { _ = Apps.quitOthers(keep: keep) }
            else if hideOthers { _ = Apps.hideOthers(keep: keep) }

            if let state = data["system_state"] as? [String: Any] { SystemState.restore(state) }
        }

        let savedLayout = JSONNumber.intDicts(data["display_layout"], keys: JSONNumber.frameKeys)
        if plan.positions, !savedLayout.isEmpty {
            if !Displays.layoutsMatch(savedLayout, Displays.getLayout()) {
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
                windows: JSONNumber.intDicts(d["windows"], keys: JSONNumber.frameKeys)
            )
        }
    }

    static func appsForGeneralLaunch(_ apps: [Apps.AppInfo],
                                     browserTabs: [String: [String]]) -> [Apps.AppInfo] {
        apps.filter { app in
            guard let bundleID = app.bundleID else { return true }
            return browserTabs[bundleID] == nil
        }
    }

    /// Entfernt Auto-Umschalt-Regeln, die auf ein gelöschtes Profil zeigen.
    static func autoSwitchRules(_ rules: [[String: Any]], removingProfile name: String) -> [[String: Any]] {
        rules.filter { ($0["profile"] as? String) != name }
    }

    @discardableResult
    static func delete(_ name: String) -> Bool {
        guard let url = profilePath(name) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }
}
