import Foundation

/// Autostart über einen macOS LaunchAgent (analog zur Python-App).
enum LaunchAgentManager {
    static let label = "com.desktopprofilemanager.swift"
    static var plistPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func isEnabled() -> Bool {
        guard FileManager.default.fileExists(atPath: plistPath.path) else { return false }
        return Shell.run("/bin/launchctl", ["print", "\(guiDomain)/\(label)"], timeout: 5).code == 0
    }

    /// GUI-Domain-Ziel des aktuellen Benutzers, z. B. "gui/501".
    private static var guiDomain: String {
        "gui/\(getuid())"
    }

    /// Pfad zur ausführbaren Datei, die beim Login gestartet werden soll.
    /// Bevorzugt den Pfad zur `.app` (über `open`), damit das vollständige
    /// Bundle (mit Info.plist/LSUIElement) gestartet wird und nicht nur das
    /// nackte Mach-O-Binary.
    private static func launchProgramArguments() -> [String] {
        // Bundle-Pfad ermitteln: .../Foo.app/Contents/MacOS/bin -> .../Foo.app
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            // Über `open -g` (im Hintergrund, ohne Fokus) das App-Bundle starten.
            return ["/usr/bin/open", "-g", bundleURL.path]
        }
        // Fallback (z. B. im DEV-Lauf ohne Bundle): direkt das Binary.
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return [exe]
    }

    /// Aktiviert den Agenten und gibt bei Fehler eine verständliche Meldung zurück.
    static func enable() -> String? {
        let programArgs = launchProgramArguments()
        let argsXML = programArgs
            .map { "        <string>\(xmlEscape($0))</string>" }
            .joined(separator: "\n")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
        \(argsXML)
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        do {
            try FileManager.default.createDirectory(at: plistPath.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try plist.write(to: plistPath, atomically: true, encoding: .utf8)
        } catch {
            return error.localizedDescription
        }

        // Eventuell vorhandenen (alten) Agent zuerst entladen, damit ein
        // erneutes Bootstrap nicht an "service already loaded" scheitert.
        Shell.run("/bin/launchctl", ["bootout", "\(guiDomain)/\(label)"])
        // Modernes Laden in der GUI-Domain des Benutzers.
        let bootstrap = Shell.run("/bin/launchctl", ["bootstrap", guiDomain, plistPath.path])
        if bootstrap.code != 0 {
            // Fallback für ältere Systeme: legacy load.
            let legacy = Shell.run("/bin/launchctl", ["load", "-w", plistPath.path])
            guard legacy.code == 0 else {
                return L("launchctl konnte den Autostart nicht laden.",
                         "launchctl could not load the start-at-login service.")
            }
        }
        // Sicherstellen, dass der Dienst nicht als deaktiviert markiert ist.
        let enabled = Shell.run("/bin/launchctl", ["enable", "\(guiDomain)/\(label)"])
        guard enabled.code == 0, isEnabled() else {
            return L("Der Autostart wurde nicht von launchd bestätigt.",
                     "launchd did not confirm start at login.")
        }
        return nil
    }

    /// Deaktiviert den Agenten und gibt bei Fehler eine verständliche Meldung zurück.
    static func disable() -> String? {
        // Dienst aus der GUI-Domain entfernen (modern + legacy als Fallback).
        let result = Shell.run("/bin/launchctl", ["bootout", "\(guiDomain)/\(label)"])
        if result.code != 0 && isEnabled() {
            let legacy = Shell.run("/bin/launchctl", ["unload", "-w", plistPath.path])
            guard legacy.code == 0 else {
                return L("launchctl konnte den Autostart nicht entfernen.",
                         "launchctl could not remove the start-at-login service.")
            }
        }
        do {
            if FileManager.default.fileExists(atPath: plistPath.path) {
                try FileManager.default.removeItem(at: plistPath)
            }
        } catch {
            return error.localizedDescription
        }
        return isEnabled()
            ? L("Der Autostart ist weiterhin aktiv.", "Start at login is still active.")
            : nil
    }

    /// Escaped die für XML-Textinhalte gefährlichen Zeichen.
    private static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
