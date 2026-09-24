#!/usr/bin/env python3
"""Regenerate every app-icon resource from the official Krotak icon.

Source of truth: tools/krotak_icon_source.png (the supplied artwork, 1024x1024,
untouched apart from resizing). Run this only when the artwork changes; the
generated files are committed, so CI does not need to run it.

Generates:
  - assets/icon/app_icon.png            splash screen (rounded tile)
  - assets/icon/krotak_icon.b64         "About" card (base64 PNG)
  - mipmap-*/ic_launcher.png            legacy launcher icon (full artwork)
  - drawable-*/ic_launcher_art.png      adaptive-icon foreground (artwork fitted to the safe zone)
  - drawable-*/ic_launcher_mono_art.png white silhouette for Android 13 themed icons / status bar
  - drawable-*/ic_notif_large.png       large notification icon
"""
from __future__ import annotations

import base64
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools" / "krotak_icon_source.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# density: (legacy launcher px, adaptive layer px [108dp], notification px)
DENSITIES = {
    "mdpi": (48, 108, 96),
    "hdpi": (72, 162, 144),
    "xhdpi": (96, 216, 192),
    "xxhdpi": (144, 324, 288),
    "xxxhdpi": (192, 432, 384),
}

# The artwork is scaled to 92% inside the 108dp adaptive layer so the frame's
# corners are never clipped by circular launcher masks. The background layer
# uses the artwork's own flat colour, so the seam is invisible.
ADAPTIVE_SCALE = 0.92


def load_source() -> Image.Image:
    return Image.open(SOURCE).convert("RGB")


def resized(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)


def adaptive_layer(image: Image.Image, size: int, mode: str = "RGB") -> Image.Image:
    inner = int(round(size * ADAPTIVE_SCALE))
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    art = resized(image, inner).convert("RGBA")
    offset = (size - inner) // 2
    layer.paste(art, (offset, offset))
    return layer


def rounded_tile(image: Image.Image, size: int, radius_ratio: float = 0.22) -> Image.Image:
    scale = 4
    art = resized(image, size).convert("RGBA")
    mask = Image.new("L", (size * scale, size * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size * scale - 1, size * scale - 1),
        radius=int(size * scale * radius_ratio),
        fill=255,
    )
    mask = mask.resize((size, size), Image.Resampling.LANCZOS)
    art.putalpha(mask)
    return art


def monochrome(image: Image.Image) -> Image.Image:
    """White silhouette of the light artwork (frame, K, signal) on transparency."""
    rgb = image.convert("RGB")
    w, h = rgb.size
    bg = rgb.getpixel((6, 6))
    light = (247, 204, 190)  # colour of the artwork's light shapes
    lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    lo, hi = lum(bg) + 12, lum(light) - 12
    gray = rgb.convert("L")
    mask = gray.point(
        lambda v: 0 if v <= lo else (255 if v >= hi else int(255 * (v - lo) / (hi - lo)))
    )
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(mask)
    return out


def main() -> None:
    image = load_source()
    bg = image.getpixel((6, 6))
    mono = monochrome(image)

    save_png(rounded_tile(image, 512), ROOT / "assets" / "icon" / "app_icon.png")

    about = BytesIO()
    resized(image, 192).save(about, "PNG", optimize=True)
    (ROOT / "assets" / "icon" / "krotak_icon.b64").write_text(
        base64.b64encode(about.getvalue()).decode("ascii"), encoding="ascii"
    )

    for density, (launcher, layer, notif) in DENSITIES.items():
        save_png(resized(image, launcher), RES / f"mipmap-{density}" / "ic_launcher.png")
        save_png(adaptive_layer(image, layer), RES / f"drawable-{density}" / "ic_launcher_art.png")
        save_png(adaptive_layer(mono, layer), RES / f"drawable-{density}" / "ic_launcher_mono_art.png")
        save_png(resized(image, notif), RES / f"drawable-{density}" / "ic_notif_large.png")

    (RES / "drawable" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- خلفية الأيقونة المتكيّفة — نفس لون خلفية الأيقونة الرسمية -->\n"
        '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:shape="rectangle">\n'
        f'    <solid android:color="#{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}" />\n'
        "</shape>\n",
        encoding="utf-8",
    )
    print("Applied official Krotak icon. background =", "#%02X%02X%02X" % bg)


if __name__ == "__main__":
    main()
