import Foundation
import AppKit

/// Erfassen/Starten/Verbergen laufender Apps inkl. Fenstergeometrie.
enum Apps {

    static let appBlacklistBundles: Set<String> = [
        "com.apple.finder", "com.iconguard.app", "com.desktopprofilemanager.app"
    ]
    static let appBlacklistNames: Set<String> = [Paths.appName, "Finder"]

    struct AppInfo {
        var name: String
        var bundleID: String?
        var path: String
        var windows: [[String: Int]] = []
    }

    /// Aktuell sichtbare (reguläre) Apps via NSWorkspace.
    static func getRunning() -> [AppInfo] {
        var apps: [AppInfo] = []
        for ra in NSWorkspace.shared.runningApplications {
            if ra.activationPolicy != .regular { continue }
            guard let name = ra.localizedName, let url = ra.bundleURL else { continue }
            let bundleID = ra.bundleIdentifier
            if let bid = bundleID, appBlacklistBundles.contains(bid) { continue }
            if appBlacklistNames.contains(name) { continue }
            apps.append(AppInfo(name: name, bundleID: bundleID, path: url.path))
        }
        return apps
    }

    /// Liefert pro Prozessname die Fenster-Geometrien (benötigt Bedienungshilfen).
    static func getWindows() -> [String: [[String: Int]]] {
        let script = """
        tell application "System Events"
            set output to ""
            repeat with proc in (every process whose background only is false)
                set procName to name of proc
                try
                    repeat with w in windows of proc
                        set p to position of w
                        set s to size of w
                        set output to output & procName & "||" & (item 1 of p) & "||" & (item 2 of p) & "||" & (item 1 of s) & "||" & (item 2 of s) & linefeed
                    end repeat
                end try
            end repeat
            return output
        end tell
        """
        guard let raw = Shell.runAppleScript(script) else { return [:] }
        var result: [String: [[String: Int]]] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.components(separatedBy: "||")
            if parts.count != 5 { continue }
            guard let x = Double(parts[1]), let y = Double(parts[2]),
                  let w = Double(parts[3]), let h = Double(parts[4]) else { continue }
            result[parts[0], default: []].append(["x": Int(x), "y": Int(y), "w": Int(w), "h": Int(h)])
        }
        return result
    }

    /// Erfasst laufende Apps inkl. Fenster; ausgeschlossene Namen werden ausgelassen.
    static func capture(exclusions: Set<String>) -> [AppInfo] {
        var apps = getRunning().filter { !exclusions.contains($0.name) }
        let windows = getWindows()
        for i in apps.indices {
            apps[i].windows = windows[apps[i].name] ?? []
        }
        return apps
    }

    static func restoreWindows(_ apps: [AppInfo]) {
        for app in apps {
            if app.windows.isEmpty { continue }
            let name = Shell.esc(app.name)
            var lines = ["tell application \"System Events\"", "  tell process \"\(name)\""]
            for (i, w) in app.windows.enumerated() {
                lines.append("    try")
                lines.append("      set position of window \(i + 1) to {\(w["x"] ?? 0), \(w["y"] ?? 0)}")
                lines.append("      set size of window \(i + 1) to {\(w["w"] ?? 0), \(w["h"] ?? 0)}")
                lines.append("    end try")
            }
            lines.append("  end tell")
            lines.append("end tell")
            _ = Shell.runAppleScript(lines.joined(separator: "\n"))
        }
    }

    private static func setVisible(_ names: [String], _ visible: Bool) {
        let names = names.filter { !$0.isEmpty }
        if names.isEmpty { return }
        let val = visible ? "true" : "false"
        var lines = ["tell application \"System Events\""]
        for n in names {
            lines.append("  try")
            lines.append("    set visible of process \"\(Shell.esc(n))\" to \(val)")
            lines.append("  end try")
        }
        lines.append("end tell")
        _ = Shell.runAppleScript(lines.joined(separator: "\n"))
    }

    /// Startet Apps gestaffelt und stellt ihre Fenster wieder her.
    @discardableResult
    static func launch(_ apps: [AppInfo], staggerDelay: Double = 1.5) -> Int {
        var launched = 0
        let runningNames = Set(getRunning().map { $0.name })
        var toUnhide: [String] = []
        for app in apps {
            let alreadyRunning = runningNames.contains(app.name)
            // Bereits laufende Apps zusätzlich wieder einblenden (falls per
            // System Events ausgeblendet).
            if alreadyRunning { toUnhide.append(app.name) }

            // In JEDEM Fall öffnen/aktivieren – auch bereits laufende Apps.
            // `open -b` startet die App, bringt sie nach vorn und öffnet bei
            // fensterlosen Apps (z. B. Safari ohne offenes Fenster) ein neues
            // Fenster. Bevorzugt über die Bundle-ID (stabil, auch wenn sich der
            // Pfad ändert, z. B. Apple-Apps im Cryptex-Volume). Fällt auf den
            // Pfad bzw. den Namen zurück.
            var ok = false
            if let bid = app.bundleID, !bid.isEmpty {
                ok = Shell.run("/usr/bin/open", ["-b", bid], timeout: 20).code == 0
            }
            if !ok {
                let target = app.path.isEmpty ? app.name : app.path
                if !target.isEmpty {
                    ok = Shell.run("/usr/bin/open", ["-a", target], timeout: 20).code == 0
                }
            }
            if !ok && !app.name.isEmpty {
                ok = Shell.run("/usr/bin/open", ["-a", app.name], timeout: 20).code == 0
            }
            // Nur echte Kaltstarts gestaffelt verzögern – bereits laufende Apps
            // sind sofort da und brauchen keine Wartezeit.
            if ok && !alreadyRunning {
                launched += 1
                Thread.sleep(forTimeInterval: staggerDelay)
            }
        }
        if !toUnhide.isEmpty { setVisible(toUnhide, true) }
        if apps.contains(where: { !$0.windows.isEmpty }) {
            Thread.sleep(forTimeInterval: 3)
            restoreWindows(apps)
        }
        return launched
    }

    @discardableResult
    static func hideOthers(keep: [AppInfo]) -> Int {
        let keepBundles = Set(keep.compactMap { $0.bundleID })
        let keepNames = Set(keep.map { $0.name })
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var toHide: [String] = []
        for ra in NSWorkspace.shared.runningApplications {
            if ra.activationPolicy != .regular { continue }
            if ra.processIdentifier == ownPID { continue }
            guard let name = ra.localizedName else { continue }
            if let bid = ra.bundleIdentifier, appBlacklistBundles.contains(bid) { continue }
            if appBlacklistNames.contains(name) { continue }
            if let bid = ra.bundleIdentifier, keepBundles.contains(bid) { continue }
            if keepNames.contains(name) { continue }
            if ra.isHidden { continue }
            toHide.append(name)
        }
        setVisible(toHide, false)
        return toHide.count
    }

    @discardableResult
    static func quitOthers(keep: [AppInfo]) -> Int {
        let keepBundles = Set(keep.compactMap { $0.bundleID })
        let keepNames = Set(keep.map { $0.name })
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var count = 0
        for ra in NSWorkspace.shared.runningApplications {
            if ra.activationPolicy != .regular { continue }
            if ra.processIdentifier == ownPID { continue }
            guard let name = ra.localizedName else { continue }
            if let bid = ra.bundleIdentifier, appBlacklistBundles.contains(bid) { continue }
            if appBlacklistNames.contains(name) { continue }
            if let bid = ra.bundleIdentifier, keepBundles.contains(bid) { continue }
            if keepNames.contains(name) { continue }
            if ra.terminate() { count += 1 }
        }
        return count
    }
}
