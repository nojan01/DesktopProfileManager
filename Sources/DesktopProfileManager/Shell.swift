import Foundation
import Darwin

/// Hilfsfunktionen zum Ausführen externer Prozesse und AppleScript.
enum Shell {

    /// Führt einen Prozess aus und gibt (stdout, exitCode) zurück.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 30) -> (output: String, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            return ("", -1)
        }

        // Pipes sofort leeren: Andernfalls blockiert ein Kindprozess bei großer
        // Ausgabe am Pipe-Puffer, bevor `waitUntilExit()` zurückkehren kann.
        let ioGroup = DispatchGroup()
        var outputData = Data()
        ioGroup.enter()
        DispatchQueue.global().async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            ioGroup.leave()
        }
        ioGroup.enter()
        DispatchQueue.global().async {
            _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
            ioGroup.leave()
        }

        // Timeout über einen Watchdog-Thread
        let deadline = DispatchTime.now() + timeout
        let terminationGroup = DispatchGroup()
        terminationGroup.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            terminationGroup.leave()
        }
        let timedOut = terminationGroup.wait(timeout: deadline) == .timedOut
        if timedOut {
            process.terminate()
            // `terminate()` kann ignoriert werden; dann Prozess hart beenden,
            // damit die Pipe-Leser nicht unbegrenzt auf ihr EOF warten.
            if terminationGroup.wait(timeout: .now() + 2) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                terminationGroup.wait()
            }
        }
        ioGroup.wait()
        let out = String(data: outputData, encoding: .utf8) ?? ""
        return (out.trimmingCharacters(in: .whitespacesAndNewlines), timedOut ? -1 : process.terminationStatus)
    }

    /// Führt ein AppleScript via `osascript` aus. Gibt nil bei Fehler zurück.
    @discardableResult
    static func runAppleScript(_ script: String, timeout: TimeInterval = 30) -> String? {
        let result = run("/usr/bin/osascript", ["-e", script], timeout: timeout)
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
