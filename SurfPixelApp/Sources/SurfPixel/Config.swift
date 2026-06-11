import Foundation

struct Config: Codable {
    struct Point: Codable { var lat: Double; var lon: Double }
    struct Location: Codable {
        var name: String
        var weather: Point
        var surf: Point
        var timezone: String
    }
    struct Display: Codable {
        var brightness: Int
        var refreshMinutes: Int
        var deviceNamePrefix: String
        // period >= this many seconds renders green, below it red
        var goodPeriodSeconds: Double?
    }

    var location: Location
    var display: Display
    var colors: [String: String]

    static let defaults = Config(
        location: .init(
            name: "Chisan (Hamasuka, Chigasaki)",
            weather: .init(lat: 35.326, lon: 139.418),
            surf: .init(lat: 35.30, lon: 139.42),
            timezone: "Asia/Tokyo"
        ),
        display: .init(brightness: 80, refreshMinutes: 10, deviceNamePrefix: "IDM-",
                       goodPeriodSeconds: 8),
        colors: [
            "temp": "#ffb000",
            "wind": "#9aa7b0",
            "wave": "#00c8ff",
            "wave_unit": "#0077a8",
            "period_good": "#00ff66",
            "period_bad": "#ff5050",
            "arrow": "#00c8ff",
            "tide": "#00e08c",
            "tide_fill": "#00482c",
            "tide_now": "#ffffff",
            "rising": "#00ff66",
            "falling": "#ff5050",
            "separator": "#1c1c28",
        ]
    )

    static var fileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SurfPixel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    /// Load from Application Support, writing the default config on first run.
    static func load() -> Config {
        if let data = try? Data(contentsOf: fileURL),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        save(defaults)
        return defaults
    }

    static func save(_ cfg: Config) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cfg) {
            try? data.write(to: fileURL)
        }
    }
}
