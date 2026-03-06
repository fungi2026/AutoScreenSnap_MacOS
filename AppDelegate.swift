import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let snapManager = ScreenSnapManager()
    private var toggleMenuItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var lastResultMenuItem: NSMenuItem!

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

        let openItem = NSMenuItem(title: "Open Snapshots Folder", action: #selector(openFolder), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        updateUI()
    }

    private func updateUI() {
        let running = snapManager.isRunning
        statusItem.button?.image = NSImage(
            systemSymbolName: running ? "camera.fill" : "camera",
            accessibilityDescription: nil)
        toggleMenuItem.title  = running ? "■  Stop Capturing" : "▶  Start Capturing"
        statusMenuItem.title  = running ? "Capturing every 5 seconds…" : "Status: Stopped"
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

    @objc private func openFolder() {
        let url = ScreenSnapManager.snapshotsBaseURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
