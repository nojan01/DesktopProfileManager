import AppKit
import Foundation

/// Sichert und öffnet Browser-Tabs für die Browser mit AppleScript-Schnittstelle.
/// Firefox stellt keine verlässliche öffentliche Schnittstelle zum Auslesen
/// vorhandener Tabs bereit und wird deshalb bewusst nicht erfasst.
enum BrowserTabs {
    struct RestoreOutcome {
        let openedTabs: Int
        let failedBrowsers: [String]
    }

    private struct Browser {
        let name: String
        let bundleID: String
    }

    private static let supportedBrowsers = [
        Browser(name: "Safari", bundleID: "com.apple.Safari"),
        Browser(name: "Google Chrome", bundleID: "com.google.Chrome"),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac"),
    ]

    /// Liest Web- und lokale Datei-Tabs aktuell laufender unterstützter Browser aus.
    static func capture() -> [String: [String]] {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var result: [String: [String]] = [:]
        for browser in supportedBrowsers where runningBundleIDs.contains(browser.bundleID) {
            let script = """
            tell application "\(browser.name)"
                set output to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set output to output & (URL of t) & linefeed
                        end try
                    end repeat
                end repeat
                return output
            end tell
            """
            guard let output = Shell.runAppleScript(script) else { continue }
            let urls = validURLs(output.split(separator: "\n").map(String.init))
            if !urls.isEmpty { result[browser.bundleID] = urls }
        }
        return result
    }

    /// Stellt jeden gespeicherten Browser in einem eigenen Profilfenster wieder her.
    /// Erst wenn alle Profil-Tabs erzeugt wurden, werden ältere Fenster geschlossen.
    /// Damit bleibt beim Profilwechsel ausschließlich der gespeicherte Satz an Tabs.
    @discardableResult
    static func restore(_ savedTabs: [String: [String]]) -> RestoreOutcome {
        var openedTabs = 0
        var failedBrowsers: [String] = []
        for browser in supportedBrowsers {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil,
                  let urls = savedTabs[browser.bundleID] else { continue }
            let valid = validURLs(urls)
            guard !valid.isEmpty else { continue }

            let creationScript = restoreScript(browserName: browser.name,
                                               urls: valid)
            if Shell.runAppleScript(creationScript) != nil {
                openedTabs += valid.count
                // Das Bereinigen ist bewusst ein zweites, unabhängiges Script:
                // Ein Fehler beim Schließen alter Fenster darf niemals das zuvor
                // erfolgreiche Öffnen der Profil-Tabs rückgängig machen.
                _ = Shell.runAppleScript(cleanupScript(browserName: browser.name))
            } else {
                failedBrowsers.append(browser.name)
            }
        }
        return RestoreOutcome(openedTabs: openedTabs, failedBrowsers: failedBrowsers)
    }

    static func parse(_ raw: Any?) -> [String: [String]] {
        guard let dictionary = raw as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for (bundleID, value) in dictionary {
            let urls = validURLs(value as? [String] ?? [])
            if !urls.isEmpty { result[bundleID] = urls }
        }
        return result
    }

    /// Safari kann beim Speichern vorübergehend keine URLs liefern, etwa während
    /// einer Sitzungswiederherstellung. In diesem Fall dürfen beim Überschreiben
    /// eines Profils bereits gespeicherte Tabs nicht verloren gehen.
    static func tabsForSave(captured: [String: [String]], existing: Any?,
                            captureRequested: Bool) -> (tabs: [String: [String]], preserved: Bool) {
        guard captureRequested, captured.isEmpty else {
            return (captured, false)
        }
        let previous = parse(existing)
        guard !previous.isEmpty else { return (captured, false) }
        return (previous, true)
    }

    static func validURLs(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased() else { return false }

            let isWebURL = ["http", "https"].contains(scheme) && url.host != nil
            // Nur lokale, absolute Datei-URLs akzeptieren. file://<fremder-host>/...
            // wird bewusst ausgeschlossen, damit keine Netzwerkfreigaben geöffnet werden.
            let isLocalFileURL = scheme == "file"
                && url.isFileURL
                && (url.host == nil || url.host?.lowercased() == "localhost")
                && url.path.hasPrefix("/")
            guard isWebURL || isLocalFileURL else { return false }
            return seen.insert(candidate).inserted
        }
    }

    /// Der Befehl läuft bereits im Kontext von `tell front window`. Eine zweite
    /// Referenz auf `front window` würde Safari als Fenster-eines-Fensters
    /// interpretieren und das Öffnen der Tabs fehlschlagen lassen.
    static func tabCreationCommands(_ urls: [String]) -> String {
        urls.map {
            "    make new tab at end of tabs with properties {URL:\"\(Shell.esc($0))\"}"
        }.joined(separator: "\n")
    }

    /// Erstellt ein neues Browserfenster für das Profil und füllt es vollständig.
    /// Das Schließen alter Fenster ist davon getrennt, damit es die Wiederherstellung
    /// nicht blockieren kann.
    static func restoreScript(browserName: String, urls: [String]) -> String {
        guard let firstURL = urls.first else { return "" }
        let remainingTabCommands = tabCreationCommands(Array(urls.dropFirst()))
        return """
        tell application "\(browserName)"
            activate
            make new window
            tell front window
                try
                    set URL of tab 1 to "\(Shell.esc(firstURL))"
                on error
                    make new tab at end of tabs with properties {URL:"\(Shell.esc(firstURL))"}
                end try
        \(remainingTabCommands)
            end tell
        end tell
        """
    }

    /// Behält das soeben erzeugte Vordergrundfenster und schließt nur ältere
    /// Browserfenster. Fehler werden im aufrufenden Code absichtlich ignoriert,
    /// weil die Profil-Tabs zu diesem Zeitpunkt bereits geöffnet sind.
    static func cleanupScript(browserName: String) -> String {
        """
        tell application "\(browserName)"
            set profileWindowID to id of front window
            repeat while (count of windows) > 1
                try
                    if (id of window 1) is profileWindowID then
                        close window 2
                    else
                        close window 1
                    end if
                on error
                    exit repeat
                end try
            end repeat
        end tell
        """
    }
}
