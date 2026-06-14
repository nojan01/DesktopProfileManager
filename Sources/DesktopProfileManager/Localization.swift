import Foundation

/// Sprachsteuerung – entspricht der `L(de, en)`-Funktion der Python-App.
enum Localization {
    enum Lang { case de, en }

    static var current: Lang = .de

    /// Ermittelt die Systemsprache: "de" nur bei deutschem System, sonst "en".
    static func detectSystemLanguage() -> Lang {
        if let first = Locale.preferredLanguages.first,
           first.lowercased().hasPrefix("de") {
            return .de
        }
        return .en
    }

    /// Setzt `current` anhand der Konfiguration ("system" | "de" | "en").
    @discardableResult
    static func resolve(_ pref: String) -> Lang {
        switch pref {
        case "en": current = .en
        case "de": current = .de
        default: current = detectSystemLanguage()
        }
        return current
    }
}

/// Kurzform wie in Python: `L("Deutsch", "German")`.
func L(_ de: String, _ en: String) -> String {
    return Localization.current == .en ? en : de
}
