"""Fetch weather, wave and tide data from Open-Meteo (no API key required)."""

from dataclasses import dataclass
from datetime import datetime
from zoneinfo import ZoneInfo

import requests

WEATHER_URL = "https://api.open-meteo.com/v1/forecast"
MARINE_URL = "https://marine-api.open-meteo.com/v1/marine"


@dataclass
class Conditions:
    # weather
    temperature: float        # °C
    weather_code: int         # WMO code
    wind_speed: float         # m/s
    wind_direction: float     # degrees, direction wind comes FROM
    # surf
    wave_height: float        # m
    wave_period: float        # s
    wave_direction: float     # degrees, direction waves come FROM
    # tide: hourly sea level for a window around now, 1 value per hour
    tide_levels: list[float]
    tide_now_index: int       # index of the current hour inside tide_levels
    fetched_at: datetime


def fetch(cfg: dict) -> Conditions:
    loc = cfg["location"]
    tz = ZoneInfo(loc["timezone"])
    now = datetime.now(tz)

    weather = requests.get(
        WEATHER_URL,
        params={
            "latitude": loc["weather"]["lat"],
            "longitude": loc["weather"]["lon"],
            "current": "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m",
            "wind_speed_unit": "ms",
            "timezone": loc["timezone"],
        },
        timeout=15,
    )
    weather.raise_for_status()
    cur = weather.json()["current"]

    marine = requests.get(
        MARINE_URL,
        params={
            "latitude": loc["surf"]["lat"],
            "longitude": loc["surf"]["lon"],
            "hourly": "wave_height,wave_period,wave_direction,sea_level_height_msl",
            "forecast_days": 3,
            "timezone": loc["timezone"],
        },
        timeout=15,
    )
    marine.raise_for_status()
    hourly = marine.json()["hourly"]

    # find the index of the current hour in the marine hourly series
    hour_key = now.strftime("%Y-%m-%dT%H:00")
    try:
        idx = hourly["time"].index(hour_key)
    except ValueError:
        idx = 0

    # tide window: 3 hours back, 28 ahead -> 32 columns, one per hour
    start = max(0, idx - 3)
    levels = hourly["sea_level_height_msl"][start : start + 32]
    levels = [v if v is not None else 0.0 for v in levels]

    return Conditions(
        temperature=cur["temperature_2m"],
        weather_code=cur["weather_code"],
        wind_speed=cur["wind_speed_10m"],
        wind_direction=cur["wind_direction_10m"],
        wave_height=hourly["wave_height"][idx] or 0.0,
        wave_period=hourly["wave_period"][idx] or 0.0,
        wave_direction=hourly["wave_direction"][idx] or 0.0,
        tide_levels=levels,
        tide_now_index=idx - start,
        fetched_at=now,
    )
