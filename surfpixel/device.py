"""Push frames to the iDotMatrix over Bluetooth LE."""

import logging
import tempfile
from pathlib import Path

from idotmatrix import ConnectionManager
from idotmatrix.modules.common import Common
from idotmatrix.modules.image import Image as IdmImage
from PIL import Image

log = logging.getLogger(__name__)


async def scan() -> list[str]:
    return await ConnectionManager.scan()


class Display:
    def __init__(self, address: str | None = None):
        self.conn = ConnectionManager()
        self.address = address
        self._frame_path = Path(tempfile.gettempdir()) / "surfpixel_frame.png"
        self._mode_set = False

    async def connect(self) -> None:
        if self.address:
            await self.conn.connectByAddress(self.address)
        else:
            await self.conn.connectBySearch()
        if not self.conn.client or not self.conn.client.is_connected:
            raise ConnectionError(
                "no iDotMatrix device found — is it powered on and in range?"
            )

    async def set_brightness(self, percent: int) -> None:
        await Common().setBrightness(max(5, min(100, percent)))

    async def show(self, frame: Image.Image) -> None:
        frame.save(self._frame_path, format="PNG")
        image = IdmImage()
        if not self._mode_set:
            await image.setMode(1)  # DIY draw mode
            self._mode_set = True
        await image.uploadProcessed(str(self._frame_path), pixel_size=32)

    async def disconnect(self) -> None:
        await self.conn.disconnect()
