"""Render a 32x32 frame: small weather strip on top, big wave info in the
middle, tide curve across the bottom."""

from PIL import Image

from .data import Conditions

SIZE = 32

# --- tiny pixel fonts -------------------------------------------------------
# Each glyph is a list of row strings; "1" = lit pixel. Widths may vary.

FONT_SMALL = {  # 5 rows tall
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
}

FONT_BIG = {  # 7 rows tall, for the wave height
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
}

# wave glyph used as the "period" label
WAVES = ["00000", "01010", "10101", "00000", "00000"]

# 5x5 weather icons; "1" = primary color, "2" = secondary color
ICONS = {
    "sun": (["00100", "01110", "11111", "01110", "00100"], "#ffd000", None),
    "partly": (["11000", "11220", "02222", "22222", "00000"], "#ffd000", "#9aa7b0"),
    "cloud": (["00000", "01110", "11111", "11111", "00000"], "#9aa7b0", None),
    "rain": (["01110", "11111", "00000", "20202", "02020"], "#9aa7b0", "#3399ff"),
    "snow": (["01110", "11111", "00000", "20202", "00000"], "#9aa7b0", "#ffffff"),
    "storm": (["01110", "11111", "00220", "02200", "00200"], "#9aa7b0", "#ffd000"),
    "fog": (["11111", "00000", "11111", "00000", "11111"], "#667077", None),
}

# arrow pointing up, 5x5; other directions are derived by rotation/flips
ARROW_N = ["00100", "01110", "10101", "00100", "00100"]
ARROW_NE = ["00111", "00011", "00101", "01000", "10000"]


def icon_for_wmo(code: int) -> str:
    if code in (0, 1):
        return "sun"
    if code == 2:
        return "partly"
    if code == 3:
        return "cloud"
    if code in (45, 48):
        return "fog"
    if code in (71, 73, 75, 77, 85, 86):
        return "snow"
    if code >= 95:
        return "storm"
    if code >= 51:
        return "rain"
    return "sun"


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def _rotate(glyph: list[str]) -> list[str]:
    """Rotate a square glyph 90 degrees clockwise."""
    return ["".join(glyph[len(glyph) - 1 - c][r] for c in range(len(glyph)))
            for r in range(len(glyph))]


def arrow_for(degrees: float) -> list[str]:
    """5x5 arrow pointing in the given compass direction (0 = north/up)."""
    octant = int(((degrees % 360) + 22.5) // 45) % 8
    base = ARROW_N if octant % 2 == 0 else ARROW_NE
    glyph = base
    for _ in range(octant // 2):
        glyph = _rotate(glyph)
    return glyph


def draw_glyph(px, x: int, y: int, glyph: list[str], color, color2=None) -> int:
    for dy, row in enumerate(glyph):
        for dx, ch in enumerate(row):
            if ch == "0":
                continue
            if 0 <= x + dx < SIZE and 0 <= y + dy < SIZE:
                px[x + dx, y + dy] = color2 if (ch == "2" and color2) else color
    return len(glyph[0])


def draw_text(px, x: int, y: int, text: str, color, font=FONT_SMALL) -> int:
    cx = x
    for ch in text:
        glyph = font.get(ch)
        if glyph is None:
            continue
        cx += draw_glyph(px, cx, y, glyph, color) + 1
    return cx - x - 1


def text_width(text: str, font=FONT_SMALL) -> int:
    widths = [len(font[ch][0]) for ch in text if ch in font]
    return sum(widths) + max(0, len(widths) - 1)


def render(cond: Conditions, colors: dict, good_period_seconds: float = 8.0) -> Image.Image:
    c = {k: hex_to_rgb(v) for k, v in colors.items()}
    img = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    px = img.load()

    # --- top strip (rows 0-4): weather icon, temperature, wind m/s ---------
    glyph, primary, secondary = ICONS[icon_for_wmo(cond.weather_code)]
    draw_glyph(px, 0, 0, glyph, hex_to_rgb(primary),
               hex_to_rgb(secondary) if secondary else None)
    draw_text(px, 7, 0, f"{round(cond.temperature)}°", c["temp"])
    # wind: speed + arrow showing where the wind blows TO (source + 180)
    wind = str(round(cond.wind_speed))
    draw_glyph(px, SIZE - 5, 0, arrow_for(cond.wind_direction + 180), c["wind"])
    draw_text(px, SIZE - 6 - text_width(wind), 0, wind, c["wind"])

    for x in range(SIZE):  # separator
        px[x, 6] = c["separator"]

    # --- wave block (rows 8-14): big height + unit + direction arrow -------
    height = f"{cond.wave_height:.1f}"
    w = draw_text(px, 0, 8, height, c["wave"], FONT_BIG)
    draw_text(px, w + 2, 10, "m", c["wave_unit"])
    # arrow shows where the swell is travelling TO (source direction + 180)
    draw_glyph(px, SIZE - 5, 9, arrow_for(cond.wave_direction + 180), c["arrow"])

    # --- period line (rows 16-20), green = good swell, red = poor -----------
    good = cond.wave_period >= good_period_seconds
    period_color = c.get("period_good" if good else "period_bad",
                         hex_to_rgb("#00ff66" if good else "#ff5050"))
    draw_glyph(px, 0, 16, WAVES, period_color)
    draw_text(px, 7, 16, f"{cond.wave_period:.1f}s", period_color)
    # tide trend triangle at the right end of the period line
    lv = cond.tide_levels
    i = cond.tide_now_index
    rising = i + 1 < len(lv) and lv[i + 1] >= lv[i]
    if rising:
        draw_glyph(px, SIZE - 5, 17, ["00100", "01110", "11111"], c["rising"])
    else:
        draw_glyph(px, SIZE - 5, 17, ["11111", "01110", "00100"], c["falling"])

    # --- tide curve (rows 22-31), one column per hour -----------------------
    top, bottom = 22, 31
    levels = cond.tide_levels
    lo, hi = min(levels), max(levels)
    span = (hi - lo) or 1.0
    for x in range(min(SIZE, len(levels))):
        y = bottom - round((levels[x] - lo) / span * (bottom - top))
        for fy in range(y + 1, bottom + 1):
            px[x, fy] = c["tide_fill"]
        px[x, y] = c["tide"]
    # "now" marker: dotted white line from the bottom edge up to the curve
    nx = min(cond.tide_now_index, len(levels) - 1)
    ny = bottom - round((levels[nx] - lo) / span * (bottom - top))
    for my in range(bottom, ny, -2):
        px[nx, my] = c["tide_now"]
    px[nx, ny] = c["tide_now"]

    return img
