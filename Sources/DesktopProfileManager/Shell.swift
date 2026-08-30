import Foundation
import Darwin

/// Hilfsfunktionen zum Ausführen externer Prozesse und AppleScript.
enum Shell {

    private final class DataBox {
        private let lock = NSLock()
        private var data = Data()

        func store(_ newData: Data) {
            lock.lock()
            data = newData
            lock.unlock()
        }

        func load() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    /// Führt einen Prozess aus und gibt (stdout, exitCode) zurück.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 30,
                    shouldCancel: () -> Bool = { false }) -> (output: String, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        // `Process.waitUntilExit()` kann auf neueren macOS-Versionen in einem
        // CFRunLoop hängen bleiben, obwohl der Kindprozess bereits verschwunden
        // ist. Der Completion-Handler signalisiert dasselbe Ereignis, ohne dafür
        // dauerhaft einen blockierenden Worker-Thread zu belegen.
        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }
        do {
            try process.run()
        } catch {
            return ("", -1)
        }
        // Die Schreibenden gehören nach dem Spawn nur noch dem Kindprozess.
        // Offene Eltern-Handles würden sonst das EOF der Leser verzögern.
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()

        // Pipes sofort leeren: Andernfalls blockiert ein Kindprozess bei großer
        // Ausgabe am Pipe-Puffer, bevor `waitUntilExit()` zurückkehren kann.
        let ioGroup = DispatchGroup()
        let outputData = DataBox()
        ioGroup.enter()
        DispatchQueue.global().async {
            outputData.store(outputPipe.fileHandleForReading.readDataToEndOfFile())
            ioGroup.leave()
        }
        ioGroup.enter()
        DispatchQueue.global().async {
            _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
            ioGroup.leave()
        }

        // In kurzen Intervallen warten, damit ein neuer Profilwechsel den noch
        // laufenden externen Prozess abbrechen kann.
        let deadline = Date().addingTimeInterval(timeout)
        var interrupted = false
        var terminated = false
        while terminationSemaphore.wait(timeout: .now() + 0.1) == .timedOut {
            if shouldCancel() || Date() >= deadline {
                interrupted = true
                break
            }
        }
        if !interrupted { terminated = true }
        if interrupted {
            process.terminate()
            // `terminate()` kann ignoriert werden. Auch nach SIGKILL niemals
            // unbegrenzt warten: Foundation kann bei einem verlorenen Child-
            // Exit-Ereignis sonst die gesamte Restore-Queue dauerhaft blockieren.
            if terminationSemaphore.wait(timeout: .now() + 2) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                terminated = terminationSemaphore.wait(timeout: .now() + 1) == .success
            } else {
                terminated = true
            }
        }

        // Auch Pipe-Leser erhalten eine feste Obergrenze. Abkömmlinge eines
        // beendeten Prozesses können geerbte Deskriptoren sonst offen halten.
        if ioGroup.wait(timeout: .now() + 2) == .timedOut {
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            _ = ioGroup.wait(timeout: .now() + 1)
        }

        let out = String(data: outputData.load(), encoding: .utf8) ?? ""
        // `terminationStatus` ist nur definiert, nachdem Foundation das
        // Terminierungsereignis tatsächlich gemeldet hat.
        let code = interrupted || !terminated ? Int32(-1) : process.terminationStatus
        return (out.trimmingCharacters(in: .whitespacesAndNewlines), code)
    }

    /// Führt ein AppleScript via `osascript` aus und liefert auch den Exit-Status.
    static func runAppleScriptResult(_ script: String, timeout: TimeInterval = 30,
                                     shouldCancel: () -> Bool = { false }) -> (output: String, code: Int32) {
        run("/usr/bin/osascript", ["-e", script], timeout: timeout,
            shouldCancel: shouldCancel)
    }

    /// Führt ein AppleScript via `osascript` aus. Gibt nil bei Fehler zurück.
    @discardableResult
    static func runAppleScript(_ script: String, timeout: TimeInterval = 30,
                               shouldCancel: () -> Bool = { false }) -> String? {
        let result = runAppleScriptResult(script, timeout: timeout,
                                          shouldCancel: shouldCancel)
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
