#!/usr/bin/env python3
"""يولّد أيقونة تطبيق «كروتك» بكل الصيغ المطلوبة بدون مكتبات خارجية.

السبب: بيئة البناء لا تحتوي Pillow أو ImageMagick، بينما Android يحتاج:

1. `mipmap-<density>/ic_launcher.png` — أيقونة كاملة (خلفية + رسم) للأجهزة
   الأقدم من API 26، مقصوصة بحواف دائرية.
2. `drawable-<density>/ic_launcher_art.png` — الرسم فقط بخلفية شفافة، وهو
   الطبقة الأمامية للأيقونة المتكيّفة (`ic_launcher_foreground.xml`) وأيقونة
   الثيم (`ic_launcher_monochrome.xml`). يجب توفيره لكل الكثافات وإلا كبّر
   Android نسخة mdpi وأصبحت ضبابية على الأجهزة الحديثة.
3. `drawable-<density>/ic_launcher_mono_art.png` — أيقونة الثيم (Android 13+):
   حدود البطاقة الأمامية + حرف K فقط، بلون أبيض وشفافية، فيلوّنها النظام.
4. `drawable-<density>/ic_notif_large.png` — أيقونة كبيرة لإشعار المخزون الحي
   (لا يمكن استخدام `@mipmap/ic_launcher` لأنه أيقونة متكيّفة XML لا تُفكّ كصورة).
5. `assets/icon/app_icon.png` — الأيقونة الكاملة داخل شاشة «عن التطبيق».

التصميم الجديد (بديل كامل للتصميم السابق «N»):
خلفية داكنة تتدرّج إلى تراكوطة دافئة، بطاقتان متراكبتان (بطاقة خلفية بلون
الهوية + بطاقة أمامية لؤلؤية)، وبداخلها مونوغرام «K» بخطّين: عمود وقاعدة
بلون الهوية الداكن، وضلع صاعد ذهبي — يجمع هوية الكروت والإشارة/الشبكة في
رمز واحد مقروء حتى في أصغر حجم (48px).

الاستخدام:  python3 tools/generate_launcher_icons.py
"""

import math
import os
import struct
import zlib

# ---------------------------------------------------------------------------
# لوحة الألوان (هوية كروتك: داكن → تراكوطة + ذهب دافئ)
# ---------------------------------------------------------------------------
BG_STOPS = [
    (0.00, (0x1F, 0x1F, 0x1F)),  # Dark base
    (0.50, (0xB8, 0x5C, 0x3E)),  # Primary Dark
    (1.00, (0xD9, 0x77, 0x57)),  # Primary
]
GLOW = (0xF7, 0xF4, 0xEF)          # وهج دافئ خفيف
GOLD = (0xB8, 0x95, 0x3A)          # ذهب دافئ
TEAL_DEEP = (0xB8, 0x5C, 0x3E)     # خط المونوغرام (Primary Dark)
BACK_CARD = (0xD9, 0x77, 0x57)     # البطاقة الخلفية (Primary)
PEARL = (255, 255, 255)            # البطاقة الأمامية

# المرجع: viewport 108×108 (نفس نظام الأيقونة المتكيّفة في Android).
VIEWPORT = 108.0

# البطاقة الخلفية (متراكبة أعلى-يسار)
BACK = (26.0, 26.0, 68.0, 68.0)
BACK_RADIUS = 11.0
# البطاقة الأمامية (لؤلؤية، أسفل-يمين)
FRONT = (40.0, 40.0, 82.0, 82.0)
FRONT_RADIUS = 13.0
FRONT_INSET = 5.5                  # إطار داخلي رقيق بلون الهوية
FRONT_INSET_WIDTH = 1.2

# مونوغرام K — ثلاث ضلعات سميكة بأطراف دائرية
K_STEM = ((54.0, 48.0), (54.0, 74.0))
K_LOWER_ARM = ((57.5, 59.5), (67.0, 74.0))
K_UPPER_ARM = ((54.0, 61.0), (66.5, 47.5))
K_WIDTH = 7.4

# وهج علوي (إضاءة ناعمة تكسر التدرّج الخطي)
GLOW_CENTER = (34.0, 30.0)
GLOW_RADIUS = 52.0
GLOW_ALPHA = 0.13

OUTER_RADIUS_RATIO = 0.22          # استدارة الأيقونة الكاملة للأجهزة القديمة
SUPERSAMPLE = 3                    # 3×3 عيّنة لكل بكسل لمكافحة التسنّن


# ---------------------------------------------------------------------------
# أدوات هندسية
# ---------------------------------------------------------------------------
def rounded_rect_contains(px, py, x0, y0, x1, y1, r):
    if px < x0 or px > x1 or py < y0 or py > y1:
        return False
    cx = min(max(px, x0 + r), x1 - r)
    cy = min(max(py, y0 + r), y1 - r)
    dx, dy = px - cx, py - cy
    return dx * dx + dy * dy <= r * r


def point_segment_distance(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    length_sq = vx * vx + vy * vy
    if length_sq == 0:
        return math.hypot(wx, wy)
    t = max(0.0, min(1.0, (wx * vx + wy * vy) / length_sq))
    return math.hypot(px - (ax + t * vx), py - (ay + t * vy))


def gradient_color(t):
    t = max(0.0, min(1.0, t))
    for i in range(len(BG_STOPS) - 1):
        t0, c0 = BG_STOPS[i]
        t1, c1 = BG_STOPS[i + 1]
        if t <= t1:
            local = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(int(round(c0[k] + (c1[k] - c0[k]) * local)) for k in range(3))
    return BG_STOPS[-1][1]


def blend(dst, src, alpha):
    """src/dst = (r, g, b); alpha معامل التغطية."""
    inv = 1.0 - alpha
    return (
        src[0] * alpha + dst[0] * inv,
        src[1] * alpha + dst[1] * inv,
        src[2] * alpha + dst[2] * inv,
    )


# ---------------------------------------------------------------------------
# الرسم
# ---------------------------------------------------------------------------
def render(size, with_background):
    """يرجع بايتات RGBA بحجم size×size.

    with_background=True  → الأيقونة الكاملة (خلفية + رسم + قص دائري).
    with_background=False → الرسم فقط بخلفية شفافة (الطبقة الأمامية المتكيّفة).
    """
    k = size / VIEWPORT
    radius = OUTER_RADIUS_RATIO * size

    back = tuple(v * k for v in BACK)
    back_radius = BACK_RADIUS * k
    front = tuple(v * k for v in FRONT)
    front_radius = FRONT_RADIUS * k
    inset = FRONT_INSET * k
    inset_w = FRONT_INSET_WIDTH * k

    stem = tuple((p[0] * k, p[1] * k) for p in K_STEM)
    lower_arm = tuple((p[0] * k, p[1] * k) for p in K_LOWER_ARM)
    upper_arm = tuple((p[0] * k, p[1] * k) for p in K_UPPER_ARM)
    k_half = K_WIDTH * k / 2.0

    glow_cx, glow_cy = GLOW_CENTER[0] * k, GLOW_CENTER[1] * k
    glow_r = GLOW_RADIUS * k

    samples = SUPERSAMPLE * SUPERSAMPLE
    step = 1.0 / SUPERSAMPLE
    offset = step / 2.0

    rows = []
    for py in range(size):
        row = bytearray()
        row.append(0)  # PNG filter type: None
        for px in range(size):
            rgba = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SUPERSAMPLE):
                y = py + offset + sy * step
                for sx in range(SUPERSAMPLE):
                    x = px + offset + sx * step

                    # القص الخارجي للأيقونة الكاملة فقط.
                    if with_background and not rounded_rect_contains(
                        x, y, 0.0, 0.0, size - 1.0, size - 1.0, radius
                    ):
                        continue

                    color = (0.0, 0.0, 0.0)
                    hit = with_background
                    if with_background:
                        diag_t = (x + y) / (2.0 * (size - 1.0)) if size > 1 else 0.0
                        color = tuple(float(c) for c in gradient_color(diag_t))
                        # وهج علوي ناعم.
                        d = math.hypot(x - glow_cx, y - glow_cy)
                        if d < glow_r:
                            color = blend(color, GLOW, GLOW_ALPHA * (1.0 - d / glow_r) ** 2)

                    # 1) البطاقة الخلفية بلون الهوية.
                    if rounded_rect_contains(
                        x, y, back[0], back[1], back[2], back[3], back_radius
                    ):
                        color = blend(color, BACK_CARD, 0.95)
                        hit = True

                    # 2) البطاقة الأمامية اللؤلؤية.
                    if rounded_rect_contains(
                        x, y, front[0], front[1], front[2], front[3], front_radius
                    ):
                        color = blend(color, PEARL, 0.98)
                        hit = True

                        # 3) إطار داخلي رقيق بلون الهوية.
                        inside_inner = rounded_rect_contains(
                            x,
                            y,
                            front[0] + inset,
                            front[1] + inset,
                            front[2] - inset,
                            front[3] - inset,
                            max(front_radius - inset, 0.0),
                        )
                        inside_ring = rounded_rect_contains(
                            x,
                            y,
                            front[0] + inset - inset_w,
                            front[1] + inset - inset_w,
                            front[2] - inset + inset_w,
                            front[3] - inset + inset_w,
                            max(front_radius - inset + inset_w, 0.0),
                        )
                        if inside_ring and not inside_inner:
                            color = blend(color, TEAL_DEEP, 0.18 / 0.98)

                        # 4) مونوغرام K — عمود وقاعدة بلون الهوية، ضلع ذهبي.
                        if point_segment_distance(x, y, *stem[0], *stem[1]) <= k_half:
                            color = blend(color, TEAL_DEEP, 1.0)
                        if point_segment_distance(x, y, *lower_arm[0], *lower_arm[1]) <= k_half:
                            color = blend(color, TEAL_DEEP, 1.0)
                        if point_segment_distance(x, y, *upper_arm[0], *upper_arm[1]) <= k_half:
                            color = blend(color, GOLD, 1.0)

                    rgba[0] += color[0]
                    rgba[1] += color[1]
                    rgba[2] += color[2]
                    # التغطية تُحسب فقط للعيّنات التي رسمت شيئاً، وإلا أصبحت
                    # الطبقة الشفافة (الأيقونة المتكيّفة) معتمة بالكامل.
                    if hit:
                        rgba[3] += 255.0

            covered = rgba[3] / samples
            if covered <= 0.0:
                row.extend((0, 0, 0, 0))
                continue
            alpha = int(round(covered))
            inv_alpha = 1.0 / max(covered / 255.0, 1e-6)
            row.extend(
                (
                    max(0, min(255, int(round(rgba[0] / samples * inv_alpha)))),
                    max(0, min(255, int(round(rgba[1] / samples * inv_alpha)))),
                    max(0, min(255, int(round(rgba[2] / samples * inv_alpha)))),
                    alpha,
                )
            )
        rows.append(bytes(row))
    return b"".join(rows)


def render_monochrome(size):
    """أيقونة الثيم: حدود البطاقة + حرف K فقط بلون أبيض وخلفية شفافة.

    لا تُرسم خلفية ولا بطاقة ممتلئة، لأن النظام يستبدل اللون بالكامل: أي شكل
    ممتلئ سيظهر كتلة واحدة ويُخفي الحرف.
    """
    k = size / VIEWPORT
    front = tuple(v * k for v in FRONT)
    front_radius = FRONT_RADIUS * k
    border = 3.2 * k
    outer = (
        front[0] - border,
        front[1] - border,
        front[2] + border,
        front[3] + border,
    )
    stem = tuple((p[0] * k, p[1] * k) for p in K_STEM)
    lower_arm = tuple((p[0] * k, p[1] * k) for p in K_LOWER_ARM)
    upper_arm = tuple((p[0] * k, p[1] * k) for p in K_UPPER_ARM)
    k_half = K_WIDTH * k / 2.0

    samples = SUPERSAMPLE * SUPERSAMPLE
    step = 1.0 / SUPERSAMPLE
    offset = step / 2.0

    rows = []
    for py in range(size):
        row = bytearray()
        row.append(0)
        for px in range(size):
            hits = 0
            for sy in range(SUPERSAMPLE):
                y = py + offset + sy * step
                for sx in range(SUPERSAMPLE):
                    x = px + offset + sx * step
                    on_border = rounded_rect_contains(
                        x, y, outer[0], outer[1], outer[2], outer[3], front_radius + border
                    ) and not rounded_rect_contains(
                        x, y, front[0], front[1], front[2], front[3], front_radius
                    )
                    on_k = (
                        point_segment_distance(x, y, *stem[0], *stem[1]) <= k_half
                        or point_segment_distance(x, y, *lower_arm[0], *lower_arm[1])
                        <= k_half
                        or point_segment_distance(x, y, *upper_arm[0], *upper_arm[1])
                        <= k_half
                    )
                    if on_border or on_k:
                        hits += 1
            alpha = int(round(hits * 255 / samples))
            row.extend((255, 255, 255, alpha) if alpha > 0 else (0, 0, 0, 0))
        rows.append(bytes(row))
    return b"".join(rows)


def write_png(path, size, raw):
    def chunk(tag, data):
        payload = tag + data
        return (
            struct.pack(">I", len(data))
            + payload
            + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as handle:
        handle.write(png)


# كثافة → (حجم أيقونة الـmipmap بوحدة dp 48، حجم 108dp للرسم المتكيّف)
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

APP_ICON_SIZE = 192
NOTIF_LARGE_DP = 96          # الأيقونة الكبيرة في الإشعار (96dp)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    res = os.path.join(root, "android", "app", "src", "main", "res")

    for density, (launcher_size, art_size) in DENSITIES.items():
        mipmap_dir = os.path.join(res, f"mipmap-{density}")
        os.makedirs(mipmap_dir, exist_ok=True)
        launcher_path = os.path.join(mipmap_dir, "ic_launcher.png")
        write_png(launcher_path, launcher_size, render(launcher_size, True))
        print(f"wrote {launcher_path} ({launcher_size}x{launcher_size})")

        drawable_dir = os.path.join(res, f"drawable-{density}")
        os.makedirs(drawable_dir, exist_ok=True)
        art_path = os.path.join(drawable_dir, "ic_launcher_art.png")
        write_png(art_path, art_size, render(art_size, False))
        print(f"wrote {art_path} ({art_size}x{art_size})")

        mono_path = os.path.join(drawable_dir, "ic_launcher_mono_art.png")
        write_png(mono_path, art_size, render_monochrome(art_size))
        print(f"wrote {mono_path} ({art_size}x{art_size})")

        notif_size = int(round(NOTIF_LARGE_DP * launcher_size / 48))
        notif_path = os.path.join(drawable_dir, "ic_notif_large.png")
        write_png(notif_path, notif_size, render(notif_size, True))
        print(f"wrote {notif_path} ({notif_size}x{notif_size})")

    icon_dir = os.path.join(root, "assets", "icon")
    os.makedirs(icon_dir, exist_ok=True)
    app_icon_path = os.path.join(icon_dir, "app_icon.png")
    write_png(app_icon_path, APP_ICON_SIZE, render(APP_ICON_SIZE, True))
    print(f"wrote {app_icon_path} ({APP_ICON_SIZE}x{APP_ICON_SIZE})")


if __name__ == "__main__":
    main()
