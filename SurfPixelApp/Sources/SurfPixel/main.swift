import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var timer: Timer?
    private let matrix = MatrixDevice()
    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private lazy var settings: SettingsWindowController = {
        let s = SettingsWindowController()
        s.onSave = { [weak self] in self?.updateNow() }
        return s
    }()

    /// Template wave glyph for the status item: vector, recolored by the
    /// system to match the menu bar (white on dark menu bars).
    private func waveIcon() -> NSImage {
        if let symbol = NSImage(systemSymbolName: "water.waves",
                                accessibilityDescription: "SurfPixel") {
            symbol.isTemplate = true
            return symbol
        }
        // fallback: hand-drawn double wave
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            for baseY in [6.5, 11.5] {
                let path = NSBezierPath()
                path.lineWidth = 1.6
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: 2, y: baseY))
                path.curve(to: NSPoint(x: 9, y: baseY),
                           controlPoint1: NSPoint(x: 4, y: baseY + 3.5),
                           controlPoint2: NSPoint(x: 7, y: baseY + 3.5))
                path.curve(to: NSPoint(x: 16, y: baseY),
                           controlPoint1: NSPoint(x: 11, y: baseY - 3.5),
                           controlPoint2: NSPoint(x: 14, y: baseY - 3.5))
                path.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = waveIcon()

        let menu = NSMenu()
        statusLine = NSMenuItem(title: "starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Update Now", action: #selector(updateNow), keyEquivalent: "u")
        menu.addItem(withTitle: "Preview Frame", action: #selector(preview), keyEquivalent: "p")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SurfPixel", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem.menu = menu

        matrix.onStatus = { [weak self] text in
            guard let self else { return }
            self.statusLine.title = "\(text) · \(self.timeFmt.string(from: Date()))"
        }

        updateNow()
    }

    @objc private func updateNow() {
        let cfg = Config.load()
        statusLine.title = "fetching forecast…"
        Task { @MainActor in
            do {
                let cond = try await Forecast.fetch(config: cfg)
                let png = Renderer.render(cond, colors: cfg.colors, goodPeriodSeconds: cfg.display.goodPeriodSeconds ?? 8).pngData()
                matrix.namePrefix = cfg.display.deviceNamePrefix
                matrix.push(frame: png, brightness: cfg.display.brightness)
                statusItem.button?.toolTip = String(
                    format: "%@\n%.0f°C · wave %.1fm @ %.1fs",
                    cfg.location.name, cond.temperature, cond.waveHeight, cond.wavePeriod)
            } catch {
                statusLine.title = "forecast fetch failed · \(timeFmt.string(from: Date()))"
            }
            schedule(minutes: cfg.display.refreshMinutes)
        }
    }

    private func schedule(minutes: Int) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(max(1, minutes)) * 60,
                                     repeats: false) { [weak self] _ in
            self?.updateNow()
        }
    }

    @objc private func preview() {
        let cfg = Config.load()
        Task { @MainActor in
            do {
                let cond = try await Forecast.fetch(config: cfg)
                let png = Renderer.render(cond, colors: cfg.colors, goodPeriodSeconds: cfg.display.goodPeriodSeconds ?? 8).pngData(scale: 12)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("surfpixel_preview.png")
                try png.write(to: url)
                NSWorkspace.shared.open(url)
            } catch {
                statusLine.title = "preview failed"
            }
        }
    }

    @objc private func openSettings() {
        settings.populate()
        settings.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            statusLine.title = "login item change failed"
        }
    }
}

// headless mode for testing the renderer: SurfPixel --preview out.png
if let i = CommandLine.arguments.firstIndex(of: "--preview"),
   i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    let cfg = Config.load()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let cond = try await Forecast.fetch(config: cfg)
            let canvas = Renderer.render(cond, colors: cfg.colors, goodPeriodSeconds: cfg.display.goodPeriodSeconds ?? 8)
            try canvas.pngData().write(to: URL(fileURLWithPath: path))
            try canvas.pngData(scale: 12).write(
                to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "_big.png")))
            print("saved \(path)")
        } catch {
            print("error: \(error)")
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

// headless mode for docs: SurfPixel --settings-shot out.png
if let i = CommandLine.arguments.firstIndex(of: "--settings-shot"),
   i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    _ = NSApplication.shared
    NSApplication.shared.setActivationPolicy(.accessory)
    let wc = SettingsWindowController()
    wc.populate()
    let window = wc.window!
    let view = window.contentView!
    window.setContentSize(view.fittingSize)
    view.layoutSubtreeIfNeeded()
    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("saved \(path)")
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
app.run()
