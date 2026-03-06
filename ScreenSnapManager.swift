import AppKit
import Foundation
import ScreenCaptureKit

final class ScreenSnapManager {

    static let snapshotsBaseURL: URL = {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.appendingPathComponent("screensnap")
    }()

    private static let captureInterval: TimeInterval = 5
    private static let jpegQuality: CGFloat = 0.75
    private static let maxImageWidth: CGFloat = 1920

    private var timer: Timer?
    private(set) var isRunning = false
    var onStatusUpdate: ((String) -> Void)?

    // Tracks the last app the user was actually working in (never AutoScreenSnap itself)
    private var lastActivePID:  pid_t  = 0
    private var lastActiveName: String = "Unknown"

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return }
        lastActivePID  = app.processIdentifier
        lastActiveName = app.localizedName ?? "Unknown"
    }

    // MARK: - Control

    func start() {
        isRunning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard self?.isRunning == true else { return }
            self?.takeSnapshot(preview: false)
        }
        let t = Timer(timeInterval: Self.captureInterval, repeats: true) { [weak self] _ in
            self?.takeSnapshot(preview: false)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Snapshot

    func takeSnapshot(preview: Bool) {
        // Use lastActivePID if available; otherwise fall back to current frontmost (if not our app)
        if lastActivePID == 0 {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            lastActivePID  = app.processIdentifier
            lastActiveName = app.localizedName ?? "Unknown"
        }

        let pid       = lastActivePID
        let appName   = sanitized(lastActiveName)
        let timestamp = DateFormatter.snapFormatter.string(from: Date())
        let prefix    = preview ? "test_" : ""
        let folderURL = Self.snapshotsBaseURL.appendingPathComponent(appName)
        let fileURL   = folderURL.appendingPathComponent("\(prefix)\(appName)_\(timestamp).jpg")
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        if #available(macOS 14.0, *) {
            captureWindow(for: pid, saveTo: fileURL, preview: preview)
        }
    }

    // MARK: - Direct window capture via SCKit

    @available(macOS 14.0, *)
    private func captureWindow(for pid: pid_t, saveTo url: URL, preview: Bool) {
        // Resolve the frontmost real window ID first (CGWindowList is in z-order, front to back)
        let targetID = frontWindowID(for: pid)

        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, _ in
            guard let self else { return }

            let allWindows = content?.windows ?? []

            // Prefer matching by CGWindowID; fall back to first visible non-desktop-sized window
            let targetWindow: SCWindow?
            if let wid = targetID {
                targetWindow = allWindows.first { $0.windowID == wid }
            } else {
                let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 3000, height: 3000)
                targetWindow = allWindows.first { w in
                    w.owningApplication?.processID == pid &&
                    w.isOnScreen &&
                    w.frame.width  > 50 &&
                    w.frame.height > 50 &&
                    !(w.frame.width  > screenSize.width  * 0.97 &&
                      w.frame.height > screenSize.height * 0.97)
                }
            }

            guard let window = targetWindow else {
                DispatchQueue.main.async {
                    self.onStatusUpdate?("No window found — is the app visible?")
                }
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale  = NSScreen.main?.backingScaleFactor ?? 2.0
            let config = SCStreamConfiguration()
            config.capturesAudio = false
            config.width  = Int(window.frame.width  * scale)
            config.height = Int(window.frame.height * scale)

            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { [weak self] image, error in
                guard let self else { return }
                guard let image else {
                    DispatchQueue.main.async {
                        self.onStatusUpdate?("Capture failed: \(error?.localizedDescription ?? "unknown")")
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.saveAsJPEG(image, to: url)
                    self.onStatusUpdate?("Saved \(url.lastPathComponent)")
                    if preview { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    // MARK: - Frontmost window ID

    // CGWindowListCopyWindowInfo returns windows front-to-back.
    // We walk the list to find the first normal (layer 0) window for the given PID
    // that is not a desktop-covering overlay (e.g. Finder's desktop "window").
    private func frontWindowID(for pid: pid_t) -> CGWindowID? {
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 3000, height: 3000)

        for info in list {
            guard Int32(info[kCGWindowOwnerPID as String] as? Int ?? -1) == pid else { continue }
            guard (info[kCGWindowLayer as String] as? Int ?? 999) == 0 else { continue }
            guard let dict   = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  bounds.width > 50, bounds.height > 50 else { continue }
            // Skip desktop-filling windows (Finder desktop, full-screen overlays, etc.)
            if bounds.width  > screenSize.width  * 0.97 &&
               bounds.height > screenSize.height * 0.97 { continue }
            if let wid = info[kCGWindowNumber as String] as? CGWindowID { return wid }
        }
        return nil
    }

    // MARK: - Save

    private func saveAsJPEG(_ cgImage: CGImage, to url: URL) {
        let image = downscaledIfNeeded(cgImage)
        let nsImage = NSImage(cgImage: image, size: .zero)
        guard let tiff = nsImage.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: Self.jpegQuality])
        else { return }
        try? data.write(to: url)
    }

    private func downscaledIfNeeded(_ cgImage: CGImage) -> CGImage {
        let width = CGFloat(cgImage.width)
        guard width > Self.maxImageWidth else { return cgImage }
        let scale = Self.maxImageWidth / width
        let w = Int(width * scale), h = Int(CGFloat(cgImage.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return cgImage }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? cgImage
    }

    private func sanitized(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension DateFormatter {
    static let snapFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()
}
