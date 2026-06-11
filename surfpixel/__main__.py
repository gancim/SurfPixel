"""surfpixel — local weather + surf forecast on an iDotMatrix 32x32.

Usage:
  python -m surfpixel                  run forever, refresh every N minutes
  python -m surfpixel --once           fetch, push one frame, exit
  python -m surfpixel --preview out.png  render to a PNG instead of the device
  python -m surfpixel --scan           list iDotMatrix devices in range
"""

import argparse
import asyncio
import logging
import sys
import time
from pathlib import Path

import yaml

from . import data, device, render

log = logging.getLogger("surfpixel")


def load_config(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def build_frame(cfg: dict):
    cond = data.fetch(cfg)
    log.info(
        "%.0f°C wmo=%s wind %.1fm/s | wave %.1fm @ %.1fs from %.0f° | tide idx %d",
        cond.temperature, cond.weather_code, cond.wind_speed,
        cond.wave_height, cond.wave_period, cond.wave_direction,
        cond.tide_now_index,
    )
    good_period = cfg.get("thresholds", {}).get("good_period_seconds", 8)
    return render.render(cond, cfg["colors"], good_period)


async def run(args, cfg: dict) -> None:
    disp = device.Display(cfg["display"].get("device_address"))
    await disp.connect()
    await disp.set_brightness(cfg["display"].get("brightness", 80))
    try:
        while True:
            try:
                await disp.show(build_frame(cfg))
            except Exception:
                log.exception("update failed, will retry next cycle")
            if args.once:
                return
            time.sleep(cfg["display"].get("refresh_minutes", 10) * 60)
    finally:
        await disp.disconnect()


def main() -> None:
    parser = argparse.ArgumentParser(prog="surfpixel", description=__doc__)
    parser.add_argument("--config", default=str(Path(__file__).parent.parent / "config.yaml"))
    parser.add_argument("--once", action="store_true", help="push one frame and exit")
    parser.add_argument("--preview", metavar="PNG", help="render to a PNG file instead of the device")
    parser.add_argument("--scan", action="store_true", help="list iDotMatrix devices and exit")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    if args.scan:
        found = asyncio.run(device.scan())
        print("\n".join(found) if found else "no iDotMatrix devices found")
        return

    cfg = load_config(args.config)

    if args.preview:
        frame = build_frame(cfg)
        frame.save(args.preview)
        big = frame.resize((32 * 12, 32 * 12), resample=0)
        big_path = Path(args.preview).with_stem(Path(args.preview).stem + "_big")
        big.save(big_path)
        print(f"saved {args.preview} (32x32) and {big_path} (scaled)")
        return

    try:
        asyncio.run(run(args, cfg))
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
