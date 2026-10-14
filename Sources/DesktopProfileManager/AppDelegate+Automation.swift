import AppKit
import ApplicationServices

/// Globale Kurzbefehle (⌘⌃1–9) und automatisches Umschalten nach Zeit/Netzwerk.
extension AppDelegate {

    // MARK: - Hotkey-Helfer

    func currentHotkeySymbol() -> String {
        let key = config.get("hotkey_modifier", "cmd_ctrl")
        return AppDelegate.hotkeyModifiers.first { $0.key == key }?.symbol ?? "⌘⌃"
    }

    /// Prüft, ob die App die Bedienungshilfen-Berechtigung besitzt.
    /// Globale Tastatur-Monitore funktionieren nur mit dieser Freigabe.
    /// - Parameter prompt: Wenn true, zeigt macOS den Systemdialog zum Erteilen an.
    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Geforderte Modifier-Maske gemäß Konfiguration.
    private func hotkeyFlags() -> NSEvent.ModifierFlags {
        switch config.get("hotkey_modifier", "cmd_ctrl") {
        case "ctrl": return [.control]
        case "opt_cmd": return [.option, .command]
        case "ctrl_shift": return [.control, .shift]
        default: return [.command, .control]
        }
    }

    // Tastencodes der Ziffern 1–9 → Index 0–8
    private static let digitKeycodes: [UInt16: Int] = [
        18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8,
    ]

    func startHotkeys() {
        stopHotkeys()
        let allMods: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let want = self.hotkeyFlags()
            if event.modifierFlags.intersection(allMods) != want { return }
            guard let idx = AppDelegate.digitKeycodes[event.keyCode] else { return }
            let profiles = Profiles.list()
            if idx < profiles.count {
                let name = profiles[idx].name
                DispatchQueue.main.async {
                    self.doRestore(name, trigger: .manual, markActive: true)
                }
            }
        }
    }

    func stopHotkeys() {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
    }

    @objc func onToggleHotkeys() {
        let enabled = !config.get("hotkeys_enabled", false)
        config.set("hotkeys_enabled", enabled)
        config.save()
        if enabled {
            startHotkeys()
            let sym = currentHotkeySymbol()
            // Ohne Bedienungshilfen-Berechtigung empfängt der globale Monitor
            // keine Tastenanschläge. Nutzer informieren und Systemdialog zeigen.
            if !hasAccessibilityPermission(prompt: true) {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = L("Berechtigung erforderlich",
                                      "Permission required")
                alert.informativeText = L(
                    "Damit die Kurzbefehle \(sym)1–9 systemweit funktionieren, benötigt „\(Paths.appName)“ die Bedienungshilfen-Berechtigung.\n\nÖffne „Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen“, aktiviere dort „\(Paths.appName)“ und schalte die Kurzbefehle anschließend einmal aus und wieder ein.",
                    "For the shortcuts \(sym)1–9 to work system-wide, “\(Paths.appName)” needs the Accessibility permission.\n\nOpen “System Settings › Privacy & Security › Accessibility”, enable “\(Paths.appName)” there, then turn the shortcuts off and on again.")
                alert.addButton(withTitle: L("Systemeinstellungen öffnen",
                                             "Open System Settings"))
                alert.addButton(withTitle: L("Später", "Later"))
                let resp = alert.runModal()
                NSApp.setActivationPolicy(.accessory)
                if resp == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                Notifier.show(L("Kurzbefehle aktiviert", "Shortcuts enabled"),
                              L("\(sym)1 bis \(sym)9 stellen die ersten 9 Profile wieder her.",
                                "\(sym)1 to \(sym)9 restore the first 9 profiles."))
            }
        } else {
            stopHotkeys()
            Notifier.show(L("Kurzbefehle deaktiviert", "Shortcuts disabled"), "")
        }
        buildMenu()
    }

    @objc func onSetHotkeyModifier(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        config.set("hotkey_modifier", key)
        config.save()
        if config.get("hotkeys_enabled", false) { startHotkeys() }
        buildMenu()
    }

    // MARK: - Auto-Umschalten

    func startAutoSwitch() {
        stopAutoSwitch()
        autoSwitchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.autoSwitchTick()
        }
        WiFi.requestPermissionIfNeeded()
        autoSwitchTick()
    }

    func stopAutoSwitch() {
        autoSwitchTimer?.invalidate()
        autoSwitchTimer = nil
    }

    /// Prüft, ob `nowMinutes` (Minuten seit Mitternacht) im Bereich
    /// 'HH:MM-HH:MM' liegt. Bereiche über Mitternacht sind erlaubt.
    static func timeInRange(_ value: String, nowMinutes: Int) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 2 else { return false }
        func minutes(_ s: Substring) -> Int? {
            let hm = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]),
                  (0...23).contains(h), (0...59).contains(m) else { return nil }
            return h * 60 + m
        }
        guard let start = minutes(parts[0]), let end = minutes(parts[1]) else { return false }
        if start <= end { return start <= nowMinutes && nowMinutes < end }
        return nowMinutes >= start || nowMinutes < end
    }

    static func timeRuleTarget(_ rules: [[String: Any]], nowMinutes: Int) -> String? {
        for rule in rules where (rule["type"] as? String) == "time" {
            if let profile = rule["profile"] as? String,
               timeInRange(rule["value"] as? String ?? "", nowMinutes: nowMinutes) {
                return profile
            }
        }
        return nil
    }

    /// Ermittelt das Profil zur aktuellen Netzwerkverbindung. Ist ein Kabel
    /// verbunden, gewinnt eine Kabel-Zuordnung (erst „Kabel“, dann „Beides“)
    /// vor dem WLAN – auch wenn das WLAN gleichzeitig verbunden ist. Danach
    /// folgen WLAN-Zuordnungen („WLAN“, dann „Beides“) und ältere WLAN-Regeln.
    static func networkTarget(ssid: String?, ethernetConnected: Bool,
                              profiles: [NetworkAssignment], rules: [[String: Any]]) -> String? {
        if ethernetConnected {
            if let match = profiles.first(where: { $0.mode == .ethernet }) { return match.name }
            if let match = profiles.first(where: { $0.mode == .both }) { return match.name }
        }
        guard let ssid, !ssid.isEmpty else { return nil }
        if let match = profiles.first(where: { $0.mode == .wifi && $0.ssid == ssid }) { return match.name }
        if let match = profiles.first(where: { $0.mode == .both && $0.ssid == ssid }) { return match.name }
        for rule in rules where (rule["type"] as? String) == "wifi" {
            if let profile = rule["profile"] as? String, ssid == rule["value"] as? String {
                return profile
            }
        }
        return nil
    }

    private func autoSwitchTick() {
        guard !isAutoSwitchCheckRunning else { return }
        let rules = config.get("auto_switch_rules", [[String: Any]]())
        let networkProfiles = Profiles.list().filter { $0.networkMode != .none }
            .map { NetworkAssignment(name: $0.name, mode: $0.networkMode, ssid: $0.wifiSSID) }
        let hasWiFiRules = rules.contains { ($0["type"] as? String) == "wifi" }
        let needsWiFi = hasWiFiRules || networkProfiles.contains { $0.mode.usesWiFi }
        let needsEthernet = networkProfiles.contains { $0.mode.usesEthernet }
        let needsNetwork = needsWiFi || needsEthernet
        if rules.isEmpty && !needsNetwork { return }

        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        // Zeitregeln haben Vorrang.
        if let target = Self.timeRuleTarget(rules, nowMinutes: nowMinutes) {
            applyAutoSwitch(target)
            return
        }
        guard needsNetwork else {
            applyAutoSwitch(nil)
            return
        }
        // Die Netzwerkabfrage startet ggf. Hilfsprozesse und darf das Menü nicht blockieren.
        isAutoSwitchCheckRunning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ssid = needsWiFi ? WiFi.currentSSID() : nil
            let wired = needsEthernet && Ethernet.isConnected()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAutoSwitchCheckRunning = false
                guard self.config.get("auto_switch_enabled", false) else { return }
                self.applyAutoSwitch(Self.networkTarget(ssid: ssid, ethernetConnected: wired,
                                                        profiles: networkProfiles, rules: rules))
            }
        }
    }

    // MARK: - WLAN passend schalten

    static let wifiOffByAppKey = "wifi_off_by_app"

    /// Übernimmt das Ergebnis der WLAN-Schaltung eines Profils und liefert ggf.
    /// einen Hinweis für die Mitteilung.
    func handleWiFiSwitch(_ outcome: WiFiSwitch.Outcome) -> String? {
        switch outcome {
        case .unchanged:
            return nil
        case .wifiOn:
            setWiFiOffByApp(false)
            return nil
        case .wifiOff:
            setWiFiOffByApp(true)
            return nil
        case .keptNoCable:
            setWiFiOffByApp(false)
            return L("Kein Netzwerkkabel verbunden – WLAN bleibt eingeschaltet.",
                     "No network cable connected – Wi-Fi stays on.")
        case .failed:
            return L("WLAN konnte nicht umgeschaltet werden.", "Wi-Fi could not be switched.")
        }
    }

    private func setWiFiOffByApp(_ value: Bool) {
        if config.get(Self.wifiOffByAppKey, false) != value {
            config.set(Self.wifiOffByAppKey, value)
            config.save()
        }
        if value { startWiFiFailoverWatch() } else { stopWiFiFailoverWatch() }
    }

    /// Solange die App das WLAN ausgeschaltet hat, wird das Kabel überwacht.
    /// Bleibt es mehrere Prüfungen lang getrennt, schaltet die App das WLAN
    /// wieder ein (kurze Aussetzer, z. B. nach dem Aufwachen, zählen nicht).
    func startWiFiFailoverWatch() {
        guard wifiFailoverTimer == nil else { return }
        wifiFailoverMissedChecks = 0
        wifiFailoverTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.wifiFailoverTick()
        }
        wifiFailoverTick()
    }

    func stopWiFiFailoverWatch() {
        wifiFailoverTimer?.invalidate()
        wifiFailoverTimer = nil
    }

    private func wifiFailoverTick() {
        guard !isWiFiFailoverCheckRunning else { return }
        isWiFiFailoverCheckRunning = true
        let missed = wifiFailoverMissedChecks
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let wired = Ethernet.isConnected()
            let action = WiFiSwitch.failoverAction(wifiPoweredOn: WiFi.isPoweredOn, ethernetConnected: wired,
                                                   previousMissedChecks: missed)
            let restored = action == .turnOnWiFi && WiFi.setPower(true)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isWiFiFailoverCheckRunning = false
                self.wifiFailoverMissedChecks = wired ? 0 : missed + 1
                switch action {
                case .keepWatching:
                    return
                case .stopWatching:
                    self.setWiFiOffByApp(false)
                case .turnOnWiFi:
                    // Fehlgeschlagen: beim nächsten Durchlauf erneut versuchen.
                    guard restored else { return }
                    self.setWiFiOffByApp(false)
                    Notifier.show(L("WLAN wieder eingeschaltet", "Wi-Fi turned back on"),
                                  L("Das Netzwerkkabel wurde getrennt.", "The network cable was disconnected."))
                    // Nach der WLAN-Anmeldung passendes Profil wählen.
                    if self.config.get("auto_switch_enabled", false) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                            self?.autoSwitchTick()
                        }
                    }
                }
            }
        }
    }

    /// Ohne passende Regel wird der Merker zurückgesetzt, damit ein späteres
    /// erneutes Eintreten (z. B. Rückkehr ins Heim-WLAN) wieder umschaltet.
    private func applyAutoSwitch(_ target: String?) {
        guard let target, Profiles.exists(target) else {
            lastAutoSwitch = nil
            return
        }
        guard target != lastAutoSwitch else { return }
        // Nur merken, wenn die Wiederherstellung tatsächlich angenommen wurde;
        // sonst wird es beim nächsten Durchlauf erneut versucht.
        if doRestore(target, trigger: .autoSwitch, markActive: true) {
            lastAutoSwitch = target
        }
    }

    @objc func onToggleAutoSwitch() {
        let enabled = !config.get("auto_switch_enabled", false)
        config.set("auto_switch_enabled", enabled)
        config.save()
        if enabled {
            lastAutoSwitch = nil
            startAutoSwitch()
            Notifier.show(L("Auto-Umschalten aktiviert", "Auto switch enabled"),
                          L("Profile werden je nach Zeit/Netzwerk automatisch gewechselt.",
                            "Profiles are switched automatically based on time/network."))
        } else {
            stopAutoSwitch()
            Notifier.show(L("Auto-Umschalten deaktiviert", "Auto switch disabled"), "")
        }
        buildMenu()
    }

    @objc func onAddTimeRule() {
        guard let value = promptText(
            title: L("Zeitregel: Profil nach Uhrzeit laden", "Time rule: load profile by time of day"),
            message: L("In welchem Zeitfenster soll ein Profil automatisch geladen werden?\nFormat HH:MM-HH:MM (z. B. 09:00-17:00):",
                       "During which time window should a profile load automatically?\nFormat HH:MM-HH:MM (e.g. 09:00-17:00):"),
            defaultText: "09:00-17:00"),
            !value.isEmpty else { return }

        // Format prüfen
        let parts = value.split(separator: "-")
        var valid = parts.count == 2
        if valid {
            for part in parts {
                let hm = part.trimmingCharacters(in: .whitespaces).split(separator: ":")
                guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]),
                      (0..<24).contains(h), (0..<60).contains(m) else { valid = false; break }
            }
        }
        if !valid {
            Notifier.show(L("Ungültig", "Invalid"),
                          L("Format HH:MM-HH:MM erwartet.", "Expected format HH:MM-HH:MM."))
            return
        }
        guard let profile = pickProfileName() else { return }
        var rules = config.get("auto_switch_rules", [[String: Any]]())
        rules.append(["type": "time", "value": value, "profile": profile])
        config.set("auto_switch_rules", rules)
        config.save()
        buildMenu()
    }

    @objc func onDeleteAutoSwitchRule(_ sender: NSMenuItem) {
        guard let idx = sender.representedObject as? Int else { return }
        var rules = config.get("auto_switch_rules", [[String: Any]]())
        if idx >= 0 && idx < rules.count {
            rules.remove(at: idx)
            config.set("auto_switch_rules", rules)
            config.save()
        }
        buildMenu()
    }

    // MARK: - Kleine Dialoge

    /// Einfacher Texteingabe-Dialog. Gibt den Text oder nil zurück.
    private func promptText(title: String, message: String, defaultText: String) -> String? {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(.accessory) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("OK", "OK"))
        alert.addButton(withTitle: L("Abbrechen", "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultText
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// Profil per Dropdown auswählen. Gibt den Namen oder nil zurück.
    private func pickProfileName() -> String? {
        let profiles = Profiles.list().map { $0.name }
        if profiles.isEmpty {
            Notifier.show(L("Keine Profile", "No profiles"),
                          L("Bitte zuerst ein Profil anlegen.", "Please create a profile first."))
            return nil
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(.accessory) }
        let alert = NSAlert()
        alert.messageText = L("Profil wählen", "Choose profile")
        alert.informativeText = L("Welches Profil soll dieser Regel zugeordnet werden?",
                                  "Which profile should be assigned to this rule?")
        alert.addButton(withTitle: L("OK", "OK"))
        alert.addButton(withTitle: L("Abbrechen", "Cancel"))
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        popup.addItems(withTitles: profiles)
        alert.accessoryView = popup
        if alert.runModal() == .alertFirstButtonReturn {
            return popup.titleOfSelectedItem
        }
        return nil
    }
}
