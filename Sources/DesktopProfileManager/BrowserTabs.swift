import AppKit
import Foundation

/// Sichert und öffnet Browser-Tabs für die Browser mit AppleScript-Schnittstelle.
/// Firefox stellt keine verlässliche öffentliche Schnittstelle zum Auslesen
/// vorhandener Tabs bereit und wird deshalb bewusst nicht erfasst.
enum BrowserTabs {
    /// Ein Browser erhält ausreichend Zeit für ein reguläres vollständiges
    /// Beenden. Ein erzwungenes Beenden wird wegen möglicher Datenverluste vermieden.
    static let quitTimeout: TimeInterval = 15
    static let windowRestoreDelay: TimeInterval = 2

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

    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    static func browserName(for bundleID: String) -> String {
        supportedBrowsers.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    /// Liest Web- und lokale Datei-Tabs aktuell laufender unterstützter Browser aus.
    static func capture() -> [String: [String]] {
        let running = runningBundleIDs()
        var result: [String: [String]] = [:]
        for browser in supportedBrowsers where running.contains(browser.bundleID) {
            guard let output = Shell.runAppleScript(captureScript(browserName: browser.name)) else { continue }
            let urls = validURLs(output.split(separator: "\n").map(String.init))
            if !urls.isEmpty { result[browser.bundleID] = urls }
        }
        return result
    }

    /// Inkognito-Fenster (Chrome/Edge) werden nicht gespeichert. Safari kennt die
    /// Eigenschaft `mode` nicht; der Fehler wird abgefangen und das Fenster normal
    /// erfasst.
    static func captureScript(browserName: String) -> String {
        """
        tell application "\(Shell.esc(browserName))"
            set output to ""
            repeat with w in windows
                set isPrivate to false
                try
                    if (mode of w as string) is "incognito" then set isPrivate to true
                end try
                if not isPrivate then
                    repeat with t in tabs of w
                        try
                            set output to output & (URL of t) & linefeed
                        end try
                    end repeat
                end if
            end repeat
            return output
        end tell
        """
    }

    /// Erfasst Browser-Fenster unabhängig davon, ob der Browser in der allgemeinen
    /// App-Auswahl des Profils enthalten ist. Die Zuordnung erfolgt über die
    /// Prozess-ID, weil Prozessnamen lokalisiert oder abweichend sein können.
    static func captureWindowPositions() -> [String: [[String: Int]]] {
        let windowsByPID = Apps.getWindowsByPID()
        var result: [String: [[String: Int]]] = [:]
        for application in NSWorkspace.shared.runningApplications {
            guard let bundleID = application.bundleIdentifier,
                  supportedBrowsers.contains(where: { $0.bundleID == bundleID }),
                  let windows = windowsByPID[application.processIdentifier],
                  !windows.isEmpty else { continue }
            result[bundleID, default: []].append(contentsOf: windows)
        }
        return result
    }

    /// Beendet den Browser vollständig und startet ihn anschließend mit allen
    /// gespeicherten URLs in einem Aufruf neu. Dadurch gibt es keine nachlaufende
    /// Tab-/Fensterbereinigung, die bereits geöffnete Profil-Tabs wieder schließt.
    @discardableResult
    static func restore(_ savedTabs: [String: [String]],
                        windowPositions: [String: [[String: Int]]] = [:],
                        shouldCancel: @escaping () -> Bool = { false }) -> RestoreOutcome {
        var openedTabs = 0
        var failedBrowsers: [String] = []
        for browser in supportedBrowsers {
            if shouldCancel() { break }
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil,
                  let urls = savedTabs[browser.bundleID] else { continue }
            let valid = validURLs(urls)
            guard !valid.isEmpty else { continue }

            let stopResult = stop(browserName: browser.name, bundleID: browser.bundleID,
                                  shouldCancel: shouldCancel)
            guard stopResult.stopped else {
                if shouldCancel() { break }
                failedBrowsers.append(stopResult.message ?? browser.name)
                continue
            }

            let result = Shell.run("/usr/bin/open",
                                   launchArguments(bundleID: browser.bundleID, urls: valid),
                                   timeout: 20)
            if result.code == 0 {
                openedTabs += valid.count
                if let windows = windowPositions[browser.bundleID], !windows.isEmpty,
                   cancellableDelay(windowRestoreDelay, shouldCancel: shouldCancel) {
                    let app = Apps.AppInfo(name: browser.name,
                                           bundleID: browser.bundleID,
                                           path: "",
                                           windows: windows)
                    // Der Prozess kann bereits laufen, während sein erstes Fenster
                    // noch entsteht. Mehrere kurze Versuche sind zuverlässiger als
                    // eine lange starre Pause.
                    for attempt in 0..<3 {
                        if shouldCancel() { break }
                        Apps.restoreWindows([app], shouldCancel: shouldCancel)
                        if attempt < 2 && !cancellableDelay(0.5, shouldCancel: shouldCancel) {
                            break
                        }
                    }
                }
            } else {
                failedBrowsers.append(browser.name)
            }
        }
        return RestoreOutcome(openedTabs: openedTabs, failedBrowsers: failedBrowsers)
    }

    static func launchArguments(bundleID: String, urls: [String]) -> [String] {
        ["-b", bundleID] + urls
    }

    static func quitScript(browserName: String) -> String {
        """
        ignoring application responses
            tell application "\(browserName)" to quit
        end ignoring
        """
    }

    private static func stop(browserName: String, bundleID: String,
                             shouldCancel: @escaping () -> Bool) -> (stopped: Bool, message: String?) {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }
        guard !running.isEmpty else { return (true, nil) }

        // Genau ein regulärer Beenden-Befehl wie bei ⌘Q. Nur wenn AppleScript
        // diesen Befehl gar nicht senden konnte, dient NSWorkspace als Fallback.
        let quitResult = Shell.runAppleScriptResult(
            quitScript(browserName: browserName), timeout: 2,
            shouldCancel: shouldCancel)
        if quitResult.code != 0 {
            for application in running where !application.isTerminated {
                _ = application.terminate()
            }
        }
        let stopped = waitUntilStopped(applications: running, timeout: quitTimeout,
                                       shouldCancel: shouldCancel)
        if stopped { return (true, nil) }
        return (false, L("\(browserName): Beenden wurde nach 15 Sekunden nicht abgeschlossen",
                         "\(browserName): quit did not complete within 15 seconds"))
    }

    private static func waitUntilStopped(applications: [NSRunningApplication], timeout: TimeInterval,
                                         shouldCancel: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if shouldCancel() { return false }
            // Nur die zuvor laufenden Instanzen beobachten. macOS darf Safari
            // anschließend vorladen, ohne dass dies als fehlgeschlagenes Beenden
            // der alten Browserinstanz gewertet wird.
            if applications.allSatisfy(\.isTerminated) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }

    private static func cancellableDelay(_ duration: TimeInterval,
                                         shouldCancel: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            if shouldCancel() { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !shouldCancel()
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

    static func parseWindowPositions(_ raw: Any?) -> [String: [[String: Int]]] {
        guard let dictionary = raw as? [String: Any] else { return [:] }
        var result: [String: [[String: Int]]] = [:]
        for (bundleID, rawWindows) in dictionary {
            guard let windows = rawWindows as? [Any] else { continue }
            let validWindows = windows.compactMap { rawWindow -> [String: Int]? in
                guard let window = JSONNumber.intDict(rawWindow, keys: JSONNumber.frameKeys),
                      (window["w"] ?? 0) > 0, (window["h"] ?? 0) > 0 else { return nil }
                return window
            }
            if !validWindows.isEmpty { result[bundleID] = validWindows }
        }
        return result
    }

    /// Ein laufender Browser kann beim Speichern vorübergehend keine URLs liefern,
    /// etwa während einer Sitzungswiederherstellung. Beim Überschreiben bleiben
    /// dann genau für diesen Browser die bisher gespeicherten Tabs erhalten.
    /// `runningBundleIDs == nil` behandelt alle Browser als laufend.
    static func tabsForSave(captured: [String: [String]], existing: Any?,
                            captureRequested: Bool, runningBundleIDs: Set<String>? = nil)
        -> (tabs: [String: [String]], preserved: [String]) {
        guard captureRequested else { return (captured, []) }
        var tabs = captured
        var preserved: [String] = []
        for (bundleID, urls) in parse(existing).sorted(by: { $0.key < $1.key })
        where captured[bundleID] == nil && (runningBundleIDs?.contains(bundleID) ?? true) {
            tabs[bundleID] = urls
            preserved.append(browserName(for: bundleID))
        }
        return (tabs, preserved)
    }

    static func windowPositionsForSave(captured: [String: [[String: Int]]],
                                       existing: Any?, captureRequested: Bool,
                                       runningBundleIDs: Set<String>? = nil) -> [String: [[String: Int]]] {
        guard captureRequested else { return captured }
        var result = captured
        for (bundleID, windows) in parseWindowPositions(existing)
        where captured[bundleID] == nil && (runningBundleIDs?.contains(bundleID) ?? true) {
            result[bundleID] = windows
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

}
