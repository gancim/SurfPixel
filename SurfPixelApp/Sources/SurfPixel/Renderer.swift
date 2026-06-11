import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGB {
    var r: UInt8, g: UInt8, b: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    init(hex: String) {
        var v = hex
        if v.hasPrefix("#") { v.removeFirst() }
        let n = UInt32(v, radix: 16) ?? 0
        self.init(UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF))
    }
}

final class Canvas {
    static let size = 32
    private var buf: [UInt8]

    init() {
        buf = [UInt8](repeating: 0, count: Canvas.size * Canvas.size * 4)
        for i in 0..<(Canvas.size * Canvas.size) { buf[i * 4 + 3] = 255 }
    }

    func set(_ x: Int, _ y: Int, _ c: RGB) {
        guard x >= 0, x < Canvas.size, y >= 0, y < Canvas.size else { return }
        let i = (y * Canvas.size + x) * 4
        buf[i] = c.r
        buf[i + 1] = c.g
        buf[i + 2] = c.b
    }

    func cgImage(scale: Int = 1) -> CGImage {
        let provider = CGDataProvider(data: Data(buf) as CFData)!
        let img = CGImage(
            width: Canvas.size, height: Canvas.size,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: Canvas.size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
        guard scale > 1 else { return img }
        let s = Canvas.size * scale
        let ctx = CGContext(
            data: nil, width: s, height: s,
            bitsPerComponent: 8, bytesPerRow: s * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: s, height: s))
        return ctx.makeImage()!
    }

    func pngData(scale: Int = 1) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage(scale: scale), nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}

// MARK: - tiny pixel fonts. "1" = lit pixel; widths may vary per glyph.

let fontSmall: [Character: [String]] = [  // 5 rows tall
    "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"],
    "7": ["111", "001", "001", "010", "010"],
    "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"],
    "-": ["000", "000", "111", "000", "000"],
    ".": ["0", "0", "0", "0", "1"],
    "°": ["11", "11", "00", "00", "00"],
    "m": ["000", "000", "111", "101", "101"],
    "s": ["011", "100", "010", "001", "110"],
    " ": ["00", "00", "00", "00", "00"],
]

let fontBig: [Character: [String]] = [  // 7 rows tall, for the wave height
    "0": ["0110", "1001", "1001", "1001", "1001", "1001", "0110"],
    "1": ["0010", "0110", "0010", "0010", "0010", "0010", "0111"],
    "2": ["0110", "1001", "0001", "0010", "0100", "1000", "1111"],
    "3": ["1110", "0001", "0001", "0110", "0001", "0001", "1110"],
    "4": ["1001", "1001", "1001", "1111", "0001", "0001", "0001"],
    "5": ["1111", "1000", "1110", "0001", "0001", "1001", "0110"],
    "6": ["0110", "1000", "1110", "1001", "1001", "1001", "0110"],
    "7": ["1111", "0001", "0010", "0010", "0100", "0100", "0100"],
    "8": ["0110", "1001", "1001", "0110", "1001", "1001", "0110"],
    "9": ["0110", "1001", "1001", "0111", "0001", "0001", "0110"],
    ".": ["0", "0", "0", "0", "0", "0", "1"],
]

// wave glyph used as the "period" label
let wavesGlyph = ["00000", "01010", "10101", "00000", "00000"]

// 5x5 weather icons; "1" = primary color, "2" = secondary color
let icons: [String: (glyph: [String], primary: String, secondary: String?)] = [
    "sun": (["00100", "01110", "11111", "01110", "00100"], "#ffd000", nil),
    "partly": (["11000", "11220", "02222", "22222", "00000"], "#ffd000", "#9aa7b0"),
    "cloud": (["00000", "01110", "11111", "11111", "00000"], "#9aa7b0", nil),
    "rain": (["01110", "11111", "00000", "20202", "02020"], "#9aa7b0", "#3399ff"),
    "snow": (["01110", "11111", "00000", "20202", "00000"], "#9aa7b0", "#ffffff"),
    "storm": (["01110", "11111", "00220", "02200", "00200"], "#9aa7b0", "#ffd000"),
    "fog": (["11111", "00000", "11111", "00000", "11111"], "#667077", nil),
]

// arrow pointing up, 5x5; other directions derived by rotation
let arrowN = ["00100", "01110", "10101", "00100", "00100"]
let arrowNE = ["00111", "00011", "00101", "01000", "10000"]

enum Renderer {
    static func iconForWMO(_ code: Int) -> String {
        switch code {
        case 0, 1: return "sun"
        case 2: return "partly"
        case 3: return "cloud"
        case 45, 48: return "fog"
        case 71, 73, 75, 77, 85, 86: return "snow"
        case 95...: return "storm"
        case 51...: return "rain"
        default: return "sun"
        }
    }

    /// Rotate a square glyph 90 degrees clockwise.
    static func rotate(_ glyph: [String]) -> [String] {
        let g = glyph.map(Array.init)
        let n = g.count
        return (0..<n).map { r in String((0..<n).map { c in g[n - 1 - c][r] }) }
    }

    /// 5x5 arrow pointing in the given compass direction (0 = north/up).
    static func arrow(for degrees: Double) -> [String] {
        let octant = Int((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45) % 8
        var glyph = octant % 2 == 0 ? arrowN : arrowNE
        for _ in 0..<(octant / 2) { glyph = rotate(glyph) }
        return glyph
    }

    @discardableResult
    static func drawGlyph(_ c: Canvas, _ x: Int, _ y: Int, _ glyph: [String],
                          _ color: RGB, _ color2: RGB? = nil) -> Int {
        for (dy, row) in glyph.enumerated() {
            for (dx, ch) in row.enumerated() {
                if ch == "0" { continue }
                c.set(x + dx, y + dy, ch == "2" ? (color2 ?? color) : color)
            }
        }
        return glyph[0].count
    }

    @discardableResult
    static func drawText(_ c: Canvas, _ x: Int, _ y: Int, _ text: String,
                         _ color: RGB, font: [Character: [String]] = fontSmall) -> Int {
        var cx = x
        for ch in text {
            guard let glyph = font[ch] else { continue }
            cx += drawGlyph(c, cx, y, glyph, color) + 1
        }
        return cx - x - 1
    }

    static func textWidth(_ text: String, font: [Character: [String]] = fontSmall) -> Int {
        let widths = text.compactMap { font[$0]?[0].count }
        return widths.reduce(0, +) + max(0, widths.count - 1)
    }

    static func render(_ cond: Conditions, colors: [String: String],
                       goodPeriodSeconds: Double = 8) -> Canvas {
        func col(_ key: String) -> RGB { RGB(hex: colors[key] ?? "#ffffff") }
        let c = Canvas()
        let size = Canvas.size

        // --- top strip (rows 0-4): weather icon, temperature, wind m/s ----
        let icon = icons[iconForWMO(cond.weatherCode)]!
        drawGlyph(c, 0, 0, icon.glyph, RGB(hex: icon.primary),
                  icon.secondary.map { RGB(hex: $0) })
        drawText(c, 7, 0, "\(Int(cond.temperature.rounded()))°", col("temp"))
        // wind: speed + arrow showing where the wind blows TO (source + 180)
        let wind = "\(Int(cond.windSpeed.rounded()))"
        drawGlyph(c, size - 5, 0, arrow(for: cond.windDirection + 180), col("wind"))
        drawText(c, size - 6 - textWidth(wind), 0, wind, col("wind"))

        for x in 0..<size { c.set(x, 6, col("separator")) }  // separator

        // --- wave block (rows 8-14): big height + unit + direction arrow --
        let height = String(format: "%.1f", cond.waveHeight)
        let w = drawText(c, 0, 8, height, col("wave"), font: fontBig)
        drawText(c, w + 2, 10, "m", col("wave_unit"))
        // arrow shows where the swell is travelling TO (source + 180)
        drawGlyph(c, size - 5, 9, arrow(for: cond.waveDirection + 180), col("arrow"))

        // --- period line (rows 16-20), green = good swell, red = poor -------
        let good = cond.wavePeriod >= goodPeriodSeconds
        let periodColor = RGB(hex: colors[good ? "period_good" : "period_bad"]
            ?? (good ? "#00ff66" : "#ff5050"))
        drawGlyph(c, 0, 16, wavesGlyph, periodColor)
        drawText(c, 7, 16, String(format: "%.1fs", cond.wavePeriod), periodColor)

        // --- tide curve (rows 22-31), one column per hour -------------------
        let top = 22, bottom = 31
        let levels = cond.tideLevels
        guard !levels.isEmpty else { return c }
        let lo = levels.min()!, hi = levels.max()!
        let span = (hi - lo) == 0 ? 1.0 : hi - lo
        func curveY(_ i: Int) -> Int {
            bottom - Int(((levels[i] - lo) / span * Double(bottom - top)).rounded())
        }
        for x in 0..<min(size, levels.count) {
            let y = curveY(x)
            for fy in stride(from: y + 1, through: bottom, by: 1) {
                c.set(x, fy, col("tide_fill"))
            }
            c.set(x, y, col("tide"))
        }
        // "now" marker: dotted white line from the bottom edge up to the curve
        let nx = min(cond.tideNowIndex, levels.count - 1)
        let ny = curveY(nx)
        var my = bottom
        while my > ny {
            c.set(nx, my, col("tide_now"))
            my -= 2
        }
        c.set(nx, ny, col("tide_now"))
        // tide trend triangle, top-right of the band: ▲ rising / ▼ falling
        let i = cond.tideNowIndex
        let rising = i + 1 < levels.count && levels[i + 1] >= levels[i]
        if rising {
            drawGlyph(c, size - 5, top + 1, ["00100", "01110", "11111"], col("rising"))
        } else {
            drawGlyph(c, size - 5, top + 1, ["11111", "01110", "00100"], col("falling"))
        }

        return c
    }
}
