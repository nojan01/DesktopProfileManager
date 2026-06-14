import AppKit

/// Fenster zum Anlegen/Bearbeiten eines Profils: Name, Emoji, Inhalts-Optionen,
/// Systemzustand und App-Auswahl.
final class ProfileSetupWindow: NSObject, NSWindowDelegate {
    private weak var app: AppDelegate?
    private let editName: String?
    private var window: NSWindow?

    private var nameField: NSTextField!
    private var emojiField: NSTextField!
    private var wifiField: NSTextField!
    private var optionSwitches: [(key: String, button: NSButton)] = []
    private var systemSwitches: [(key: String, button: NSButton)] = []
    private var appCheckboxes: [(name: String, button: NSButton)] = []

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

        // WLAN-Zuordnung (für Auto-Umschalten)
        label(L("WLAN-Name (optional, für Auto-Umschalten):", "Wi-Fi name (optional, for auto switch):"))
        yCursor -= 22
        wifiField = NSTextField(frame: NSRect(x: padding, y: yCursor - 24, width: innerW, height: 24))
        wifiField.placeholderString = L("z. B. Zuhause-WLAN", "e.g. Home-WiFi")
        wifiField.font = .systemFont(ofSize: 13)
        if isEdit { wifiField.stringValue = savedSettings["wifi_ssid"] as? String ?? "" }
        content.addSubview(wifiField)
        yCursor -= 34

        // Inhalts-Optionen
        label(isEdit ? L("Was soll wiederhergestellt werden?", "What should be restored?")
                     : L("Was soll gespeichert werden?", "What should be saved?"), bold: true)
        yCursor -= 26
        let optionDefs: [(String, String)] = [
            ("capture_positions", L("Icon-Positionen", "Icon positions")),
            ("capture_hidden", L("Versteckte Icons", "Hidden icons")),
            ("capture_wallpaper", L("Hintergrundbild", "Wallpaper")),
            ("capture_apps", L("Apps", "Apps")),
        ]
        for (key, text) in optionDefs {
            let on = isEdit ? (savedSettings[key] as? Bool ?? true) : true
            optionSwitches.append((key, addSwitch(text, on: on)))
        }
        yCursor -= 6

        // Systemzustand
        label(L("Systemzustand (optional):", "System state (optional):"), bold: true)
        yCursor -= 26
        let savedSysKeys = Set(savedSettings["system_state_keys"] as? [String] ?? [])
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

    /// Setzt den Fokus ins Emoji-Feld und öffnet die macOS-Emoji-Auswahl.
    @objc func onPickEmoji() {
        window?.makeFirstResponder(emojiField)
        NSApp.orderFrontCharacterPalette(nil)
    }

    @objc func onCancel() {
        window?.close()
    }

    @objc func onCreate() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            let alert = NSAlert()
            alert.messageText = L("Profilname fehlt", "Profile name missing")
            alert.informativeText = L("Bitte einen Namen für das Profil eingeben.", "Please enter a name for the profile.")
            alert.runModal()
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
            default: break
            }
        }
        options.systemStateKeys = systemSwitches.filter { $0.button.state == .on }.map { $0.key }
        options.emoji = emojiField.stringValue.trimmingCharacters(in: .whitespaces)
        options.wifiSSID = wifiField.stringValue.trimmingCharacters(in: .whitespaces)
        options.includedApps = appCheckboxes.filter { $0.button.state == .on }.map { $0.name }

        window?.close()
        if let oldName = editName {
            // Bearbeiten: gespeicherte Icon-Daten erhalten, nur Metadaten/Apps ändern
            app?.doApplyEdit(oldName: oldName, newName: name, options: options)
        } else {
            app?.doSaveWithOptions(name, options: options)
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window = nil
    }
}
