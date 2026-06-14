import Foundation

/// Hilfsfunktionen zum Ausführen externer Prozesse und AppleScript.
enum Shell {

    /// Führt einen Prozess aus und gibt (stdout, exitCode) zurück.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 30) -> (output: String, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ("", -1)
        }
        // Einfaches Timeout über einen Watchdog-Thread
        let deadline = DispatchTime.now() + timeout
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return ("", -1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (out.trimmingCharacters(in: .whitespacesAndNewlines), process.terminationStatus)
    }

    /// Führt ein AppleScript via `osascript` aus. Gibt nil bei Fehler zurück.
    @discardableResult
    static func runAppleScript(_ script: String) -> String? {
        let result = run("/usr/bin/osascript", ["-e", script])
        if result.code != 0 {
            return nil
        }
        return result.output
    }

    /// Escaped einen String für die Verwendung in AppleScript-Literalen.
    static func esc(_ text: String) -> String {
        return text.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
