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

    /// Öffnet die gespeicherten URLs als neue Tabs. Die Browser werden dabei bei
    /// Bedarf gestartet; vorhandene Fenster und Tabs bleiben unverändert.
    @discardableResult
    static func restore(_ savedTabs: [String: [String]]) -> RestoreOutcome {
        var openedTabs = 0
        var failedBrowsers: [String] = []
        for browser in supportedBrowsers {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil,
                  let urls = savedTabs[browser.bundleID] else { continue }
            let valid = validURLs(urls)
            guard !valid.isEmpty else { continue }

            let script = restoreScript(browserName: browser.name,
                                       urls: valid)
            if Shell.runAppleScript(script) != nil {
                openedTabs += valid.count
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

    /// Browser erzeugen beim Start häufig einen zusätzlichen leeren Startseiten-Tab.
    /// Der Browser kann zuvor bereits durch die App-Wiederherstellung gestartet worden
    /// sein. Daher wird nicht der Prozessstatus, sondern die Startseiten-URL geprüft.
    /// Bereits vorhandene Nutzer-Tabs bleiben unverändert.
    static func restoreScript(browserName: String, urls: [String]) -> String {
        guard let firstURL = urls.first else { return "" }
        let allTabCommands = tabCreationCommands(urls)
        let remainingTabCommands = tabCreationCommands(Array(urls.dropFirst()))
        return """
        tell application "\(browserName)"
            activate
            if (count of windows) is 0 then
                make new window
            end if
            tell front window
                set reuseStartPageTab to false
                try
                    set firstTabURL to URL of tab 1
                    if firstTabURL is in {"favorites://", "about:blank", "chrome://newtab/", "edge://newtab/", "safari://startpage", "safari://startpage/"} then
                        set reuseStartPageTab to true
                    end if
                end try
                if reuseStartPageTab then
                    set URL of tab 1 to "\(Shell.esc(firstURL))"
        \(remainingTabCommands)
                else
        \(allTabCommands)
                end if
            end tell
        end tell
        """
    }
}
