import Foundation

struct Conditions {
    var temperature: Double      // °C
    var weatherCode: Int         // WMO code
    var windSpeed: Double        // m/s
    var windDirection: Double    // degrees, direction wind comes FROM
    var waveHeight: Double       // m
    var wavePeriod: Double       // s
    var waveDirection: Double    // degrees, direction waves come FROM
    var tideLevels: [Double]     // hourly sea level, window around now
    var tideNowIndex: Int        // index of the current hour in tideLevels
}

enum Forecast {
    struct WeatherResponse: Codable {
        struct Current: Codable {
            let temperature_2m: Double
            let weather_code: Int
        }
        let current: Current
    }

    struct WindResponse: Codable {
        struct Current: Codable {
            let wind_speed_10m: Double
            let wind_direction_10m: Double
        }
        let current: Current
    }

    struct MarineResponse: Codable {
        struct Hourly: Codable {
            let time: [String]
            let wave_height: [Double?]
            let wave_period: [Double?]
            let wave_direction: [Double?]
            let sea_level_height_msl: [Double?]
        }
        let hourly: Hourly
    }

    // never serve cached responses; forecasts must be fetched fresh
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// Fetch with retries. Each round tries URLSession, then `curl --http1.1`:
    /// some VPN middleboxes abort TLS handshakes that offer HTTP/2 in ALPN
    /// (which URLSession always does and cannot be told not to), and the
    /// interference can be intermittent, so back off and try again.
    private static func fetchData(_ url: URL, rounds: Int = 3) async throws -> Data {
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for round in 0..<rounds {
            if round > 0 {
                try await Task.sleep(nanoseconds: UInt64(round) * 3_000_000_000)
            }
            do {
                return try await session.data(from: url).0
            } catch {
                lastError = error
                log.warning("URLSession failed round \(round) (\(error.localizedDescription)), trying HTTP/1.1")
            }
            do {
                return try await curlHTTP1(url)
            } catch {
                lastError = error
                log.warning("curl HTTP/1.1 failed round \(round)")
            }
        }
        throw lastError
    }

    private static func curlHTTP1(_ url: URL) async throws -> Data {
        try await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            proc.arguments = ["--http1.1", "-fsS", "--max-time", "20", url.absoluteString]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0, !data.isEmpty else {
                throw URLError(.cannotLoadFromNetwork)
            }
            return data
        }.value
    }

    static func fetch(config: Config) async throws -> Conditions {
        var weatherURL = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        weatherURL.queryItems = [
            .init(name: "latitude", value: String(config.location.weather.lat)),
            .init(name: "longitude", value: String(config.location.weather.lon)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "timezone", value: config.location.timezone),
        ]
        // wind comes from the surf point: the weather point's grid cell is
        // inland, where land friction underreports the wind at the lineup
        let windUnit = ["ms", "kn", "kmh", "mph"].contains(config.display.windUnit ?? "")
            ? config.display.windUnit! : "ms"
        var windURL = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        windURL.queryItems = [
            .init(name: "latitude", value: String(config.location.surf.lat)),
            .init(name: "longitude", value: String(config.location.surf.lon)),
            .init(name: "current", value: "wind_speed_10m,wind_direction_10m"),
            .init(name: "wind_speed_unit", value: windUnit),
            .init(name: "timezone", value: config.location.timezone),
        ]
        var marineURL = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
        marineURL.queryItems = [
            .init(name: "latitude", value: String(config.location.surf.lat)),
            .init(name: "longitude", value: String(config.location.surf.lon)),
            .init(name: "hourly", value: "wave_height,wave_period,wave_direction,sea_level_height_msl"),
            .init(name: "forecast_days", value: "3"),
            .init(name: "timezone", value: config.location.timezone),
        ]

        let wURL = weatherURL.url!, dURL = windURL.url!, mURL = marineURL.url!
        async let weatherData = fetchData(wURL)
        async let windData = fetchData(dURL)
        async let marineData = fetchData(mURL)
        let weather = try JSONDecoder().decode(WeatherResponse.self, from: await weatherData).current
        let wind = try JSONDecoder().decode(WindResponse.self, from: await windData).current
        let marine = try JSONDecoder().decode(MarineResponse.self, from: await marineData).hourly

        // index of the current hour in the marine hourly series
        let fmt = DateFormatter()
        // POSIX locale + Gregorian: without these, a system set to a
        // non-Gregorian calendar produces a key that never matches the API's
        // timestamps, silently falling back to index 0 (midnight data)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM-dd'T'HH:00"
        fmt.timeZone = TimeZone(identifier: config.location.timezone)
        let idx = marine.time.firstIndex(of: fmt.string(from: Date())) ?? 0

        // tide window: 3 hours back, 28 ahead -> 32 columns, one per hour
        let start = max(0, idx - 3)
        let end = min(start + 32, marine.sea_level_height_msl.count)
        let levels = marine.sea_level_height_msl[start..<end].map { $0 ?? 0 }

        return Conditions(
            temperature: weather.temperature_2m,
            weatherCode: weather.weather_code,
            windSpeed: wind.wind_speed_10m,
            windDirection: wind.wind_direction_10m,
            waveHeight: marine.wave_height[idx] ?? 0,
            wavePeriod: marine.wave_period[idx] ?? 0,
            waveDirection: marine.wave_direction[idx] ?? 0,
            tideLevels: Array(levels),
            tideNowIndex: idx - start
        )
    }
}
