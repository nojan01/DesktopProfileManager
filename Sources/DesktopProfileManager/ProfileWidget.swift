import AppKit

/// Ziehbare Kopfleiste des Widgets. Ein Mausklick auf diese Fläche bewegt das
/// gesamte Panel – so lässt sich das Widget zuverlässig überallhin ziehen,
/// auch wenn die Profil-Buttons den Rest der Fläche ausfüllen.
final class WidgetDragHandle: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Schwebendes Profil-Widget – frei verschiebbares Panel mit einem Button pro
/// Profil. Zwei Varianten: normal (Emoji + Name) und kompakt (nur Emojis).
final class ProfileWidget: NSObject, NSWindowDelegate {
    private weak var app: AppDelegate?
    private var panel: NSPanel?
    private var profileNames: [String] = []

    init(app: AppDelegate) {
        self.app = app
    }

    func show() {
        rebuild()
        panel?.orderFront(nil)
    }

    func close() {
        panel?.close()
    }

    func rebuild() {
        guard let app = app else { return }
        let profiles = Profiles.list()
        let compact = app.config.get("widget_compact", false)

        let headerHeight: CGFloat = 20
        let padding: CGFloat = 12
        let rowGap: CGFloat = 6
        let rowHeight: CGFloat = compact ? 64 : 46
        let width: CGFloat = compact ? (64 + 2 * padding) : 280
        let n = CGFloat(max(profiles.count, 1))
        let contentHeight = headerHeight + n * rowHeight + (n - 1) * rowGap + 2 * padding

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            let oldFrame = panel.frame
            let oldTop = oldFrame.origin.y + oldFrame.size.height
            let oldRight = oldFrame.origin.x + oldFrame.size.width
            panel.setContentSize(NSSize(width: width, height: contentHeight))
            let newFrame = panel.frame
            panel.setFrameOrigin(NSPoint(x: oldRight - newFrame.size.width,
                                         y: oldTop - newFrame.size.height))
        } else {
            panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: contentHeight),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            // Transparent, ohne Titelleiste – nur der Inhalt ist sichtbar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.delegate = self
            self.panel = panel

            if let pos = app.config.values["widget_pos"] as? [Double], pos.count == 2 {
                panel.setFrameOrigin(NSPoint(x: pos[0], y: pos[1]))
            } else if let screen = NSScreen.main {
                let vf = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: vf.origin.x + vf.size.width - width - 20,
                                             y: vf.origin.y + vf.size.height - contentHeight - 20))
            }
        }

        guard let contentView = panel.contentView else { return }
        // Transparenter Hintergrund, aber abgerundeter Rahmen bleibt sichtbar
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.cornerRadius = 12
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        contentView.subviews.forEach { $0.removeFromSuperview() }
        profileNames = profiles.map { $0.name }

        // Ziehbare Kopfleiste mit Greif-Indikator
        let handle = WidgetDragHandle(frame: NSRect(x: 0, y: contentHeight - headerHeight,
                                                    width: width, height: headerHeight))
        let grip = NSView(frame: NSRect(x: width / 2 - 18, y: headerHeight / 2 - 2, width: 36, height: 4))
        grip.wantsLayer = true
        grip.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        grip.layer?.cornerRadius = 2
        handle.addSubview(grip)
        handle.toolTip = L("Zum Verschieben hier ziehen", "Drag here to move")
        contentView.addSubview(handle)

        if profiles.isEmpty {
            let label = NSTextField(labelWithString: L("(keine Profile)", "(no profiles)"))
            label.frame = NSRect(x: padding, y: (contentHeight - headerHeight) / 2 - 10,
                                 width: width - 2 * padding, height: 20)
            label.alignment = .center
            label.font = .systemFont(ofSize: 12)
            contentView.addSubview(label)
            return
        }

        for (i, p) in profiles.enumerated() {
            let y = contentHeight - headerHeight - padding - CGFloat(i + 1) * rowHeight - CGFloat(i) * rowGap
            let btn = NSButton(frame: NSRect(x: padding, y: y, width: width - 2 * padding, height: rowHeight))
            btn.bezelStyle = .rounded
            btn.tag = i
            btn.target = self
            btn.action = #selector(onProfileButton(_:))
            if compact {
                btn.title = p.emoji.isEmpty ? String(p.name.prefix(1)).uppercased() : p.emoji
                btn.font = .systemFont(ofSize: 42)
                btn.toolTip = p.name
            } else {
                let prefix = p.emoji.isEmpty ? "" : p.emoji + " "
                btn.title = "\(prefix)\(p.name)"
                btn.font = .systemFont(ofSize: 19)
            }
            if p.name == app.activeProfile {
                btn.bezelColor = .controlAccentColor
            }
            contentView.addSubview(btn)
        }
    }

    @objc func onProfileButton(_ sender: NSButton) {
        let idx = sender.tag
        if idx >= 0 && idx < profileNames.count {
            app?.doRestore(profileNames[idx], markActive: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let panel = panel else { return }
        app?.config.set("widget_pos", [Double(panel.frame.origin.x), Double(panel.frame.origin.y)])
        app?.config.save()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        app?.widgetClosed()
    }
}
