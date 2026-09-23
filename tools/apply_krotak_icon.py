#!/usr/bin/env python3
"""Apply the official Krotak launcher artwork to Flutter and Android resources.

Source of truth: tools/krotak_icon.jpg.b64 (the supplied official icon).
Generates:
  - assets/icon/app_icon.png
  - mipmap-*/ic_launcher.png
  - drawable-*/ic_launcher_art.png
  - drawable-*/ic_launcher_mono_art.png (white silhouette for Android 13 themed icons)
  - drawable-*/ic_notif_large.png
"""
from __future__ import annotations

import base64
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageFilter

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


def make_monochrome(image: Image.Image) -> Image.Image:
    """White silhouette of the logo for Android themed icons."""
    pixels = image.load()
    w, h = image.size
    samples = [
        pixels[2, 2][:3],
        pixels[w - 3, 2][:3],
        pixels[2, h - 3][:3],
        pixels[w - 3, h - 3][:3],
    ]
    bg = tuple(sum(c[i] for c in samples) // 4 for i in range(3))

    def dist(a, b):
        return sum((a[i] - b[i]) ** 2 for i in range(3)) ** 0.5

    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    for y in range(h):
        for x in range(w):
            r, g, b, _ = pixels[x, y]
            d = dist((r, g, b), bg)
            if d > 28:
                mp[x, y] = min(255, int(d * 2.2))
    mask = mask.filter(ImageFilter.GaussianBlur(radius=0.8))

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    mp = mask.load()
    for y in range(h):
        for x in range(w):
            a = mp[x, y]
            if a > 10:
                op[x, y] = (255, 255, 255, a)
    return out


def main() -> None:
    image = load_source_image()
    mono = make_monochrome(image)

    # Flutter settings / splash
    save_png(image, ROOT / "assets" / "icon" / "app_icon.png", 192)

    for density, (launcher_size, art_size, notif_size) in DENSITIES.items():
        save_png(image, RES / f"mipmap-{density}" / "ic_launcher.png", launcher_size)
        save_png(image, RES / f"drawable-{density}" / "ic_launcher_art.png", art_size)
        save_png(mono, RES / f"drawable-{density}" / "ic_launcher_mono_art.png", art_size)
        save_png(image, RES / f"drawable-{density}" / "ic_notif_large.png", notif_size)

    (RES / "drawable" / "ic_launcher_foreground.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<bitmap xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:src="@drawable/ic_launcher_art"\n'
        '    android:gravity="center" />\n',
        encoding="utf-8",
    )
    print("Applied official Krotak icon to Flutter + Android resources.")


if __name__ == "__main__":
    main()
