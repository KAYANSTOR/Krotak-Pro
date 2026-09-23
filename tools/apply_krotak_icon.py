#!/usr/bin/env python3
"""Apply the supplied Krotak launcher artwork to Flutter and Android resources."""
import base64
from io import BytesIO
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE_B64 = ROOT / "tools" / "krotak_icon.jpg.b64"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

DENSITIES = {
    "mdpi": (48, 108, 96),
    "hdpi": (72, 162, 144),
    "xhdpi": (96, 216, 192),
    "xxhdpi": (144, 324, 288),
    "xxxhdpi": (192, 432, 384),
}


def save_png(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(
        path, "PNG", optimize=True
    )


def load_source_image() -> Image.Image:
    encoded = "".join(SOURCE_B64.read_text(encoding="utf-8").split())
    if not encoded:
        raise RuntimeError(f"Icon source is empty: {SOURCE_B64}")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except Exception as exc:
        raise RuntimeError("Icon source Base64 is invalid") from exc
    image = Image.open(BytesIO(raw))
    image.load()
    return image.convert("RGBA")


def main() -> None:
    image = load_source_image()

    # Flutter settings -> About App icon.
    save_png(image, ROOT / "assets" / "icon" / "app_icon.png", 192)

    # Android launcher + notification resources.
    for density, (launcher_size, art_size, notif_size) in DENSITIES.items():
        save_png(image, RES / f"mipmap-{density}" / "ic_launcher.png", launcher_size)
        save_png(image, RES / f"drawable-{density}" / "ic_launcher_art.png", art_size)
        save_png(image, RES / f"drawable-{density}" / "ic_notif_large.png", notif_size)

    # Adaptive-icon foreground points to the generated full-colour artwork.
    (RES / "drawable" / "ic_launcher_foreground.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<bitmap xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:src="@drawable/ic_launcher_art"\n'
        '    android:gravity="center" />\n',
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
