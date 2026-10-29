// gifcap: drag-select a region of the screen, record it, get an animated GIF.
//
// Run via the gifcap wrapper next to this file, which compiles it on first use.
// Recording uses ScreenCaptureKit, conversion uses ffmpeg. The app that
// launches gifcap (Terminal, Ghostty, Shortcuts...) needs Screen Recording
// permission in System Settings > Privacy & Security.
//
// Built into gifcap.app by gifcap-app, it runs from the Dock: errors show as
// alerts instead of on stderr and the GIF is revealed in Finder.
//
// It does not use `screencapture -v`: that draws its own overlay over the
// stop button, swallows Esc, and outlives gifcap if gifcap is killed.

import AppKit
import ScreenCaptureKit

let usage = """
usage: gifcap [-f fps] [-s scale] [-d seconds] [-o dir] [-k] [-m] [-r]
  -f fps      frames per second in the GIF (default 15)
  -s scale    size relative to the selection in points; 2 = full Retina (default 1)
  -d seconds  stop automatically after this many seconds
  -o dir      where to write the GIF (default ~/Desktop)
  -k          show mouse clicks in the recording
  -m          keep the intermediate .mov next to the GIF
  -r          reveal the GIF in Finder when done
Drag to select a region (Esc cancels). Stop with the Stop button, the menu bar item
or Ctrl-C in the terminal.
The GIF path is printed and the file is put on the clipboard.
"""

// True when running as gifcap.app (launched from the Dock or Finder) rather than from a terminal.
let isApp = Bundle.main.bundleURL.pathExtension == "app"

struct Options {
    var fps = 15
    var scale = 1.0
    var duration: Double? = nil
    var outDir = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
    var clicks = false
    var keepMov = false
    var reveal = isApp
}

func fail(_ msg: String, openPrivacySettings: Bool = false) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    if isApp {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "gifcap"
        alert.informativeText = msg.replacingOccurrences(of: "gifcap: ", with: "")
        alert.runModal()
        if openPrivacySettings, let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    exit(1)
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func value(_ flag: String) -> String {
        guard !args.isEmpty else { fail("gifcap: \(flag) needs a value\n\n\(usage)") }
        return args.removeFirst()
    }
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "-f": guard let v = Int(value(a)), v > 0 else { fail(usage) }; o.fps = v
        case "-s": guard let v = Double(value(a)), v > 0 else { fail(usage) }; o.scale = v
        case "-d": guard let v = Double(value(a)), v > 0 else { fail(usage) }; o.duration = v
        case "-o": o.outDir = (value(a) as NSString).expandingTildeInPath
        case "-k": o.clicks = true
        case "-m": o.keepMov = true
        case "-r": o.reveal = true
        case "-h", "--help": print(usage); exit(0)
        default: fail("gifcap: unknown option \(a)\n\n\(usage)")
        }
    }
    return o
}

func findFFmpeg() -> String {
    let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        + ["/opt/homebrew/bin", "/usr/local/bin"]
    for d in dirs where FileManager.default.isExecutableFile(atPath: d + "/ffmpeg") {
        return d + "/ffmpeg"
    }
    fail("gifcap: ffmpeg not found (brew install ffmpeg)")
}

// MARK: - Selection overlay

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    var start: NSPoint?
    var current: NSPoint?
    let onDone: (NSRect?) -> Void

    init(frame: NSRect, onDone: @escaping (NSRect?) -> Void) {
        self.onDone = onDone
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    var selection: NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    override func mouseDown(with e: NSEvent) {
        start = convert(e.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }
    override func mouseDragged(with e: NSEvent) {
        current = convert(e.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseUp(with e: NSEvent) {
        current = convert(e.locationInWindow, from: nil)
        guard let r = selection, r.width >= 8, r.height >= 8, let w = window else {
            start = nil; current = nil; needsDisplay = true
            return
        }
        onDone(w.convertToScreen(convert(r, to: nil)))
    }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { onDone(nil) }  // Esc
    }

    override func draw(_ dirty: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        guard let r = selection else {
            let hint = "Drag to select a region to record · Esc to cancel" as NSString
            let size = hint.size(withAttributes: attrs)
            hint.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY), withAttributes: attrs)
            return
        }
        NSColor.clear.setFill()
        r.fill(using: .copy)
        NSColor.white.setStroke()
        NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5)).stroke()
        let label = "\(Int(r.width)) × \(Int(r.height))" as NSString
        label.draw(at: NSPoint(x: r.minX, y: max(r.minY - 20, 4)), withAttributes: attrs)
    }
}

// MARK: - Recording indicator

final class BorderView: NSView {
    override func draw(_ dirty: NSRect) {
        NSColor.systemRed.setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        p.lineWidth = 2
        p.stroke()
    }
}

// MARK: - Controller

final class Controller: NSObject, @unchecked Sendable, SCStreamOutput, SCRecordingOutputDelegate {
    let opts: Options
    let ffmpeg: String
    var overlays: [NSWindow] = []
    var border: NSWindow?
    var stopPanel: NSPanel?
    var stopButton: NSButton?
    var statusItem: NSStatusItem?
    var timer: Timer?
    var stream: SCStream?
    var recording = false
    var finished = false
    var sigint: DispatchSourceSignal?
    var started = Date()
    var region = NSRect.zero
    var movPath = ""
    var gifPath = ""

    init(opts: Options) {
        self.opts = opts
        self.ffmpeg = findFFmpeg()
    }

    func begin() {
        // Ctrl-C cancels the selection, or stops and saves a recording.
        signal(SIGINT, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        s.setEventHandler { [weak self] in
            guard let self = self, self.stream != nil else { exit(130) }
            self.stop()
        }
        s.resume()
        sigint = s

        for screen in NSScreen.screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size)) { [weak self] r in
                self?.selected(r)
            }
            w.contentView = v
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(v)
            overlays.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func selected(_ rect: NSRect?) {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        guard let rect = rect?.integral else { exit(0) }
        region = rect
        // Let the overlay disappear before the first frame is grabbed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                do { try await self.startRecording() } catch { fail("gifcap: could not start recording: \(error)") }
            }
        }
    }

    // On the main actor so it resumes on the main thread after each await: it creates windows.
    @MainActor func startRecording() async throws {
        // ScreenCaptureKit uses top-left-origin global coordinates.
        let mainHeight = NSScreen.screens[0].frame.height
        let global = CGRect(x: region.minX, y: mainHeight - region.maxY, width: region.width, height: region.height)
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            fail("gifcap: cannot capture the screen (\(error.localizedDescription)). Give the app running "
                + "gifcap Screen Recording permission in System Settings > Privacy & Security.",
                 openPrivacySettings: true)
        }
        let center = CGPoint(x: global.midX, y: global.midY)
        guard let display = content.displays.first(where: { CGDisplayBounds($0.displayID).contains(center) })
            ?? content.displays.first else { fail("gifcap: no display found") }
        let bounds = CGDisplayBounds(display.displayID)
        let pixelScale = NSScreen.screens.first { $0.frame.intersects(region) }?.backingScaleFactor ?? 2

        let config = SCStreamConfiguration()
        config.sourceRect = global.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        config.width = Int(region.width * pixelScale)
        config.height = Int(region.height * pixelScale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.showMouseClicks = opts.clicks
        let me = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let base = "gifcap-" + stamp.string(from: Date())
        try? FileManager.default.createDirectory(atPath: opts.outDir, withIntermediateDirectories: true)
        gifPath = (opts.outDir as NSString).appendingPathComponent(base + ".gif")
        movPath = opts.keepMov
            ? (opts.outDir as NSString).appendingPathComponent(base + ".mov")
            : (NSTemporaryDirectory() as NSString).appendingPathComponent(base + ".mov")

        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = URL(fileURLWithPath: movPath)
        recConfig.outputFileType = .mov
        recConfig.videoCodecType = .h264
        let s = SCStream(filter: filter, configuration: config, delegate: nil)
        // A no-op frame output; without one ScreenCaptureKit logs a warning per frame.
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "gifcap.frames"))
        try s.addRecordingOutput(SCRecordingOutput(configuration: recConfig, delegate: self))
        try await s.startCapture()
        stream = s
        recording = true
        started = Date()
        showRecordingUI()
        if let d = opts.duration {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { self.stop() }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { self.recordingFinished() }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async { fail("gifcap: recording failed: \(error.localizedDescription)") }
    }

    func showRecordingUI() {
        // Red frame just outside the region, so it is not in the recording.
        let b = NSWindow(contentRect: region.insetBy(dx: -3, dy: -3), styleMask: .borderless, backing: .buffered, defer: false)
        b.isOpaque = false
        b.backgroundColor = .clear
        b.ignoresMouseEvents = true
        b.level = .screenSaver
        b.sharingType = .none
        b.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        b.contentView = BorderView()
        b.orderFrontRegardless()
        border = b

        // Stop button below the region, or above it if there is no room.
        let size = NSSize(width: 130, height: 32)
        let screen = NSScreen.screens.first { $0.frame.intersects(region) } ?? NSScreen.screens[0]
        var origin = NSPoint(x: region.midX - size.width / 2, y: region.minY - size.height - 10)
        if origin.y < screen.visibleFrame.minY { origin.y = region.maxY + 10 }
        if origin.y + size.height > screen.visibleFrame.maxY { origin.y = region.minY + 10 }
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let button = NSButton(title: "■ Stop 0:00", target: self, action: #selector(stop))
        button.bezelStyle = .rounded
        button.contentTintColor = .systemRed
        button.frame = NSRect(origin: .zero, size: size)
        panel.contentView = button
        panel.orderFrontRegardless()
        stopPanel = panel
        stopButton = button

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "● 0:00"
        item.button?.contentTintColor = .systemRed
        item.button?.target = self
        item.button?.action = #selector(stop)
        statusItem = item

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    func tick() {
        let s = Int(Date().timeIntervalSince(started))
        let t = String(format: "%d:%02d", s / 60, s % 60)
        stopButton?.title = "■ Stop \(t)"
        statusItem?.button?.title = "● \(t)"
    }

    @objc func stop() {
        guard recording, let s = stream else { return }
        recording = false
        timer?.invalidate()
        stopButton?.isEnabled = false
        stopButton?.title = "Saving…"
        statusItem?.button?.title = "Saving…"
        Task { @MainActor in
            try? await s.stopCapture()
            // The recording delegate normally fires first; this covers it not firing.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.recordingFinished()
        }
    }

    func recordingFinished() {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        border?.orderOut(nil)
        stopPanel?.orderOut(nil)
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }

        guard FileManager.default.fileExists(atPath: movPath) else {
            fail("gifcap: no recording was made. Check that the app running gifcap has "
                + "Screen Recording permission (System Settings > Privacy & Security).",
                 openPrivacySettings: true)
        }
        let width = max(2, Int((region.width * opts.scale).rounded()))
        let filter = "fps=\(opts.fps),scale=\(width):-1:flags=lanczos,split[a][b];"
            + "[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        // ffmpeg runs in its own process group, so touching the terminal would get it stopped (SIGTTIN/SIGTTOU).
        p.arguments = ["-nostdin", "-loglevel", "error", "-y", "-i", movPath, "-vf", filter, "-loop", "0", gifPath]
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { fail("gifcap: could not run ffmpeg: \(error)") }
        p.waitUntilExit()
        if !opts.keepMov { try? FileManager.default.removeItem(atPath: movPath) }
        guard p.terminationStatus == 0 else { fail("gifcap: ffmpeg failed converting \(movPath)") }

        let url = URL(fileURLWithPath: gifPath)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        if opts.reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        NSSound(named: "Glass")?.play()
        print(gifPath)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }
}

let opts = parseOptions()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller(opts: opts)
controller.begin()
app.run()
