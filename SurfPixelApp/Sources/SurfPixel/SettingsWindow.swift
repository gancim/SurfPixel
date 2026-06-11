import AppKit

/// Settings window: location, refresh rate, brightness, period threshold,
/// and a color well for every element on the screen.
final class SettingsWindowController: NSWindowController {
    private let nameField = NSTextField()
    private let weatherLat = NSTextField()
    private let weatherLon = NSTextField()
    private let surfLat = NSTextField()
    private let surfLon = NSTextField()
    private let timezoneField = NSTextField()
    private let refreshField = NSTextField()
    private let goodPeriodField = NSTextField()
    private let brightnessSlider = NSSlider(value: 80, minValue: 5, maxValue: 100,
                                            target: nil, action: nil)

    private static let colorFields: [(key: String, label: String)] = [
        ("temp", "Temperature"), ("wind", "Wind"),
        ("wave", "Wave height"), ("wave_unit", "Wave unit"),
        ("period_good", "Period (good)"), ("period_bad", "Period (poor)"),
        ("arrow", "Swell arrow"), ("separator", "Separator"),
        ("tide", "Tide line"), ("tide_fill", "Tide fill"),
        ("tide_now", "Tide now dot"), ("rising", "Tide rising"),
        ("falling", "Tide falling"),
    ]
    private var colorWells: [String: NSColorWell] = [:]

    var onSave: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 0),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "SurfPixel Settings"
        self.init(window: window)
        buildUI()
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    private func pair(_ a: NSTextField, _ b: NSTextField) -> NSStackView {
        let stack = NSStackView(views: [a, b])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 250).isActive = true
        return stack
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func buildUI() {
        for f in [nameField, weatherLat, weatherLon, surfLat, surfLon,
                  timezoneField, refreshField, goodPeriodField] {
            f.translatesAutoresizingMaskIntoConstraints = false
        }

        let fieldsGrid = NSGridView(views: [
            [label("Spot name:"), nameField],
            [label("Weather lat, lon:"), pair(weatherLat, weatherLon)],
            [label("Surf lat, lon:"), pair(surfLat, surfLon)],
            [label("Timezone:"), timezoneField],
            [label("Refresh (minutes):"), refreshField],
            [label("Good period ≥ (s):"), goodPeriodField],
            [label("Brightness:"), brightnessSlider],
        ])
        fieldsGrid.rowSpacing = 8
        fieldsGrid.column(at: 0).xPlacement = .trailing
        fieldsGrid.column(at: 1).width = 250

        // colors: two label+well pairs per row
        var colorRows: [[NSView]] = []
        var current: [NSView] = []
        for (key, title) in Self.colorFields {
            let well = NSColorWell()
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 22).isActive = true
            colorWells[key] = well
            current.append(contentsOf: [label(title + ":"), well])
            if current.count == 4 {
                colorRows.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            while current.count < 4 { current.append(NSGridCell.emptyContentView) }
            colorRows.append(current)
        }
        let colorsGrid = NSGridView(views: colorRows)
        colorsGrid.rowSpacing = 8
        colorsGrid.columnSpacing = 10
        colorsGrid.column(at: 0).xPlacement = .trailing
        colorsGrid.column(at: 2).xPlacement = .trailing

        let save = NSButton(title: "Save & Update", target: self, action: #selector(save(_:)))
        save.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [
            fieldsGrid,
            sectionLabel("COLORS"),
            colorsGrid,
            buttons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(20, after: fieldsGrid)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = window!.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    private func nsColor(hex: String) -> NSColor {
        let rgb = RGB(hex: hex)
        return NSColor(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255,
                       blue: CGFloat(rgb.b) / 255, alpha: 1)
    }

    private func hexString(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02x%02x%02x",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// Fill the fields from the saved config. Call before showing the window.
    func populate() {
        let cfg = Config.load()
        nameField.stringValue = cfg.location.name
        weatherLat.stringValue = String(cfg.location.weather.lat)
        weatherLon.stringValue = String(cfg.location.weather.lon)
        surfLat.stringValue = String(cfg.location.surf.lat)
        surfLon.stringValue = String(cfg.location.surf.lon)
        timezoneField.stringValue = cfg.location.timezone
        refreshField.stringValue = String(cfg.display.refreshMinutes)
        goodPeriodField.stringValue = String(cfg.display.goodPeriodSeconds ?? 8)
        brightnessSlider.integerValue = cfg.display.brightness
        for (key, _) in Self.colorFields {
            let hex = cfg.colors[key] ?? Config.defaults.colors[key] ?? "#ffffff"
            colorWells[key]?.color = nsColor(hex: hex)
        }
    }

    @objc private func save(_ sender: Any?) {
        var cfg = Config.load()
        if !nameField.stringValue.isEmpty { cfg.location.name = nameField.stringValue }
        cfg.location.weather.lat = Double(weatherLat.stringValue) ?? cfg.location.weather.lat
        cfg.location.weather.lon = Double(weatherLon.stringValue) ?? cfg.location.weather.lon
        cfg.location.surf.lat = Double(surfLat.stringValue) ?? cfg.location.surf.lat
        cfg.location.surf.lon = Double(surfLon.stringValue) ?? cfg.location.surf.lon
        if TimeZone(identifier: timezoneField.stringValue) != nil {
            cfg.location.timezone = timezoneField.stringValue
        }
        cfg.display.refreshMinutes = max(1, Int(refreshField.stringValue) ?? cfg.display.refreshMinutes)
        cfg.display.goodPeriodSeconds = Double(goodPeriodField.stringValue)
            ?? cfg.display.goodPeriodSeconds ?? 8
        cfg.display.brightness = brightnessSlider.integerValue
        for (key, _) in Self.colorFields {
            if let well = colorWells[key] { cfg.colors[key] = hexString(well.color) }
        }
        Config.save(cfg)
        NSColorPanel.shared.close()
        close()
        onSave?()
    }

    @objc private func cancel(_ sender: Any?) {
        NSColorPanel.shared.close()
        close()
    }
}
