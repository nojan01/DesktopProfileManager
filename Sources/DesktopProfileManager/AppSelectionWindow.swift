import AppKit

/// Fenster zur Auswahl, welche laufenden Apps standardmäßig in Profile
/// aufgenommen werden. Nicht angehakte Apps landen in `app_exclusions`.
final class AppSelectionWindow: NSObject, NSWindowDelegate {
    private weak var app: AppDelegate?
    private var window: NSWindow?
    private var checkboxes: [(name: String, button: NSButton)] = []

    init(app: AppDelegate) {
        self.app = app
    }

    func show() {
        let apps = Apps.getRunning()
        if apps.isEmpty {
            Notifier.show(L("Keine Apps", "No apps"),
                          L("Keine laufenden Apps gefunden.", "No running apps found."))
            return
        }
        let exclusions = Set(app?.config.get("app_exclusions", [String]()) ?? [])

        let rowHeight: CGFloat = 26
        let padding: CGFloat = 16
        let viewWidth: CGFloat = 420
        let contentHeight = CGFloat(apps.count) * rowHeight
        let windowHeight = min(contentHeight + 140, 600)

        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: viewWidth, height: windowHeight),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Apps für Profile auswählen", "Select apps for profiles")
        window.minSize = NSSize(width: 350, height: 250)
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        let content = window.contentView!

        let info = NSTextField(labelWithString:
            L("Angehakte Apps werden beim Speichern in Profile aufgenommen.",
              "Checked apps will be included in profiles when saving."))
        info.frame = NSRect(x: padding, y: windowHeight - 40, width: viewWidth - 2 * padding, height: 28)
        info.font = .systemFont(ofSize: 12)
        content.addSubview(info)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 50, width: viewWidth, height: windowHeight - 90))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        let docHeight = max(contentHeight, windowHeight - 90)
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth - 20, height: docHeight))
        for (i, appInfo) in apps.enumerated() {
            let y = contentHeight - CGFloat(i + 1) * rowHeight
            let cb = NSButton(checkboxWithTitle: appInfo.name, target: nil, action: nil)
            cb.frame = NSRect(x: padding, y: y, width: viewWidth - 2 * padding, height: rowHeight)
            cb.state = exclusions.contains(appInfo.name) ? .off : .on
            docView.addSubview(cb)
            checkboxes.append((appInfo.name, cb))
        }
        scrollView.documentView = docView
        content.addSubview(scrollView)

        let btnAll = NSButton(frame: NSRect(x: padding, y: 12, width: 120, height: 28))
        btnAll.title = L("Alle auswählen", "Select all")
        btnAll.bezelStyle = .rounded
        btnAll.target = self
        btnAll.action = #selector(onSelectAll)
        content.addSubview(btnAll)

        let btnApply = NSButton(frame: NSRect(x: viewWidth - padding - 120, y: 12, width: 120, height: 28))
        btnApply.title = L("Speichern", "Save")
        btnApply.bezelStyle = .rounded
        btnApply.keyEquivalent = "\r"
        btnApply.target = self
        btnApply.action = #selector(onApply)
        content.addSubview(btnApply)

        NSApp.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func onSelectAll() {
        checkboxes.forEach { $0.button.state = .on }
    }

    @objc func onApply() {
        // Nicht angehakte Apps werden ausgeschlossen.
        let exclusions = checkboxes.filter { $0.button.state == .off }.map { $0.name }
        app?.config.set("app_exclusions", exclusions)
        app?.config.save()
        window?.close()
        Notifier.show(L("App-Auswahl gespeichert", "App selection saved"), "")
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window = nil
    }
}
