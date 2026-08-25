import AppKit

/// Fenster mit Checkboxen zum Ein-/Ausblenden einzelner Desktop-Dateien.
final class VisibilityWindow: NSObject, NSWindowDelegate {
    private weak var app: AppDelegate?
    private var window: NSWindow?
    private var checkboxes: [(name: String, button: NSButton)] = []

    init(app: AppDelegate) {
        self.app = app
    }

    func show() {
        let items = DesktopIcons.getAllItems()
        if items.isEmpty {
            Notifier.show(L("Keine Items", "No items"),
                          L("Keine Icons auf dem Desktop gefunden.", "No icons found on the desktop."))
            return
        }

        let rowHeight: CGFloat = 26
        let padding: CGFloat = 16
        let viewWidth: CGFloat = 420
        let contentHeight = CGFloat(items.count) * rowHeight
        let windowHeight = min(contentHeight + 120, 600)

        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: viewWidth, height: windowHeight),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Icons ein-/ausblenden", "Show/hide icons")
        window.minSize = NSSize(width: 350, height: 250)
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        let content = window.contentView!

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 50, width: viewWidth, height: windowHeight - 80))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        let docHeight = max(contentHeight, windowHeight - 80)
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth - 20, height: docHeight))
        for (i, item) in items.enumerated() {
            let y = contentHeight - CGFloat(i + 1) * rowHeight
            let cb = NSButton(checkboxWithTitle: item.name, target: nil, action: nil)
            cb.frame = NSRect(x: padding, y: y, width: viewWidth - 2 * padding, height: rowHeight)
            cb.state = item.hidden ? .off : .on // angehakt = sichtbar
            docView.addSubview(cb)
            checkboxes.append((item.name, cb))
        }
        scrollView.documentView = docView
        content.addSubview(scrollView)

        let btnAll = NSButton(frame: NSRect(x: padding, y: 12, width: 120, height: 28))
        btnAll.title = L("Alle einblenden", "Show all")
        btnAll.bezelStyle = .rounded
        btnAll.target = self
        btnAll.action = #selector(onSelectAll)
        content.addSubview(btnAll)

        let btnApply = NSButton(frame: NSRect(x: viewWidth - padding - 120, y: 12, width: 120, height: 28))
        btnApply.title = L("Anwenden", "Apply")
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
        let changes = checkboxes.map { (name: $0.name, visible: $0.button.state == .on) }
        window?.close()
        DispatchQueue.global().async {
            let result = DesktopIcons.applyVisibility(
                changes.map { (name: $0.name, hidden: !$0.visible) })
            DispatchQueue.main.async {
                let detail = result.failed == 0 ? "" :
                    L("\(result.failed) Icon(s) konnten nicht geändert werden.",
                      "\(result.failed) icon(s) could not be changed.")
                Notifier.show(L("Sichtbarkeit geändert", "Visibility changed"), detail)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window = nil
    }
}
