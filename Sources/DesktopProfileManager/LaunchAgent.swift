import Foundation

/// Autostart über einen macOS LaunchAgent (analog zur Python-App).
enum LaunchAgentManager {
    static let label = "com.desktopprofilemanager.swift"
    static var plistPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistPath.path)
    }

    /// Pfad zur laufenden ausführbaren Datei.
    private static func executablePath() -> String {
        return Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    static func enable() {
        let exe = executablePath()
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
                <string>\(exe)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        try? FileManager.default.createDirectory(at: plistPath.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? plist.write(to: plistPath, atomically: true, encoding: .utf8)
        Shell.run("/bin/launchctl", ["load", plistPath.path])
    }

    static func disable() {
        if isEnabled() {
            Shell.run("/bin/launchctl", ["unload", plistPath.path])
            try? FileManager.default.removeItem(at: plistPath)
        }
    }
}
