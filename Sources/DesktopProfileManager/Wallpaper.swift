import Foundation
import AppKit

/// Desktop-Hintergrund und Bildschirm-Anordnung.
enum Wallpaper {

    /// Liest die Hintergrundbild-Pfade aller Bildschirme.
    static func get() -> [String] {
        let script = """
        tell application "System Events"
            set output to ""
            repeat with d in every desktop
                set output to output & (picture of d) & linefeed
            end repeat
            return output
        end tell
        """
        guard let raw = Shell.runAppleScript(script) else { return [] }
        return raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Setzt den Hintergrund: eine Liste von Pfaden (einer pro Bildschirm).
    @discardableResult
    static func set(_ paths: [String]) -> Bool {
        let valid = paths.filter { !$0.isEmpty }
        if valid.isEmpty { return false }
        var lines = ["tell application \"System Events\"", "  set ds to every desktop"]
        for (i, path) in valid.enumerated() {
            if !FileManager.default.fileExists(atPath: path) { continue }
            lines.append("  try")
            lines.append("    set picture of (item \(i + 1) of ds) to \"\(Shell.esc(path))\"")
            lines.append("  end try")
        }
        lines.append("end tell")
        return Shell.runAppleScript(lines.joined(separator: "\n")) != nil
    }
}

enum Displays {
    struct Frame { let x: Int; let y: Int; let w: Int; let h: Int }

    static func getLayout() -> [Frame] {
        return NSScreen.screens.map { s in
            let f = s.frame
            return Frame(x: Int(f.origin.x.rounded()), y: Int(f.origin.y.rounded()),
                         w: Int(f.size.width.rounded()), h: Int(f.size.height.rounded()))
        }
    }

    /// Vergleicht zwei Bildschirm-Anordnungen (Anzahl + Geometrie).
    static func layoutsMatch(_ a: [[String: Int]], _ b: [Frame]) -> Bool {
        if a.isEmpty || b.isEmpty { return true }
        if a.count != b.count { return false }
        func norm(_ tuples: [[Int]]) -> [[Int]] { tuples.sorted { $0.lexicographicallyPrecedes($1) } }
        let na = norm(a.map { [$0["x"] ?? 0, $0["y"] ?? 0, $0["w"] ?? 0, $0["h"] ?? 0] })
        let nb = norm(b.map { [$0.x, $0.y, $0.w, $0.h] })
        return na == nb
    }
}
