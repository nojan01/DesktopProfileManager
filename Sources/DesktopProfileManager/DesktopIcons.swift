import Foundation
import AppKit

/// Desktop-Icon-Positionen und Sichtbarkeit von Desktop-Dateien.
enum DesktopIcons {

    /// Liest alle Desktop-Icon-Positionen als [name: (x, y)].
    static func getPositions() -> [String: (x: Int, y: Int)] {
        let script = """
        tell application "Finder"
            set output to ""
            set allItems to every item of desktop
            repeat with anItem in allItems
                set itemName to name of anItem as text
                set itemPos to desktop position of anItem
                set x to item 1 of itemPos
                set y to item 2 of itemPos
                set output to output & itemName & "||" & x & "||" & y & linefeed
            end repeat
            return output
        end tell
        """
        guard let raw = Shell.runAppleScript(script) else { return [:] }
        var positions: [String: (x: Int, y: Int)] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.components(separatedBy: "||")
            if parts.count == 3,
               let x = Double(parts[1]), let y = Double(parts[2]) {
                positions[parts[0]] = (Int(x), Int(y))
            }
        }
        return positions
    }

    /// Setzt Positionen per Referenz-Iteration (umgeht macOS-Namen-Lookup-Bug).
    @discardableResult
    static func setPositions(_ positions: [String: (x: Int, y: Int)]) -> (success: Int, failed: Int) {
        if positions.isEmpty { return (0, 0) }
        var entries: [String] = []
        for (name, pos) in positions {
            entries.append("{\"\(Shell.esc(name))\", \(pos.x), \(pos.y)}")
        }
        let targets = "{" + entries.joined(separator: ", ") + "}"
        let script = """
        set targets to \(targets)
        set successCount to 0
        set failedCount to 0
        tell application "Finder"
            set allItems to every item of desktop
            repeat with t in targets
                set tName to item 1 of t
                set tX to item 2 of t
                set tY to item 3 of t
                set foundIt to false
                repeat with anItem in allItems
                    try
                        if (name of anItem as text) is tName then
                            set desktop position of anItem to {tX, tY}
                            set successCount to successCount + 1
                            set foundIt to true
                            exit repeat
                        end if
                    end try
                end repeat
                if not foundIt then set failedCount to failedCount + 1
            end repeat
        end tell
        return (successCount as text) & "|" & (failedCount as text)
        """
        guard let result = Shell.runAppleScript(script) else { return (0, positions.count) }
        let parts = result.components(separatedBy: "|")
        if parts.count == 2, let s = Int(parts[0]), let f = Int(parts[1]) {
            return (s, f)
        }
        return (0, positions.count)
    }

    // MARK: - Sichtbarkeit (versteckte Desktop-Dateien)

    struct DesktopItem { let name: String; let hidden: Bool }

    static func getAllItems() -> [DesktopItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: Paths.desktop,
                                                        includingPropertiesForKeys: [.isHiddenKey],
                                                        options: []) else { return [] }
        var items: [DesktopItem] = []
        for url in entries {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            let hidden = (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden ?? false
            items.append(DesktopItem(name: name, hidden: hidden))
        }
        return items.sorted { $0.name < $1.name }
    }

    static func getHiddenItems() -> [String] {
        return getAllItems().filter { $0.hidden }.map { $0.name }
    }

    @discardableResult
    static func hideItem(_ name: String) -> Bool {
        return setHidden(name, true)
    }

    @discardableResult
    static func unhideItem(_ name: String) -> Bool {
        return setHidden(name, false)
    }

    private static func setHidden(_ name: String, _ hidden: Bool) -> Bool {
        let url = Paths.desktop.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            var values = URLResourceValues()
            values.isHidden = hidden
            var mutableURL = url
            try mutableURL.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }
}
