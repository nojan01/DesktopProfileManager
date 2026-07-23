import AppKit
import Foundation

/// Sichert und öffnet Browser-Tabs für die Browser mit AppleScript-Schnittstelle.
/// Firefox stellt keine verlässliche öffentliche Schnittstelle zum Auslesen
/// vorhandener Tabs bereit und wird deshalb bewusst nicht erfasst.
enum BrowserTabs {
    private struct Browser {
        let name: String
        let bundleID: String
    }

    private static let supportedBrowsers = [
        Browser(name: "Safari", bundleID: "com.apple.Safari"),
        Browser(name: "Google Chrome", bundleID: "com.google.Chrome"),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac"),
    ]

    /// Liest die HTTP(S)-Tabs aktuell laufender unterstützter Browser aus.
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
    static func restore(_ savedTabs: [String: [String]]) {
        for browser in supportedBrowsers {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil,
                  let urls = savedTabs[browser.bundleID] else { continue }
            let valid = validURLs(urls)
            guard !valid.isEmpty else { continue }

            let commands = valid.map {
                "    make new tab at end of tabs of front window with properties {URL:\"\(Shell.esc($0))\"}"
            }.joined(separator: "\n")
            let script = """
            tell application "\(browser.name)"
                activate
                if (count of windows) is 0 then make new window
                tell front window
            \(commands)
                end tell
            end tell
            """
            _ = Shell.runAppleScript(script)
        }
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
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else { return false }
            return seen.insert(candidate).inserted
        }
    }
}
