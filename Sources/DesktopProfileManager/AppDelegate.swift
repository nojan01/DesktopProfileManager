import AppKit
import Foundation

/// Menüleisten-App: NSStatusItem mit Profil-Schnellauswahl und Einstellungen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let config = Config()
    private var statusItem: NSStatusItem!
    var activeProfile: String?

    // Fenster-Referenzen (verhindert vorzeitige Freigabe)
    var widget: ProfileWidget?
    var setupWindow: ProfileSetupWindow?
    var visibilityWindow: VisibilityWindow?
    var appSelectionWindow: AppSelectionWindow?

    private var autoRestoreTimer: Timer?

    private let githubRepo = "nojan01/IconGuard"
    private let launchDelayOptions: [Double] = [0, 0.5, 1, 1.5, 2, 3, 5]

    // Globale Kurzbefehle
    var hotkeyMonitor: Any?
    // Automatisches Umschalten (Zeit/WLAN)
    var autoSwitchTimer: Timer?
    var lastAutoSwitch: String?

    // Wird beim App-Beenden gesetzt, damit das Schließen des Widget-Fensters
    // die gespeicherte Sichtbarkeit nicht zurücksetzt.
    private var isTerminating = false

    static let hotkeyModifiers: [(key: String, symbol: String)] = [
        ("cmd_ctrl", "⌘⌃"), ("ctrl", "⌃"), ("opt_cmd", "⌥⌘"), ("ctrl_shift", "⌃⇧"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        Localization.resolve(config.get("language", "system"))
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Merkt sich die vom Nutzer per ⌘-Ziehen gewählte Position in der Menüleiste.
        statusItem.autosaveName = "DesktopProfileManagerStatusItem"
        if let button = statusItem.button {
            if let image = loadStatusIcon() {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                button.title = "🗂"
            }
        }
        buildMenu()

        if config.get("widget_visible", false) {
            showWidget()
        }
        if config.get("auto_restore_enabled", false) {
            startAutoRestore()
        }
        if config.get("restore_on_login", true) {
            restoreOnLogin()
        }

        if config.get("hotkeys_enabled", false) {
            startHotkeys()
        }
        if config.get("auto_switch_enabled", false) {
            startAutoSwitch()
        }

        // Nach dem Aufwachen aus dem Ruhezustand wiederherstellen
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onSystemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Sucht das Menüleisten-Icon (icon.png) im Bundle bzw. neben der Binary.
    private func loadStatusIcon() -> NSImage? {
        var candidates: [String] = []
        if let res = Bundle.main.resourcePath {
            candidates.append(res + "/icon.png")
        }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("icon.png").path)
        candidates.append(exeDir.appendingPathComponent("../Resources/icon.png").path)
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let image = NSImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }

    @objc private func onSystemDidWake() {
        guard config.get("restore_on_wake", true) else { return }
        let profile = config.get("auto_restore_profile", "")
        if !profile.isEmpty, Profiles.profilePath(profile).map({ FileManager.default.fileExists(atPath: $0.path) }) == true {
            let iconsOnly = config.get("auto_restore_icons_only", false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.doRestore(profile, notify: false, iconsOnly: iconsOnly)
            }
        }
    }

    // MARK: - Menüaufbau

    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let profiles = Profiles.list()

        // Schnellauswahl
        if !profiles.isEmpty {
            let hotkeysOn = config.get("hotkeys_enabled", false)
            let hkSymbol = currentHotkeySymbol()
            for (i, p) in profiles.enumerated() {
                let prefix = p.emoji.isEmpty ? "" : p.emoji + " "
                var title = "▶︎ \(prefix)\(p.name)"
                if hotkeysOn && i < 9 {
                    title += "   \(hkSymbol)\(i + 1)"
                }
                let item = NSMenuItem(title: title, action: #selector(onRestore(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p.name
                if p.name == activeProfile {
                    item.attributedTitle = NSAttributedString(
                        string: title,
                        attributes: [.foregroundColor: NSColor.controlAccentColor])
                }
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }



        // Einstellungen-Untermenü
        let settings = NSMenu()
        let settingsItem = NSMenuItem(title: "⚙️ " + L("Einstellungen", "Settings"), action: nil, keyEquivalent: "")
        settingsItem.submenu = settings

        // Speichern
        let saveMenu = NSMenu()
        let saveItem = NSMenuItem(title: "💾 " + L("Profil speichern …", "Save profile …"), action: nil, keyEquivalent: "")
        saveItem.submenu = saveMenu
        let saveNew = NSMenuItem(title: L("Neues Profil …", "New profile …"), action: #selector(onSaveNew), keyEquivalent: "")
        saveNew.target = self
        saveMenu.addItem(saveNew)
        saveMenu.addItem(.separator())
        for p in profiles {
            let prefix = p.emoji.isEmpty ? "" : p.emoji + " "
            let item = NSMenuItem(title: L("Überschreiben: ", "Overwrite: ") + prefix + p.name,
                                  action: #selector(onSaveExisting(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.name
            saveMenu.addItem(item)
        }
        settings.addItem(saveItem)

        // Wiederherstellen
        let restoreMenu = NSMenu()
        let restoreItem = NSMenuItem(title: "🔄 " + L("Profil wiederherstellen", "Restore profile"), action: nil, keyEquivalent: "")
        restoreItem.submenu = restoreMenu
        if profiles.isEmpty {
            restoreMenu.addItem(NSMenuItem(title: L("(keine Profile vorhanden)", "(no profiles available)"), action: nil, keyEquivalent: ""))
        } else {
            for p in profiles {
                let prefix = p.emoji.isEmpty ? "" : p.emoji + " "
                let item = NSMenuItem(title: "\(prefix)\(p.name)", action: #selector(onRestore(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p.name
                restoreMenu.addItem(item)
            }
        }
        settings.addItem(restoreItem)
        settings.addItem(.separator())

        // Icons ein-/ausblenden
        let visItem = NSMenuItem(title: "👁 " + L("Desktop-Icons ein-/ausblenden …", "Show/hide desktop icons …"),
                                 action: #selector(onOpenVisibility), keyEquivalent: "")
        visItem.target = self
        settings.addItem(visItem)

        // Apps für Profile auswählen
        let appSelectItem = NSMenuItem(title: "🚀 " + L("Apps für Profile auswählen …", "Select apps for profiles …"),
                                       action: #selector(onOpenAppSelection), keyEquivalent: "")
        appSelectItem.target = self
        settings.addItem(appSelectItem)

        // Widget
        let widgetItem = NSMenuItem(title: "🧩 " + L("Profil-Widget anzeigen", "Show profile widget"),
                                    action: #selector(onToggleWidget), keyEquivalent: "")
        widgetItem.target = self
        widgetItem.state = (widget != nil) ? .on : .off
        settings.addItem(widgetItem)

        let compactItem = NSMenuItem(title: "🔳 " + L("Widget kompakt (nur Emojis)", "Compact widget (emojis only)"),
                                     action: #selector(onToggleWidgetCompact), keyEquivalent: "")
        compactItem.target = self
        compactItem.state = config.get("widget_compact", false) ? .on : .off
        settings.addItem(compactItem)
        settings.addItem(.separator())

        // Auto-Restore
        let autoItem = NSMenuItem(title: "⏱ " + L("Auto-Wiederherstellen", "Auto restore"),
                                  action: #selector(onToggleAutoRestore), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = config.get("auto_restore_enabled", false) ? .on : .off
        settings.addItem(autoItem)

        // Nur Desktop-Symbole wiederherstellen (kein Hintergrund/Apps/Systemzustand)
        let iconsOnlyItem = NSMenuItem(title: "🧩 " + L("Auto-Restore nur Desktop-Symbole",
                                                       "Auto restore desktop icons only"),
                                       action: #selector(onToggleAutoRestoreIconsOnly), keyEquivalent: "")
        iconsOnlyItem.target = self
        iconsOnlyItem.state = config.get("auto_restore_icons_only", false) ? .on : .off
        settings.addItem(iconsOnlyItem)

        // Intervall
        let intervalMenu = NSMenu()
        let intervalItem = NSMenuItem(title: "⏰ " + L("Intervall", "Interval"), action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        let currentInterval = config.get("auto_restore_interval_minutes", 30)
        for mins in intervalOptions {
            let label: String
            if mins < 60 { label = L("\(mins) Minuten", "\(mins) minutes") }
            else { let h = mins / 60; label = L("\(h) Stunde\(mins > 60 ? "n" : "")", "\(h) hour\(mins > 60 ? "s" : "")") }
            let item = NSMenuItem(title: label, action: #selector(onSetInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mins
            item.state = (mins == currentInterval) ? .on : .off
            intervalMenu.addItem(item)
        }
        settings.addItem(intervalItem)

        // Auto-Restore-Profil
        let autoProfileMenu = NSMenu()
        let autoProfileItem = NSMenuItem(title: "📋 " + L("Auto-Restore-Profil", "Auto-restore profile"), action: nil, keyEquivalent: "")
        autoProfileItem.submenu = autoProfileMenu
        let currentAutoProfile = config.get("auto_restore_profile", "")
        if profiles.isEmpty {
            autoProfileMenu.addItem(NSMenuItem(title: L("(erst ein Profil speichern)", "(save a profile first)"), action: nil, keyEquivalent: ""))
        } else {
            // „Kein“ – Auto-Restore-Profil abwählen (schaltet automatische Wiederherstellung aus)
            let noneItem = NSMenuItem(title: L("(Kein)", "(None)"), action: #selector(onSetAutoProfile(_:)), keyEquivalent: "")
            noneItem.target = self
            noneItem.representedObject = ""
            noneItem.state = currentAutoProfile.isEmpty ? .on : .off
            autoProfileMenu.addItem(noneItem)
            autoProfileMenu.addItem(.separator())
            for p in profiles {
                let item = NSMenuItem(title: p.name, action: #selector(onSetAutoProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p.name
                item.state = (p.name == currentAutoProfile) ? .on : .off
                autoProfileMenu.addItem(item)
            }
        }
        settings.addItem(autoProfileItem)
        settings.addItem(.separator())

        // Bearbeiten
        let editMenu = NSMenu()
        let editItem = NSMenuItem(title: "✏️ " + L("Profil bearbeiten", "Edit profile"), action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        if profiles.isEmpty {
            editMenu.addItem(NSMenuItem(title: L("(keine Profile)", "(no profiles)"), action: nil, keyEquivalent: ""))
        } else {
            for p in profiles {
                let item = NSMenuItem(title: p.name, action: #selector(onEditProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p.name
                editMenu.addItem(item)
            }
        }
        settings.addItem(editItem)

        // Löschen
        let deleteMenu = NSMenu()
        let deleteItem = NSMenuItem(title: "🗑 " + L("Profil löschen", "Delete profile"), action: nil, keyEquivalent: "")
        deleteItem.submenu = deleteMenu
        if profiles.isEmpty {
            deleteMenu.addItem(NSMenuItem(title: L("(keine Profile)", "(no profiles)"), action: nil, keyEquivalent: ""))
        } else {
            for p in profiles {
                let item = NSMenuItem(title: p.name, action: #selector(onDeleteProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p.name
                deleteMenu.addItem(item)
            }
        }
        settings.addItem(deleteItem)

        // Export / Import
        let exportMenu = NSMenu()
        let exportItem = NSMenuItem(title: "📤 " + L("Profil exportieren", "Export profile"), action: nil, keyEquivalent: "")
        exportItem.submenu = exportMenu
        if profiles.isEmpty {
            exportMenu.addItem(NSMenuItem(title: L("(keine Profile)", "(no profiles)"), action: nil, keyEquivalent: ""))
        } else {
            for p in profiles {
                let item = NSMenuItem(title: p.name, action: #selector(onExportProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p.name
                exportMenu.addItem(item)
            }
        }
        settings.addItem(exportItem)

        let importItem = NSMenuItem(title: "📥 " + L("Profil importieren …", "Import profile …"),
                                    action: #selector(onImportProfile), keyEquivalent: "")
        importItem.target = self
        settings.addItem(importItem)
        settings.addItem(.separator())

        // Wiederherstellungs-Optionen (Schalter)
        settings.addItem(toggleItem("🔁", "Beim Login Icons wiederherstellen", "Restore icons at login", "restore_on_login", true))
        settings.addItem(toggleItem("😴", "Nach Ruhemodus wiederherstellen", "Restore after sleep", "restore_on_wake", true))
        settings.addItem(toggleItem("🖼", "Hintergrund mit wiederherstellen", "Restore wallpaper too", "restore_wallpaper", true))
        settings.addItem(toggleItem("🚀", "Apps beim Wiederherstellen starten", "Launch apps on restore", "restore_apps", true))
        settings.addItem(toggleItem("🙈", "Andere Apps beim Wechsel ausblenden", "Hide other apps when switching", "hide_other_apps", false))
        settings.addItem(toggleItem("⛔", "Andere Apps beim Wechsel beenden", "Quit other apps when switching", "quit_other_apps", false))

        // App-Startverzögerung
        let delayMenu = NSMenu()
        let delayItem = NSMenuItem(title: "⏳ " + L("App-Startverzögerung", "App launch delay"), action: nil, keyEquivalent: "")
        delayItem.submenu = delayMenu
        let currentDelay = config.get("app_launch_delay", 1.5)
        for secs in launchDelayOptions {
            let label: String
            if secs == 0 { label = L("Keine", "None") }
            else { let txt = secs.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(secs)) : String(secs)
                   label = L("\(txt) Sek.", "\(txt) sec") }
            let item = NSMenuItem(title: label, action: #selector(onSetLaunchDelay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = secs
            item.state = (abs(secs - currentDelay) < 0.01) ? .on : .off
            delayMenu.addItem(item)
        }
        settings.addItem(delayItem)

        // Autostart
        let autostartItem = NSMenuItem(title: "🔓 " + L("Beim Anmelden starten", "Start at login"),
                                       action: #selector(onToggleAutostart), keyEquivalent: "")
        autostartItem.target = self
        autostartItem.state = LaunchAgentManager.isEnabled() ? .on : .off
        settings.addItem(autostartItem)
        settings.addItem(.separator())

        // Globale Kurzbefehle
        let hkSymbol = currentHotkeySymbol()
        let hotkeysItem = NSMenuItem(title: "⌨️ " + L("Kurzbefehle \(hkSymbol)1–9", "Shortcuts \(hkSymbol)1–9"),
                                     action: #selector(onToggleHotkeys), keyEquivalent: "")
        hotkeysItem.target = self
        hotkeysItem.state = config.get("hotkeys_enabled", false) ? .on : .off
        settings.addItem(hotkeysItem)

        // Tastenkombination wählen
        let hkModMenu = NSMenu()
        let hkModItem = NSMenuItem(title: "⌨️ " + L("Tastenkombination", "Key combination"), action: nil, keyEquivalent: "")
        hkModItem.submenu = hkModMenu
        let currentMod = config.get("hotkey_modifier", "cmd_ctrl")
        for (key, symbol) in AppDelegate.hotkeyModifiers {
            let item = NSMenuItem(title: "\(symbol)" + L(" + 1–9", " + 1–9"),
                                  action: #selector(onSetHotkeyModifier(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = (key == currentMod) ? .on : .off
            hkModMenu.addItem(item)
        }
        settings.addItem(hkModItem)

        // Automatisches Umschalten (Zeit/WLAN)
        let autoSwitchMenu = NSMenu()
        let autoSwitchItem = NSMenuItem(title: "🕓 " + L("Auto-Umschalten (Zeit/WLAN)", "Auto switch (time/Wi-Fi)"), action: nil, keyEquivalent: "")
        autoSwitchItem.submenu = autoSwitchMenu

        let asToggle = NSMenuItem(title: L("Aktiviert", "Enabled"), action: #selector(onToggleAutoSwitch), keyEquivalent: "")
        asToggle.target = self
        asToggle.state = config.get("auto_switch_enabled", false) ? .on : .off
        autoSwitchMenu.addItem(asToggle)
        autoSwitchMenu.addItem(.separator())

        let addTimeRule = NSMenuItem(title: "➕ " + L("Zeitregel hinzufügen … (Profil nach Uhrzeit)", "Add time rule … (profile by time)"),
                                     action: #selector(onAddTimeRule), keyEquivalent: "")
        addTimeRule.target = self
        autoSwitchMenu.addItem(addTimeRule)

        let wifiHint = NSMenuItem(title: "📶 " + L("WLAN: im Profil bearbeiten festlegen", "Wi-Fi: set in 'Edit profile'"), action: nil, keyEquivalent: "")
        autoSwitchMenu.addItem(wifiHint)

        // Aktuelle WLAN-Zuordnungen anzeigen
        let wifiAssignments = profiles.filter { !$0.wifiSSID.isEmpty }
        for p in wifiAssignments {
            autoSwitchMenu.addItem(NSMenuItem(title: "   📶 \(p.wifiSSID) → \(p.name)", action: nil, keyEquivalent: ""))
        }

        // Zeitregeln (und ältere WLAN-Regeln) auflisten – löschbar
        let rules = config.get("auto_switch_rules", [[String: Any]]())
        let hasRules = rules.contains { ($0["type"] as? String) == "time" || ($0["type"] as? String) == "wifi" }
        if hasRules {
            autoSwitchMenu.addItem(.separator())
            for (i, rule) in rules.enumerated() {
                let type = rule["type"] as? String ?? ""
                let value = rule["value"] as? String ?? ""
                let profile = rule["profile"] as? String ?? ""
                let icon = type == "time" ? "⏰" : "📶"
                guard type == "time" || type == "wifi" else { continue }
                let item = NSMenuItem(title: "\(icon) \(value) → \(profile)" + L("  (löschen)", "  (delete)"),
                                      action: #selector(onDeleteAutoSwitchRule(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = i
                autoSwitchMenu.addItem(item)
            }
        }
        settings.addItem(autoSwitchItem)
        settings.addItem(.separator())

        // Sprache
        let langMenu = NSMenu()
        let langItem = NSMenuItem(title: "🌐 " + L("Sprache", "Language"), action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        let currentLang = config.get("language", "system")
        for (code, label) in [("system", L("System", "System")), ("de", L("Deutsch", "German")), ("en", L("Englisch", "English"))] {
            let item = NSMenuItem(title: label, action: #selector(onSetLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = (code == currentLang) ? .on : .off
            langMenu.addItem(item)
        }
        settings.addItem(langItem)

        // Nach Updates suchen
        let updateItem = NSMenuItem(title: "⬆️ " + L("Nach Updates suchen …", "Check for updates …"),
                                    action: #selector(onCheckUpdate), keyEquivalent: "")
        updateItem.target = self
        settings.addItem(updateItem)
        settings.addItem(.separator())

        // Status
        let statusText: String
        let autoProf = config.get("auto_restore_profile", "")
        if config.get("auto_restore_enabled", false) && !autoProf.isEmpty {
            let iv = config.get("auto_restore_interval_minutes", 30)
            let ivText = iv < 60 ? L("alle \(iv) Min.", "every \(iv) min") : L("alle \(iv / 60) Std.", "every \(iv / 60) h")
            let scope = config.get("auto_restore_icons_only", false) ? L(" (nur Symbole)", " (icons only)") : ""
            statusText = L("Auto: '\(autoProf)' \(ivText)\(scope)", "Auto: '\(autoProf)' \(ivText)\(scope)")
        } else {
            statusText = L("Auto-Restore: Aus", "Auto restore: off")
        }
        settings.addItem(NSMenuItem(title: "ℹ️ \(statusText)", action: nil, keyEquivalent: ""))

        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let helpItem = NSMenuItem(title: L("Bedienungsanleitung", "User guide"),
                                  action: #selector(onHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)
        let aboutItem = NSMenuItem(title: L("Über \(Paths.appName)", "About \(Paths.appName)"),
                                   action: #selector(onAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let quitItem = NSMenuItem(title: L("Beenden", "Quit"), action: #selector(onQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        widget?.rebuild()
    }

    /// Erzeugt einen an einen Bool-Config-Schlüssel gebundenen Schalter-Menüpunkt.
    private func toggleItem(_ emoji: String, _ de: String, _ en: String, _ key: String, _ def: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: emoji + " " + L(de, en), action: #selector(onToggleConfig(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = key
        item.state = config.get(key, def) ? .on : .off
        return item
    }

    // MARK: - Callbacks

    @objc func onRestore(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        doRestore(name, markActive: true)
    }

    func doRestore(_ name: String, notify: Bool = true, includeApps: Bool? = nil, markActive: Bool = false, iconsOnly: Bool = false) {
        let incApps = includeApps ?? config.get("restore_apps", true)
        let incWallpaper = config.get("restore_wallpaper", true)
        let hideOthers = config.get("hide_other_apps", false)
        let quitOthers = config.get("quit_other_apps", false)
        let delay = config.get("app_launch_delay", 1.5)

        DispatchQueue.global().async {
            let r = Profiles.restore(name, includeWallpaper: incWallpaper, includeApps: incApps,
                                     hideOthers: hideOthers, quitOthers: quitOthers, launchDelay: delay,
                                     iconsOnly: iconsOnly)
            DispatchQueue.main.async {
                if let error = r.error {
                    if notify { Notifier.show(L("Fehler", "Error"), error) }
                    return
                }
                if markActive {
                    self.activeProfile = name
                    self.buildMenu()
                }
                var msg = L("\(r.success) Icons wiederhergestellt", "\(r.success) icons restored")
                if r.failed > 0 { msg += L(", \(r.failed) fehlgeschlagen", ", \(r.failed) failed") }
                if let w = r.warning { msg += "\n⚠️ " + w }
                if notify { Notifier.show(L("Profil '\(name)'", "Profile '\(name)'"), msg) }
            }
        }
    }

    @objc func onSaveNew() {
        openSetupWindow(editName: nil)
    }

    @objc func onSaveExisting(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var options = Profiles.SaveOptions()
        if let data = Profiles.load(name), let saved = data["settings"] as? [String: Any] {
            options.withPositions = saved["capture_positions"] as? Bool ?? true
            options.withHidden = saved["capture_hidden"] as? Bool ?? true
            options.withWallpaper = saved["capture_wallpaper"] as? Bool ?? true
            options.withApps = saved["capture_apps"] as? Bool ?? true
            options.withBrowserTabs = saved["capture_browser_tabs"] as? Bool ?? false
            options.includedApps = saved["included_apps"] as? [String]
            options.systemStateKeys = saved["system_state_keys"] as? [String] ?? []
            options.emoji = saved["emoji"] as? String ?? ""
            options.wifiSSID = saved["wifi_ssid"] as? String ?? ""
        }
        doSaveWithOptions(name, options: options, overwrite: true)
    }

    func doSaveWithOptions(_ name: String, options: Profiles.SaveOptions, overwrite: Bool = false) {
        let exclusions = config.get("app_exclusions", [String]())
        DispatchQueue.global().async {
            let r = Profiles.save(name, appExclusions: exclusions, options: options, overwrite: overwrite)
            DispatchQueue.main.async {
                if let error = r.error {
                    Notifier.show(L("Fehler", "Error"), error)
                } else {
                    Notifier.show(L("Profil '\(name)' gespeichert", "Profile '\(name)' saved"),
                                  L("\(r.count) Icons gesichert", "\(r.count) icons saved"))
                }
                self.buildMenu()
            }
        }
    }

    /// Speichert Änderungen aus dem Bearbeiten-Fenster, ohne den Desktop neu zu
    /// erfassen (gespeicherte Icon-Positionen bleiben erhalten).
    func doApplyEdit(oldName: String, newName: String, options: Profiles.SaveOptions) {
        DispatchQueue.global().async {
            let error = Profiles.applyEdit(oldName: oldName, newName: newName, options: options)
            DispatchQueue.main.async {
                if let error = error {
                    Notifier.show(L("Fehler", "Error"), error)
                } else {
                    // Verweise in der Konfiguration mitziehen.
                    if oldName != newName {
                        if self.config.get("auto_restore_profile", "") == oldName {
                            self.config.set("auto_restore_profile", newName)
                        }
                        var rules = self.config.get("auto_switch_rules", [[String: Any]]())
                        for index in rules.indices where rules[index]["profile"] as? String == oldName {
                            rules[index]["profile"] = newName
                        }
                        self.config.set("auto_switch_rules", rules)
                        self.config.save()
                    }
                    if self.activeProfile == oldName { self.activeProfile = newName }
                    Notifier.show(L("Profil '\(newName)' aktualisiert", "Profile '\(newName)' updated"), "")
                }
                self.buildMenu()
            }
        }
    }

    @objc func onEditProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        openSetupWindow(editName: name)
    }

    @objc func onDeleteProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.messageText = L("Profil '\(name)' löschen?", "Delete profile '\(name)'?")
        alert.informativeText = L("Dies kann nicht rückgängig gemacht werden.", "This cannot be undone.")
        alert.addButton(withTitle: L("Löschen", "Delete"))
        alert.addButton(withTitle: L("Abbrechen", "Cancel"))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        if response == .alertFirstButtonReturn {
            _ = Profiles.delete(name)
            if activeProfile == name { activeProfile = nil }
            buildMenu()
        }
    }

    @objc func onToggleAutoRestore() {
        let newVal = !config.get("auto_restore_enabled", false)
        config.set("auto_restore_enabled", newVal)
        config.save()
        if newVal { startAutoRestore() } else { stopAutoRestore() }
        buildMenu()
    }

    @objc func onToggleAutoRestoreIconsOnly() {
        let newVal = !config.get("auto_restore_icons_only", false)
        config.set("auto_restore_icons_only", newVal)
        config.save()
        buildMenu()
    }

    @objc func onSetInterval(_ sender: NSMenuItem) {
        guard let mins = sender.representedObject as? Int else { return }
        config.set("auto_restore_interval_minutes", mins)
        config.save()
        if config.get("auto_restore_enabled", false) { startAutoRestore() }
        buildMenu()
    }

    @objc func onSetAutoProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        config.set("auto_restore_profile", name)
        config.save()
        // „Kein“ gewählt → laufenden Auto-Restore-Timer stoppen
        if name.isEmpty { stopAutoRestore() }
        else if config.get("auto_restore_enabled", false) { startAutoRestore() }
        buildMenu()
    }

    @objc func onSetLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        config.set("language", code)
        config.save()
        Localization.resolve(code)
        buildMenu()
    }

    @objc func onToggleAutostart() {
        let error: String?
        if LaunchAgentManager.isEnabled() {
            error = LaunchAgentManager.disable()
        } else {
            error = LaunchAgentManager.enable()
        }
        if let error = error {
            Notifier.show(L("Autostart konnte nicht geändert werden", "Could not change start at login"), error)
        }
        buildMenu()
    }

    @objc func onToggleWidget() {
        if widget == nil {
            config.set("widget_visible", true)
            config.save()
            showWidget()
        } else {
            widget?.close()
        }
        buildMenu()
    }

    @objc func onToggleWidgetCompact() {
        config.set("widget_compact", !config.get("widget_compact", false))
        config.save()
        widget?.rebuild()
        buildMenu()
    }

    @objc func onOpenVisibility() {
        let window = VisibilityWindow(app: self)
        visibilityWindow = window
        window.show()
    }

    @objc func onOpenAppSelection() {
        let window = AppSelectionWindow(app: self)
        appSelectionWindow = window
        window.show()
    }

    @objc func onToggleConfig(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        let newVal = !config.get(key, false)

        // Warnung vor möglichem Datenverlust beim Aktivieren von "Andere Apps beenden"
        if key == "quit_other_apps" && newVal {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L("Achtung: Datenverlust möglich", "Warning: possible data loss")
            alert.informativeText = L(
                "Wenn andere Apps beim Profilwechsel beendet werden, gehen ungespeicherte Inhalte (z. B. offene Texte oder Dokumente) in diesen Apps verloren.\n\nMöchtest du diese Option wirklich aktivieren?",
                "If other apps are quit when switching profiles, any unsaved content (e.g. open texts or documents) in those apps will be lost.\n\nDo you really want to enable this option?")
            alert.addButton(withTitle: L("Aktivieren", "Enable"))
            alert.addButton(withTitle: L("Abbrechen", "Cancel"))
            let resp = alert.runModal()
            NSApp.setActivationPolicy(.accessory)
            if resp != .alertFirstButtonReturn {
                buildMenu()
                return
            }
        }

        config.set(key, newVal)
        // Beenden und Ausblenden schließen sich gegenseitig aus
        if newVal && key == "quit_other_apps" {
            config.set("hide_other_apps", false)
        } else if newVal && key == "hide_other_apps" {
            config.set("quit_other_apps", false)
        }
        config.save()
        buildMenu()
    }

    @objc func onSetLaunchDelay(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? Double else { return }
        config.set("app_launch_delay", secs)
        config.save()
        buildMenu()
    }

    @objc func onExportProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let src = Profiles.profilePath(name),
              FileManager.default.fileExists(atPath: src.path) else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = L("Profil exportieren", "Export profile")
        panel.nameFieldStringValue = "\(name).json"
        panel.allowedContentTypes = [.json]
        let response = panel.runModal()
        if response == .OK, let dest = panel.url {
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: src, to: dest)
                Notifier.show(L("Profil exportiert", "Profile exported"),
                              L("'\(name)' wurde gespeichert.", "'\(name)' was saved."))
            } catch {
                Notifier.show(L("Fehler", "Error"), error.localizedDescription)
            }
        }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func onImportProfile() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = L("Profil importieren", "Import profile")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        let response = panel.runModal()
        NSApp.setActivationPolicy(.accessory)
        guard response == .OK, let src = panel.url else { return }

        guard let data = try? Data(contentsOf: src),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["positions"] != nil else {
            Notifier.show(L("Fehler", "Error"),
                          L("Datei ist kein gültiges Profil.", "File is not a valid profile."))
            return
        }

        // Namen bei Konflikt durchnummerieren
        let rawBase = (obj["profile"] as? String) ?? src.deletingPathExtension().lastPathComponent
        guard let base = Profiles.importName(rawBase) else {
            Notifier.show(L("Fehler", "Error"),
                          L("Die Datei enthält keinen gültigen Profilnamen.",
                            "The file does not contain a valid profile name."))
            return
        }
        var name = base
        var counter = 2
        while let path = Profiles.profilePath(name), FileManager.default.fileExists(atPath: path.path) {
            name = "\(base) (\(counter))"
            counter += 1
        }
        obj["profile"] = name
        guard let dest = Profiles.profilePath(name) else { return }
        try? FileManager.default.createDirectory(at: Paths.profilesDir, withIntermediateDirectories: true)
        if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            try? out.write(to: dest, options: .atomic)
            Notifier.show(L("Profil importiert", "Profile imported"),
                          L("'\(name)' wurde hinzugefügt.", "'\(name)' was added."))
            buildMenu()
        }
    }

    @objc func onCheckUpdate() {
        UpdateManager.fetchLatest(repo: githubRepo) { result in
            DispatchQueue.main.async { self.showUpdateResult(result) }
        }
    }

    private func showUpdateResult(_ result: Result<UpdateManager.Release, Error>) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        guard case .success(let release) = result else {
            alert.messageText = L("Update-Prüfung fehlgeschlagen", "Update check failed")
            alert.informativeText = L("Die Update-Informationen konnten nicht abgerufen werden.",
                                      "Could not fetch update information.")
            alert.runModal()
            NSApp.setActivationPolicy(.accessory)
            return
        }

        if versionGreater(release.version, than: Paths.appVersion) {
            let canDownload = release.downloadURL != nil && release.assetName != nil
            alert.messageText = L("Update verfügbar", "Update available")
            alert.informativeText = canDownload
                ? L("Version v\(release.version) ist verfügbar (installiert: v\(Paths.appVersion)). Das DMG wird nach der Bestätigung in „Downloads“ gespeichert.",
                    "Version v\(release.version) is available (installed: v\(Paths.appVersion)). The DMG will be saved to Downloads after confirmation.")
                : L("Version v\(release.version) ist verfügbar (installiert: v\(Paths.appVersion)). Für dieses Release wurde keine DMG-Datei gefunden.",
                    "Version v\(release.version) is available (installed: v\(Paths.appVersion)). No DMG file was found for this release.")
            alert.addButton(withTitle: L(canDownload ? "DMG herunterladen" : "Releases öffnen",
                                         canDownload ? "Download DMG" : "Open releases"))
            alert.addButton(withTitle: L("Abbrechen", "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                if canDownload {
                    startUpdateDownload(release)
                } else if let url = URL(string: "https://github.com/\(githubRepo)/releases") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            alert.messageText = L("Keine Updates", "No updates")
            alert.informativeText = L("Du verwendest bereits die neueste Version (v\(Paths.appVersion)).",
                                      "You are already using the latest version (v\(Paths.appVersion)).")
            alert.runModal()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    private func startUpdateDownload(_ release: UpdateManager.Release) {
        Notifier.show(L("Update-Download gestartet", "Update download started"),
                      L("Das DMG wird in „Downloads“ gespeichert.", "The DMG is being saved to Downloads."))
        UpdateManager.downloadDMG(release) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let file):
                    Notifier.show(L("Update heruntergeladen", "Update downloaded"),
                                  L("Die DMG-Datei wurde in „Downloads“ gespeichert.",
                                    "The DMG file was saved to Downloads."))
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                case .failure:
                    Notifier.show(L("Update-Download fehlgeschlagen", "Update download failed"),
                                  L("Das DMG konnte nicht heruntergeladen werden. Bitte versuche es später erneut.",
                                    "The DMG could not be downloaded. Please try again later."))
                }
            }
        }
    }

    private func versionGreater(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    @objc func onHelp() {
        let lang = Localization.current == .en ? "en" : "de"
        let fileName = "help_\(lang)"

        // Hilfe-HTML im Bundle bzw. neben der Binary suchen
        var candidates: [String] = []
        if let res = Bundle.main.resourcePath {
            candidates.append(res + "/\(fileName).html")
        }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("\(fileName).html").path)
        candidates.append(exeDir.appendingPathComponent("../Resources/\(fileName).html").path)
        candidates.append(exeDir.appendingPathComponent("Resources/\(fileName).html").path)

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }

        // Fallback: kurze Schnellanleitung als Dialog
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Profil erstellen", "Create a profile")
        alert.informativeText = L(
            "1. Ordne deine Desktop-Icons wie gewünscht an.\n2. Einstellungen › Profil speichern › Neues Profil.\n3. Name, Emoji und Inhalte wählen.\n4. Profil über das Menü oder das Widget wiederherstellen.",
            "1. Arrange your desktop icons as desired.\n2. Settings › Save profile › New profile.\n3. Choose name, emoji and contents.\n4. Restore the profile via the menu or the widget.")
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func onAbout() {
        let alert = NSAlert()
        alert.messageText = L("Über Desktop Profile Manager", "About Desktop Profile Manager")
        alert.informativeText = L(
            """
            Desktop Profile Manager v\(Paths.appVersion) (Swift)

            Arbeitsumgebungs-Manager für macOS:
            • Desktop-Icon-Positionen speichern/wiederherstellen
            • Icons einzeln verstecken
            • Desktop-Hintergrund pro Profil
            • Apps inkl. Fensterposition/-größe starten

            Hinweis: Für Fensterposition/-größe muss die App in den \
            Systemeinstellungen unter „Datenschutz & Sicherheit › \
            Bedienungshilfen“ erlaubt sein.

            Copyright © 2026 Norbert Jander
            Erstellt nach einer Idee von Norbert Jander.
            Technische Umsetzung mit Claude Opus.

            Lizenz: MIT
            """,
            """
            Desktop Profile Manager v\(Paths.appVersion) (Swift)

            Work environment manager for macOS:
            • Save/restore desktop icon positions
            • Hide individual icons
            • Desktop wallpaper per profile
            • Launch apps incl. window position/size

            Note: For window position/size, the app must be allowed in \
            System Settings under “Privacy & Security › Accessibility”.

            Copyright © 2026 Norbert Jander
            Based on an idea by Norbert Jander.
            Technical implementation with Claude Opus.

            License: MIT
            """)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func onQuit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
    }

    // MARK: - Widget

    func showWidget() {
        let w = ProfileWidget(app: self)
        widget = w
        w.show()
    }

    func widgetClosed() {
        widget = nil
        // Beim App-Beenden die Einstellung NICHT ändern – sonst wäre das
        // Widget nach dem nächsten Start ausgeblendet.
        if isTerminating { return }
        config.set("widget_visible", false)
        config.save()
        buildMenu()
    }

    // MARK: - Setup-Fenster

    func openSetupWindow(editName: String?) {
        let window = ProfileSetupWindow(app: self, editName: editName)
        setupWindow = window
        window.show()
    }

    // MARK: - Auto-Restore

    func startAutoRestore() {
        stopAutoRestore()
        let minutes = config.get("auto_restore_interval_minutes", 30)
        autoRestoreTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let profile = self.config.get("auto_restore_profile", "")
            if !profile.isEmpty {
                let iconsOnly = self.config.get("auto_restore_icons_only", false)
                self.doRestore(profile, notify: false, includeApps: false, iconsOnly: iconsOnly)
            }
        }
    }

    func stopAutoRestore() {
        autoRestoreTimer?.invalidate()
        autoRestoreTimer = nil
    }

    func restoreOnLogin() {
        let profile = config.get("auto_restore_profile", "")
        if !profile.isEmpty, Profiles.profilePath(profile).map({ FileManager.default.fileExists(atPath: $0.path) }) == true {
            let iconsOnly = config.get("auto_restore_icons_only", false)
            doRestore(profile, notify: false, iconsOnly: iconsOnly)
        }
    }
}

/// Einfache Benachrichtigungen über osascript (kein Bundle nötig).
enum Notifier {
    static func show(_ title: String, _ message: String) {
        let t = Shell.esc(title)
        let m = Shell.esc(message.replacingOccurrences(of: "\n", with: " "))
        _ = Shell.runAppleScript("display notification \"\(m)\" with title \"\(Paths.appName)\" subtitle \"\(t)\"")
    }
}
