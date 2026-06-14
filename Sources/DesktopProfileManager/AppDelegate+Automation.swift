import AppKit
import ApplicationServices

/// Globale Kurzbefehle (⌘⌃1–9) und automatisches Umschalten nach Zeit/WLAN.
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
                    self.doRestore(name, markActive: true)
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
        autoSwitchTick()
    }

    func stopAutoSwitch() {
        autoSwitchTimer?.invalidate()
        autoSwitchTimer = nil
    }

    /// Prüft, ob die aktuelle Uhrzeit im Bereich 'HH:MM-HH:MM' liegt.
    private func timeInRange(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 2 else { return false }
        func minutes(_ s: Substring) -> Int? {
            let hm = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]) else { return nil }
            return h * 60 + m
        }
        guard let start = minutes(parts[0]), let end = minutes(parts[1]) else { return false }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let cur = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        if start <= end { return start <= cur && cur < end }
        return cur >= start || cur < end // über Mitternacht
    }

    private func autoSwitchTick() {
        let rules = config.get("auto_switch_rules", [[String: Any]]())
        let profiles = Profiles.list()
        let wifiMap = profiles.filter { !$0.wifiSSID.isEmpty }.map { (name: $0.name, ssid: $0.wifiSSID) }
        if rules.isEmpty && wifiMap.isEmpty { return }

        var ssid: String?
        var target: String?

        // 1. Zeitregeln (Vorrang)
        for rule in rules where (rule["type"] as? String) == "time" {
            if let profile = rule["profile"] as? String,
               timeInRange(rule["value"] as? String ?? "") {
                target = profile
                break
            }
        }

        // 2. WLAN-Zuordnung der Profile
        if target == nil, !wifiMap.isEmpty {
            ssid = WiFi.currentSSID() ?? ""
            if let ssid = ssid, !ssid.isEmpty {
                target = wifiMap.first { $0.ssid == ssid }?.name
            }
        }

        // 3. Ältere WLAN-Regeln (Abwärtskompatibilität)
        if target == nil {
            for rule in rules where (rule["type"] as? String) == "wifi" {
                guard let profile = rule["profile"] as? String else { continue }
                if ssid == nil { ssid = WiFi.currentSSID() ?? "" }
                if let ssid = ssid, !ssid.isEmpty, ssid == rule["value"] as? String {
                    target = profile
                    break
                }
            }
        }

        if let target = target, target != lastAutoSwitch,
           let path = Profiles.profilePath(target), FileManager.default.fileExists(atPath: path.path) {
            lastAutoSwitch = target
            doRestore(target, includeApps: false, markActive: true)
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
                          L("Profile werden je nach Zeit/WLAN automatisch gewechselt.",
                            "Profiles are switched automatically based on time/Wi-Fi."))
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
