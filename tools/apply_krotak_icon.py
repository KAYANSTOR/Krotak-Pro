#!/usr/bin/env python3
"""Apply the approved Krotak launcher icon to Flutter/Android resources."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "icon" / "krotak_icon.png"
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
    image.resize((size, size), Image.Resampling.LANCZOS).save(path, "PNG", optimize=True)


def main() -> None:
    image = Image.open(SOURCE).convert("RGBA")
    save_png(image, ROOT / "assets" / "icon" / "app_icon.png", 192)

    for density, (launcher_size, art_size, notif_size) in DENSITIES.items():
        save_png(image, RES / f"mipmap-{density}" / "ic_launcher.png", launcher_size)
        save_png(image, RES / f"drawable-{density}" / "ic_launcher_art.png", art_size)
        save_png(image, RES / f"drawable-{density}" / "ic_notif_large.png", notif_size)

    # The existing generated monochrome art remains transparent and suitable
    # for Android 13 themed icons; only the full-colour launcher art is replaced.
    (RES / "drawable" / "ic_launcher_foreground.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<bitmap xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:src="@drawable/ic_launcher_art"\n'
        '    android:gravity="center" />\n',
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
