import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let snapManager = ScreenSnapManager()
    private var toggleMenuItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var lastResultMenuItem: NSMenuItem!
    private var intervalMenuItems: [NSMenuItem] = []

    private let intervalOptions: [(label: String, seconds: TimeInterval)] = [
        ("5 seconds",  5),
        ("15 seconds", 15),
        ("30 seconds", 30)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        snapManager.onStatusUpdate = { [weak self] message in
            self?.lastResultMenuItem.title = "Last: \(message)"
        }
    }

    // MARK: - Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Status: Stopped", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        lastResultMenuItem = NSMenuItem(title: "Last: —", action: nil, keyEquivalent: "")
        lastResultMenuItem.isEnabled = false
        menu.addItem(lastResultMenuItem)

        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(title: "▶  Start Capturing", action: #selector(toggleCapture), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        let testItem = NSMenuItem(title: "📷  Test Screenshot (opens Preview)", action: #selector(testCapture), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(.separator())

        // Interval submenu
        let intervalItem = NSMenuItem(title: "Interval", action: nil, keyEquivalent: "")
        let intervalSubmenu = NSMenu(title: "Interval")
        for option in intervalOptions {
            let item = NSMenuItem(
                title: option.label,
                action: #selector(setInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.seconds
            intervalSubmenu.addItem(item)
            intervalMenuItems.append(item)
        }
        intervalItem.submenu = intervalSubmenu
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Snapshots Folder", action: #selector(openFolder), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        updateUI()
        updateIntervalChecks()
    }

    private func updateUI() {
        let running = snapManager.isRunning
        let secs = Int(snapManager.captureInterval)
        statusItem.button?.image = NSImage(
            systemSymbolName: running ? "camera.fill" : "camera",
            accessibilityDescription: nil)
        toggleMenuItem.title = running ? "■  Stop Capturing" : "▶  Start Capturing"
        statusMenuItem.title = running ? "Capturing every \(secs)s…" : "Status: Stopped"
    }

    private func updateIntervalChecks() {
        for item in intervalMenuItems {
            let secs = item.representedObject as? TimeInterval ?? 0
            item.state = (secs == snapManager.captureInterval) ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func toggleCapture() {
        if snapManager.isRunning { snapManager.stop() } else { snapManager.start() }
        updateUI()
    }

    @objc private func testCapture() {
        lastResultMenuItem.title = "Last: testing…"
        snapManager.takeSnapshot(preview: true)
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? TimeInterval else { return }
        let wasRunning = snapManager.isRunning
        if wasRunning { snapManager.stop() }
        snapManager.captureInterval = secs
        if wasRunning { snapManager.start() }
        updateUI()
        updateIntervalChecks()
    }

    @objc private func openFolder() {
        let url = ScreenSnapManager.snapshotsBaseURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
