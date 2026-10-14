import AppKit

/// Fenster zum Anlegen/Bearbeiten eines Profils: Name, Emoji, Inhalts-Optionen,
/// Systemzustand und App-Auswahl.
final class ProfileSetupWindow: NSObject, NSWindowDelegate {
    private weak var app: AppDelegate?
    private let editName: String?
    private var window: NSWindow?

    private var nameField: NSTextField!
    private var emojiField: NSTextField!
    private var wifiCombo: NSComboBox!
    private var networkPopup: NSPopUpButton!
    private var wifiSwitchBox: NSButton!
    /// Modi in der Reihenfolge der Einträge von `networkPopup`.
    private var networkModes: [NetworkMode] = []
    /// Aktuell verbundenes WLAN, sobald es im Hintergrund ermittelt wurde.
    private var connectedSSID: String?
    private var optionSwitches: [(key: String, button: NSButton)] = []
    private var systemSwitches: [(key: String, button: NSButton)] = []
    private var appCheckboxes: [(name: String, button: NSButton)] = []
    /// Systemzustände älterer Profile ohne eigenen Schalter (z. B. „dnd“).
    /// Sie bleiben beim Bearbeiten unverändert erhalten.
    private var legacySystemKeys: [String] = []

    init(app: AppDelegate, editName: String?) {
        self.app = app
        self.editName = editName
    }

    private var isEdit: Bool { editName != nil }

    func show() {
        // Gespeicherte Werte beim Bearbeiten laden
        var savedSettings: [String: Any] = [:]
        var savedAppNames: [String] = []
        if let editName = editName, let data = Profiles.load(editName) {
            savedSettings = data["settings"] as? [String: Any] ?? [:]
            if let inc = savedSettings["included_apps"] as? [String] {
                savedAppNames = inc
            } else if let apps = data["apps"] as? [[String: Any]] {
                savedAppNames = apps.compactMap { $0["name"] as? String }
            }
        }

        let runningNames = Apps.getRunning().map { $0.name }
        let exclusions = Set(app?.config.get("app_exclusions", [String]()) ?? [])

        let appNames: [String]
        let checkedNames: Set<String>
        if isEdit {
            var seen = Set<String>()
            appNames = (savedAppNames + runningNames).filter { seen.insert($0).inserted }
            checkedNames = Set(savedAppNames)
        } else {
            appNames = runningNames
            checkedNames = Set(runningNames.filter { !exclusions.contains($0) })
        }

        let padding: CGFloat = 16
        let viewWidth: CGFloat = 460
        let rowHeight: CGFloat = 26
        let windowHeight: CGFloat = 740

        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: viewWidth, height: windowHeight),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = isEdit ? L("Profil bearbeiten", "Edit profile") : L("Neues Profil erstellen", "Create new profile")
        window.minSize = NSSize(width: 440, height: 560)
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        let content = window.contentView!
        let innerW = viewWidth - 2 * padding

        var yCursor = windowHeight - 18

        func label(_ text: String, bold: Bool = false, size: CGFloat = 12, height: CGFloat = 18) {
            let tf = NSTextField(labelWithString: text)
            tf.frame = NSRect(x: padding, y: yCursor - height, width: innerW, height: height)
            tf.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
            content.addSubview(tf)
        }
        func addSwitch(_ text: String, on: Bool) -> NSButton {
            let cb = NSButton(checkboxWithTitle: text, target: nil, action: nil)
            cb.frame = NSRect(x: padding, y: yCursor - 22, width: innerW, height: 22)
            cb.state = on ? .on : .off
            content.addSubview(cb)
            yCursor -= rowHeight
            return cb
        }

        // Profilname + Emoji
        label(L("Profilname:", "Profile name:"), bold: true)
        yCursor -= 24
        emojiField = NSTextField(frame: NSRect(x: padding, y: yCursor - 24, width: 44, height: 24))
        emojiField.placeholderString = "🙂"
        emojiField.alignment = .center
        emojiField.font = .systemFont(ofSize: 15)
        if isEdit { emojiField.stringValue = savedSettings["emoji"] as? String ?? "" }
        content.addSubview(emojiField)

        let pickX = padding + 44 + 4
        let emojiPicker = NSButton(frame: NSRect(x: pickX, y: yCursor - 24, width: 30, height: 24))
        emojiPicker.title = "😀"
        emojiPicker.bezelStyle = .rounded
        emojiPicker.target = self
        emojiPicker.action = #selector(onPickEmoji)
        emojiPicker.toolTip = L("Emoji auswählen", "Pick emoji")
        content.addSubview(emojiPicker)

        let nameX = pickX + 30 + 8
        nameField = NSTextField(frame: NSRect(x: nameX, y: yCursor - 24, width: padding + innerW - nameX, height: 24))
        nameField.placeholderString = L("z. B. Arbeit", "e.g. Work")
        nameField.font = .systemFont(ofSize: 13)
        if let editName = editName { nameField.stringValue = editName }
        content.addSubview(nameField)
        yCursor -= 36

        // Netzwerk-Zuordnung (für Auto-Umschalten). Angeboten wird nur, was der
        // Mac tatsächlich hat; eine bereits gespeicherte Zuordnung bleibt wählbar.
        label(L("Netzwerk (optional, für Auto-Umschalten):", "Network (optional, for auto switch):"))
        yCursor -= 22
        let savedMode = isEdit ? NetworkMode.from(settings: savedSettings) : .none
        let savedSSID = savedMode.usesWiFi ? (savedSettings["wifi_ssid"] as? String ?? "") : ""
        networkModes = Self.availableNetworkModes(hasWiFi: WiFi.isAvailable, hasEthernet: Ethernet.isAvailable,
                                                  saved: savedMode)
        let popupWidth: CGFloat = 190
        networkPopup = NSPopUpButton(frame: NSRect(x: padding - 2, y: yCursor - 25, width: popupWidth, height: 26),
                                     pullsDown: false)
        networkPopup.addItems(withTitles: networkModes.map(\.title))
        networkPopup.selectItem(at: networkModes.firstIndex(of: savedMode) ?? 0)
        networkPopup.target = self
        networkPopup.action = #selector(onNetworkModeChanged)
        content.addSubview(networkPopup)

        let comboX = padding + popupWidth + 6
        wifiCombo = NSComboBox(frame: NSRect(x: comboX, y: yCursor - 25, width: padding + innerW - comboX, height: 26))
        wifiCombo.placeholderString = L("WLAN wählen oder eingeben", "Choose or enter Wi-Fi")
        wifiCombo.font = .systemFont(ofSize: 13)
        wifiCombo.completes = true
        wifiCombo.numberOfVisibleItems = 12
        wifiCombo.stringValue = savedSSID
        if !savedSSID.isEmpty { wifiCombo.addItem(withObjectValue: savedSSID) }
        content.addSubview(wifiCombo)
        yCursor -= 30

        wifiSwitchBox = NSButton(checkboxWithTitle: L("WLAN passend schalten (bei „Kabel“ aus, bei „WLAN“ ein)",
                                                      "Switch Wi-Fi accordingly (off for “Cable”, on for “Wi-Fi”)"),
                                 target: nil, action: nil)
        wifiSwitchBox.frame = NSRect(x: padding, y: yCursor - 22, width: innerW, height: 22)
        wifiSwitchBox.state = isEdit && savedSettings[WiFiSwitch.settingsKey] as? Bool == true ? .on : .off
        wifiSwitchBox.toolTip = L(
            "Das Kabel bleibt immer eingeschaltet. WLAN wird nur ausgeschaltet, wenn ein Kabel verbunden ist, und kommt automatisch zurück, sobald das Kabel getrennt wird. Ohne WLAN funktionieren AirDrop und Handoff nicht.",
            "The cable always stays on. Wi-Fi is only turned off while a cable is connected and comes back automatically when the cable is disconnected. AirDrop and Handoff need Wi-Fi.")
        // Ohne WLAN-Hardware gibt es nichts zu schalten.
        wifiSwitchBox.isHidden = !WiFi.isAvailable
        content.addSubview(wifiSwitchBox)
        updateNetworkControls()
        loadWiFiNetworks(keeping: savedSSID)
        yCursor -= 30

        // Inhalts-Optionen
        label(isEdit ? L("Was soll wiederhergestellt werden?", "What should be restored?")
                     : L("Was soll gespeichert werden?", "What should be saved?"), bold: true)
        yCursor -= 26
        let optionDefs: [(String, String)] = [
            ("capture_positions", L("Icon-Positionen", "Icon positions")),
            ("capture_hidden", L("Versteckte Icons", "Hidden icons")),
            ("capture_wallpaper", L("Hintergrundbild", "Wallpaper")),
            ("capture_apps", L("Apps", "Apps")),
            ("capture_browser_tabs", L("Browser-Tabs (Safari, Chrome, Edge)", "Browser tabs (Safari, Chrome, Edge)")),
        ]
        for (key, text) in optionDefs {
            let fallback = key != "capture_browser_tabs"
            let on = isEdit ? (savedSettings[key] as? Bool ?? fallback) : true
            let toggle = addSwitch(text, on: on)
            if key == "capture_browser_tabs" {
                toggle.toolTip = L("Nur für Browser, die unten in der App-Liste ausgewählt sind.",
                                   "Only for browsers selected in the app list below.")
            }
            optionSwitches.append((key, toggle))
        }
        yCursor -= 6

        // Systemzustand
        label(L("Systemzustand (optional):", "System state (optional):"), bold: true)
        yCursor -= 26
        let savedSysKeyList = savedSettings["system_state_keys"] as? [String] ?? []
        let savedSysKeys = Set(savedSysKeyList)
        let knownSysKeys = Set(SystemState.optionOrder.map { $0.key })
        legacySystemKeys = savedSysKeyList.filter { !knownSysKeys.contains($0) }
        for opt in SystemState.optionOrder {
            let text = Localization.current == .en ? opt.en : opt.de
            let on = isEdit ? savedSysKeys.contains(opt.key) : false
            systemSwitches.append((opt.key, addSwitch(text, on: on)))
        }
        yCursor -= 6

        // App-Liste (scrollbar)
        label(L("Apps für dieses Profil:", "Apps for this profile:"), bold: true)
        yCursor -= 22
        let scrollTop = yCursor
        let scrollBottom: CGFloat = 90
        let scrollHeight = max(scrollTop - scrollBottom, 80)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: scrollBottom, width: viewWidth, height: scrollHeight))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        let contentHeight = max(CGFloat(appNames.count) * rowHeight, scrollHeight)
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth - 20, height: contentHeight))
        for (i, appName) in appNames.enumerated() {
            let y = contentHeight - CGFloat(i + 1) * rowHeight
            var title = appName
            if isEdit && !runningNames.contains(appName) {
                title += L("  (nicht aktiv)", "  (not running)")
            }
            let cb = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            cb.frame = NSRect(x: padding, y: y, width: viewWidth - 2 * padding - 20, height: rowHeight)
            cb.state = checkedNames.contains(appName) ? .on : .off
            docView.addSubview(cb)
            appCheckboxes.append((appName, cb))
        }
        scrollView.documentView = docView
        content.addSubview(scrollView)

        // Buttons
        let btnAll = NSButton(frame: NSRect(x: padding, y: 52, width: 170, height: 28))
        btnAll.title = L("Alle Apps auswählen", "Select all apps")
        btnAll.bezelStyle = .rounded
        btnAll.target = self
        btnAll.action = #selector(onSelectAllApps)
        content.addSubview(btnAll)

        let btnCreate = NSButton(frame: NSRect(x: viewWidth - padding - 170, y: 16, width: 170, height: 28))
        btnCreate.title = isEdit ? L("Änderungen speichern", "Save changes") : L("Profil erstellen", "Create profile")
        btnCreate.bezelStyle = .rounded
        btnCreate.keyEquivalent = "\r"
        btnCreate.target = self
        btnCreate.action = #selector(onCreate)
        content.addSubview(btnCreate)

        let btnCancel = NSButton(frame: NSRect(x: viewWidth - padding - 170 - 8 - 110, y: 16, width: 110, height: 28))
        btnCancel.title = L("Abbrechen", "Cancel")
        btnCancel.bezelStyle = .rounded
        btnCancel.target = self
        btnCancel.action = #selector(onCancel)
        content.addSubview(btnCancel)

        NSApp.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nameField)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func onSelectAllApps() {
        appCheckboxes.forEach { $0.button.state = .on }
    }

    /// Auswahl für die Netzwerk-Zuordnung: „Beides“ nur, wenn WLAN und Kabel
    /// vorhanden sind. Ein gespeicherter Modus geht beim Bearbeiten nie verloren.
    static func availableNetworkModes(hasWiFi: Bool, hasEthernet: Bool, saved: NetworkMode) -> [NetworkMode] {
        NetworkMode.allCases.filter { mode in
            if mode == saved { return true }
            switch mode {
            case .none: return true
            case .wifi: return hasWiFi
            case .ethernet: return hasEthernet
            case .both: return hasWiFi && hasEthernet
            }
        }
    }

    /// Aktuelles WLAN zuerst, danach die bekannten WLANs wie in den
    /// Systemeinstellungen; ein gespeicherter Name bleibt immer enthalten.
    static func wifiChoices(current: String?, known: [String], saved: String) -> [String] {
        var seen = Set<String>()
        return ([current, saved.isEmpty ? nil : saved].compactMap { $0 } + known)
            .filter { seen.insert($0).inserted }
    }

    private var selectedNetworkMode: NetworkMode {
        let index = networkPopup.indexOfSelectedItem
        return networkModes.indices.contains(index) ? networkModes[index] : .none
    }

    private func updateNetworkControls() {
        wifiCombo.isEnabled = selectedNetworkMode.usesWiFi
        wifiSwitchBox.isEnabled = selectedNetworkMode.canSwitchWiFi
    }

    @objc func onNetworkModeChanged() {
        updateNetworkControls()
        guard selectedNetworkMode.usesWiFi else { return }
        // Ohne Freigabe der Ortungsdienste meldet macOS das verbundene WLAN nicht.
        WiFi.requestPermissionIfNeeded()
        if wifiCombo.stringValue.isEmpty, let connectedSSID {
            wifiCombo.stringValue = connectedSSID
        }
        window?.makeFirstResponder(wifiCombo)
    }

    /// Lädt verbundenes und bekannte WLANs im Hintergrund in die Auswahlliste.
    private func loadWiFiNetworks(keeping saved: String) {
        guard WiFi.isAvailable else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let current = WiFi.currentSSID()
            let known = WiFi.knownNetworks()
            DispatchQueue.main.async {
                guard let self, self.window != nil else { return }
                self.connectedSSID = current
                let choices = Self.wifiChoices(current: current, known: known, saved: saved)
                self.wifiCombo.removeAllItems()
                self.wifiCombo.addItems(withObjectValues: choices)
                if let current {
                    self.wifiCombo.toolTip = L("Aktuell verbunden: \(current)", "Currently connected: \(current)")
                }
            }
        }
    }

    /// Setzt den Fokus ins Emoji-Feld und öffnet die macOS-Emoji-Auswahl.
    @objc func onPickEmoji() {
        window?.makeFirstResponder(emojiField)
        NSApp.orderFrontCharacterPalette(nil)
    }

    @objc func onCancel() {
        window?.close()
    }

    private func showAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    @objc func onCreate() {
        let rawName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if rawName.isEmpty {
            showAlert(L("Profilname fehlt", "Profile name missing"),
                      L("Bitte einen Namen für das Profil eingeben.", "Please enter a name for the profile."))
            return
        }
        // Vor dem Schließen prüfen, damit Eingaben bei Fehlern erhalten bleiben.
        guard let name = Profiles.validatedName(rawName) else {
            showAlert(L("Ungültiger Profilname", "Invalid profile name"),
                      L("Erlaubt sind Buchstaben, Ziffern, Leerzeichen, - und _. Der Name darf nicht mit _ beginnen.",
                        "Allowed are letters, digits, spaces, - and _. The name must not start with _."))
            return
        }
        let isRename = editName.map { $0.lowercased() != name.lowercased() } ?? true
        if isRename && Profiles.exists(name) {
            showAlert(L("Profil existiert bereits", "Profile already exists"),
                      L("Ein Profil mit dem Namen '\(name)' ist bereits vorhanden.",
                        "A profile named '\(name)' already exists."))
            return
        }
        if selectedNetworkMode.usesWiFi && wifiCombo.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            showAlert(L("WLAN fehlt", "Wi-Fi missing"),
                      L("Bitte ein WLAN auswählen oder als Netzwerk „Kabel“ bzw. „Keine Zuordnung“ wählen.",
                        "Please choose a Wi-Fi network or select “Cable” or “No assignment” as network."))
            window?.makeFirstResponder(wifiCombo)
            return
        }
        var options = Profiles.SaveOptions()
        for (key, btn) in optionSwitches {
            let on = btn.state == .on
            switch key {
            case "capture_positions": options.withPositions = on
            case "capture_hidden": options.withHidden = on
            case "capture_wallpaper": options.withWallpaper = on
            case "capture_apps": options.withApps = on
            case "capture_browser_tabs": options.withBrowserTabs = on
            default: break
            }
        }
        options.systemStateKeys = systemSwitches.filter { $0.button.state == .on }.map { $0.key }
            + legacySystemKeys
        options.emoji = emojiField.stringValue.trimmingCharacters(in: .whitespaces)
        options.networkMode = selectedNetworkMode
        options.wifiSSID = options.networkMode.usesWiFi
            ? wifiCombo.stringValue.trimmingCharacters(in: .whitespaces) : ""
        options.switchWiFi = !wifiSwitchBox.isHidden && wifiSwitchBox.state == .on
        options.includedApps = appCheckboxes.filter { $0.button.state == .on }.map { $0.name }

        window?.close()
        if let oldName = editName {
            // Bearbeiten: gespeicherte Icon-Daten erhalten, nur Metadaten/Apps ändern
            app?.doApplyEdit(oldName: oldName, newName: name, options: options)
        } else {
            app?.doSaveWithOptions(name, options: options)
        }
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window = nil
    }
}
