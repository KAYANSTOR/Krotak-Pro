#!/usr/bin/env python3
"""يولّد أيقونة التطبيق (mipmap PNG) بدون أي مكتبات خارجية.

السبب: بيئة البناء لا تحتوي Pillow أو ImageMagick، بينما Android يحتاج ملفات
PNG للأجهزة الأقدم من API 26 (الأجهزة الأحدث تستخدم الأيقونة المتكيّفة في
`mipmap-anydpi-v26` + `drawable/ic_launcher_*.xml`).

نفس تصميم الأيقونة المتكيّفة بالضبط: خلفية Deep Slate → Teal، بطاقة لؤلؤية،
حرف N بلون الهوية بقُطر ذهبي واحد، وثلاث عُقد شبكة صغيرة.

الاستخدام:  python3 tools/generate_launcher_icons.py
"""

import math
import os
import struct
import zlib

# ---------------------------------------------------------------------------
# لوحة الألوان (نفس قيم الهوية المستخدمة في الثيم والأيقونة المتكيّفة)
# ---------------------------------------------------------------------------
BG_STOPS = [
    (0.00, (0x08, 0x20, 0x2B)),  # Deep Slate
    (0.55, (0x0F, 0x76, 0x6E)),  # Teal (هوية)
    (1.00, (0x14, 0xB8, 0xA6)),  # Teal فاتح
]
GOLD = (0xE0, 0xA8, 0x2E)
TEAL = (0x0F, 0x76, 0x6E)
PEARL = (255, 255, 255)
SHADOW = (0x04, 0x14, 0x1A)

# المرجع: viewport 108×108 كما في ic_launcher_foreground.xml
VIEWPORT = 108.0
CARD = (26.0, 26.0, 82.0, 82.0)          # x0, y0, x1, y1
CARD_RADIUS = 14.0
CARD_INSET = 31.0                         # الإطار الداخلي الرقيق
LEFT_STEM = (41.0, 40.0, 48.2, 68.0)
RIGHT_STEM = (59.8, 40.0, 67.0, 68.0)
DIAGONAL = [(41.0, 40.0), (48.2, 40.0), (67.0, 68.0), (59.8, 68.0)]
NODES = [
    (72.0, 42.0, 3.4, GOLD, 1.0),
    (77.0, 54.0, 2.6, TEAL, 0.85),
    (73.0, 65.0, 2.3, TEAL, 0.7),
]
CONNECTORS = [
    ((72.4, 45.2), (76.6, 51.4)),
    ((76.6, 56.6), (73.2, 62.4)),
]
CONNECTOR_WIDTH = 1.5
INNER_RING_WIDTH = 1.1
OUTER_RADIUS_RATIO = 0.20  # استدارة الأيقونة الكاملة على الأجهزة القديمة

SUPERSAMPLE = 3  # 3×3 عيّنات لكل بكسل لمكافحة التسنّن


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


def circle_contains(px, py, cx, cy, r):
    dx, dy = px - cx, py - cy
    return dx * dx + dy * dy <= r * r


def convex_polygon_contains(px, py, points):
    sign = 0
    n = len(points)
    for i in range(n):
        ax, ay = points[i]
        bx, by = points[(i + 1) % n]
        cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
        if cross == 0:
            continue
        current = 1 if cross > 0 else -1
        if sign == 0:
            sign = current
        elif sign != current:
            return False
    return True


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
            return tuple(
                int(round(c0[k] + (c1[k] - c0[k]) * local)) for k in range(3)
            )
    return BG_STOPS[-1][1]


# ---------------------------------------------------------------------------
# الرسم
# ---------------------------------------------------------------------------
def blend(dst, src, alpha):
    """src/dst = (r, g, b); alpha معامل التغطية؛ dst هو البكسل الحالي المتراكم."""
    inv = 1.0 - alpha
    return (
        src[0] * alpha + dst[0] * inv,
        src[1] * alpha + dst[1] * inv,
        src[2] * alpha + dst[2] * inv,
    )


def render(size):
    """يرجع بايتات RGBA للصورة بحجم size×size."""
    k = size / VIEWPORT
    radius = OUTER_RADIUS_RATIO * size
    samples = SUPERSAMPLE * SUPERSAMPLE
    step = 1.0 / SUPERSAMPLE
    offset = step / 2.0

    card = tuple(v * k for v in CARD)
    card_radius = CARD_RADIUS * k
    inset = CARD_INSET * k
    shadow_shift = 4.0 * k
    ring_w = INNER_RING_WIDTH * k
    conn_w = CONNECTOR_WIDTH * k
    diagonal = [(x * k, y * k) for x, y in DIAGONAL]
    stems = [
        tuple(v * k for v in LEFT_STEM),
        tuple(v * k for v in RIGHT_STEM),
    ]
    nodes = [(x * k, y * k, r * k, color, a) for x, y, r, color, a in NODES]
    connectors = [
        ((a[0] * k, a[1] * k), (b[0] * k, b[1] * k)) for a, b in CONNECTORS
    ]

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

                    if not rounded_rect_contains(
                        x, y, 0.0, 0.0, size - 1.0, size - 1.0, radius
                    ):
                        continue

                    # 1) الخلفية المتدرّجة
                    diag_t = (x + y) / (2.0 * (size - 1.0)) if size > 1 else 0.0
                    color = gradient_color(diag_t)

                    # 2) ظل البطاقة (قبل البطاقة، مُزاح للأسفل)
                    if rounded_rect_contains(
                        x,
                        y,
                        card[0],
                        card[1] + shadow_shift,
                        card[2],
                        card[3] + shadow_shift,
                        card_radius,
                    ):
                        color = blend(color, SHADOW, 0.28)

                    # 3) البطاقة اللؤلؤية
                    if rounded_rect_contains(
                        x, y, card[0], card[1], card[2], card[3], card_radius
                    ):
                        color = blend(color, PEARL, 0.97)

                        # 4) الإطار الداخلي الرقيق
                        inner_outside = not rounded_rect_contains(
                            x,
                            y,
                            card[0] + inset,
                            card[1] + inset,
                            card[2] - inset,
                            card[3] - inset,
                            max(card_radius - inset, 0.0),
                        )
                        ring_center = rounded_rect_contains(
                            x,
                            y,
                            card[0] + inset - ring_w,
                            card[1] + inset - ring_w,
                            card[2] - inset + ring_w,
                            card[3] - inset + ring_w,
                            max(card_radius - inset + ring_w, 0.0),
                        )
                        if inner_outside and ring_center:
                            color = blend(color, TEAL, 0.16 / 0.97)

                        # 5) ساقا حرف N
                        for s in stems:
                            if rounded_rect_contains(x, y, s[0], s[1], s[2], s[3], 0.0):
                                color = blend(color, TEAL, 1.0)

                        # 6) القُطر الذهبي
                        if convex_polygon_contains(x, y, diagonal):
                            color = blend(color, GOLD, 1.0)

                        # 7) وصلات وعُقد الشبكة
                        for (ax, ay), (bx, by) in connectors:
                            if point_segment_distance(x, y, ax, ay, bx, by) <= conn_w / 2.0:
                                color = blend(color, GOLD, 0.7)
                        for nx, ny, nr, ncolor, nalpha in nodes:
                            if circle_contains(x, y, nx, ny, nr):
                                color = blend(color, ncolor, nalpha)

                    rgba[0] += color[0]
                    rgba[1] += color[1]
                    rgba[2] += color[2]
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


DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for density, size in DENSITIES.items():
        target = os.path.join(
            root, "android", "app", "src", "main", "res", f"mipmap-{density}"
        )
        os.makedirs(target, exist_ok=True)
        path = os.path.join(target, "ic_launcher.png")
        write_png(path, size, render(size))
        print(f"wrote {path} ({size}x{size})")


if __name__ == "__main__":
    main()
