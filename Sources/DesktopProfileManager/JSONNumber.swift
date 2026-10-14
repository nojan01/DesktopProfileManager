import Foundation

/// Tolerantes Lesen von Zahlen aus JSON-Daten. Ältere bzw. aus der Python-App
/// stammende Profile enthalten Koordinaten teils als Fließkommazahlen.
enum JSONNumber {

    static func int(_ value: Any?) -> Int? {
        guard let value = value, !isBool(value) else { return nil }
        if let i = value as? Int { return i }
        if let d = value as? Double, d.isFinite, abs(d) < Double(Int.max) {
            return Int(d.rounded())
        }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        guard let value = value, !isBool(value) else { return nil }
        if let d = value as? Double, d.isFinite { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let value = value else { return nil }
        if isBool(value) { return value as? Bool }
        return nil
    }

    /// Liest ein Dictionary, dessen angegebene Schlüssel alle Zahlen sind.
    static func intDict(_ raw: Any?, keys: [String]) -> [String: Int]? {
        guard let dict = raw as? [String: Any] else { return nil }
        var result: [String: Int] = [:]
        for key in keys {
            guard let value = int(dict[key]) else { return nil }
            result[key] = value
        }
        return result
    }

    /// Liest eine Liste solcher Dictionaries; ungültige Einträge entfallen.
    static func intDicts(_ raw: Any?, keys: [String]) -> [[String: Int]] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { intDict($0, keys: keys) }
    }

    static let frameKeys = ["x", "y", "w", "h"]

    /// JSONSerialization liefert Bool und Zahl gleichermaßen als NSNumber;
    /// nur CFBoolean kennzeichnet einen echten Wahrheitswert.
    private static func isBool(_ value: Any) -> Bool {
        guard let n = value as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }
}
