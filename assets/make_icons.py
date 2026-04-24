#!/usr/bin/env python3
"""Generate Clipo.icns and menubar.pdf from the logo design."""

import math
import os
import struct
import zlib

# ── helpers ────────────────────────────────────────────────────────────────

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

def lerp(a, b, t):
    return a + (b - a) * t

# ── tiny PNG writer (no Pillow needed) ─────────────────────────────────────

def _chunk(tag, data):
    c = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", c)

def write_png(path, pixels, w, h):
    """pixels: list of (r,g,b,a) tuples, row-major."""
    raw = b""
    for y in range(h):
        raw += b"\x00"  # filter type None
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
            raw += bytes([r, g, b, a])
    compressed = zlib.compress(raw, 9)
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    idat = _chunk(b"IDAT", compressed)
    iend = _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(sig + ihdr + idat + iend)

# ── drawing primitives ──────────────────────────────────────────────────────

def fill_background(buf, w, h, r, g, b, a, corner):
    """Rounded-rectangle fill."""
    for y in range(h):
        for x in range(w):
            # distance from corner
            cx = clamp(x, corner, w - 1 - corner)
            cy = clamp(y, corner, h - 1 - corner)
            dist = math.sqrt((x - cx)**2 + (y - cy)**2)
            alpha = clamp(corner - dist + 0.5, 0, 1)
            if alpha > 0:
                buf[y * w + x] = (r, g, b, int(a * alpha))

def blend(bg, fg, t):
    """Alpha-blend fg onto bg."""
    a = t / 255
    return tuple(int(bg[i] * (1 - a) + fg[i] * a) for i in range(3)) + (
        clamp(int(bg[3] + fg[3] * a * (1 - bg[3] / 255)), 0, 255),
    )

def draw_circle(buf, w, h, cx, cy, radius, color, aa=1.5):
    ix, iy = int(cx), int(cy)
    r = int(radius + aa + 1)
    for y in range(max(0, iy - r), min(h, iy + r + 1)):
        for x in range(max(0, ix - r), min(w, ix + r + 1)):
            dist = math.sqrt((x - cx)**2 + (y - cy)**2)
            alpha = clamp(radius - dist + aa, 0, 1)
            if alpha > 0:
                fc = color[:3] + (int(color[3] * alpha),)
                buf[y * w + x] = blend(buf[y * w + x], fc, fc[3])

def draw_line_segment(buf, w, h, x0, y0, x1, y1, thick, color):
    """Thick line via sampling."""
    dx, dy = x1 - x0, y1 - y0
    length = math.sqrt(dx*dx + dy*dy)
    if length < 0.001:
        return
    nx, ny = -dy / length, dx / length
    steps = max(int(length * 2), 2)
    half = thick / 2
    for i in range(steps + 1):
        t = i / steps
        px, py = x0 + dx * t, y0 + dy * t
        draw_circle(buf, w, h, px, py, half, color, aa=1.0)

def draw_bezier(buf, w, h, x0, y0, cx, cy, x1, y1, thick, color, steps=60):
    prev = (x0, y0)
    for i in range(1, steps + 1):
        t = i / steps
        bx = (1-t)**2*x0 + 2*(1-t)*t*cx + t**2*x1
        by = (1-t)**2*y0 + 2*(1-t)*t*cy + t**2*y1
        draw_line_segment(buf, w, h, prev[0], prev[1], bx, by, thick, color)
        prev = (bx, by)

# ── logo renderer ───────────────────────────────────────────────────────────

def render_logo(size, bg=True):
    """Render the Clipo logo at `size`×`size`. Returns pixel buffer."""
    s = size / 200  # scale factor

    buf = [(0, 0, 0, 0)] * (size * size)

    if bg:
        corner = 42 * s
        fill_background(buf, size, size, 0x0d, 0x11, 0x17, 255, int(corner))

    dark_green  = (0x15, 0x80, 0x3d, 255)
    mid_green   = (0x22, 0xc5, 0x5e, 255)
    light_green = (0x4a, 0xde, 0x80, 255)
    leaf_green  = (0x22, 0xc5, 0x5e, 255)

    # Scale node positions from 200px space
    def p(x, y):
        return x * s, y * s

    root      = p(100, 163)
    junction  = p(100, 126)
    left_mid  = p(58,  91)
    right_mid = p(142, 91)
    leaf_l    = p(36,  55)
    leaf_cl   = p(80,  55)
    leaf_r    = p(142, 55)

    t_trunk   = 3.5 * s
    t_branch  = 2.8 * s
    t_twig    = 2.2 * s

    # Trunk
    draw_line_segment(buf, size, size, *root, *junction, t_trunk, dark_green)

    # Junction → left / right mid
    draw_bezier(buf, size, size, junction[0], junction[1],
                junction[0], p(100,110)[1], left_mid[0], left_mid[1]+4*s,
                t_branch, dark_green)
    draw_bezier(buf, size, size, junction[0], junction[1],
                junction[0], p(100,110)[1], right_mid[0], right_mid[1]+4*s,
                t_branch, dark_green)

    # Left mid → leaf_l
    draw_bezier(buf, size, size, left_mid[0], left_mid[1],
                left_mid[0], p(58,74)[1], leaf_l[0], leaf_l[1]+4*s,
                t_twig, mid_green)
    # Left mid → leaf_cl
    draw_bezier(buf, size, size, left_mid[0], left_mid[1],
                left_mid[0], p(58,74)[1], leaf_cl[0], leaf_cl[1]+4*s,
                t_twig, mid_green)
    # Right mid → leaf_r (straight)
    draw_line_segment(buf, size, size, right_mid[0], right_mid[1],
                      leaf_r[0], leaf_r[1], t_twig, mid_green)

    # Nodes (outer ring, inner fill)
    draw_circle(buf, size, size, *root,      9*s, dark_green)
    draw_circle(buf, size, size, *root,    5.5*s, light_green)

    draw_circle(buf, size, size, *junction,  8*s, dark_green)
    draw_circle(buf, size, size, *junction,  5*s, mid_green)

    draw_circle(buf, size, size, *left_mid,  7*s, (0x16, 0x65, 0x34, 255))
    draw_circle(buf, size, size, *left_mid, 4.2*s, light_green)

    draw_circle(buf, size, size, *right_mid, 7*s, (0x16, 0x65, 0x34, 255))
    draw_circle(buf, size, size, *right_mid,4.2*s, light_green)

    draw_circle(buf, size, size, *leaf_l,    6*s, leaf_green)
    draw_circle(buf, size, size, *leaf_cl,   6*s, leaf_green)
    draw_circle(buf, size, size, *leaf_r,    6*s, leaf_green)

    return buf

# ── monochrome menu bar renderer ────────────────────────────────────────────

def render_menubar(size):
    """Black tree on transparent bg — macOS template image."""
    buf = [(0, 0, 0, 0)] * (size * size)
    s = size / 22  # design space: 22×22 pt

    black = (0, 0, 0, 255)

    def p(x, y):
        return x * s, y * s

    root      = p(11,  20)
    junction  = p(11,  14)
    left_mid  = p(6.5, 9)
    right_mid = p(15.5, 9)
    leaf_l    = p(4,   4)
    leaf_cl   = p(9,   4)
    leaf_r    = p(15.5, 4)

    t = 1.1 * s

    draw_line_segment(buf, size, size, *root, *junction, t, black)
    draw_bezier(buf, size, size, junction[0], junction[1],
                junction[0], p(11, 12)[1], left_mid[0], left_mid[1]+0.5*s, t, black)
    draw_bezier(buf, size, size, junction[0], junction[1],
                junction[0], p(11, 12)[1], right_mid[0], right_mid[1]+0.5*s, t, black)
    draw_bezier(buf, size, size, left_mid[0], left_mid[1],
                left_mid[0], p(6.5, 7)[1], leaf_l[0], leaf_l[1]+0.5*s, t, black)
    draw_bezier(buf, size, size, left_mid[0], left_mid[1],
                left_mid[0], p(6.5, 7)[1], leaf_cl[0], leaf_cl[1]+0.5*s, t, black)
    draw_line_segment(buf, size, size, right_mid[0], right_mid[1],
                      leaf_r[0], leaf_r[1], t, black)

    draw_circle(buf, size, size, *root,      2.2*s, black)
    draw_circle(buf, size, size, *junction,  2*s, black)
    draw_circle(buf, size, size, *left_mid,  1.8*s, black)
    draw_circle(buf, size, size, *right_mid, 1.8*s, black)
    draw_circle(buf, size, size, *leaf_l,    1.6*s, black)
    draw_circle(buf, size, size, *leaf_cl,   1.6*s, black)
    draw_circle(buf, size, size, *leaf_r,    1.6*s, black)

    return buf

# ── main ────────────────────────────────────────────────────────────────────

base = os.path.dirname(os.path.abspath(__file__))
assets = os.path.join(base, "assets")
os.makedirs(assets, exist_ok=True)

# 1. App icon ICNS
iconset = os.path.join(assets, "Clipo.iconset")
os.makedirs(iconset, exist_ok=True)

icon_sizes = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

for size, name in icon_sizes:
    print(f"  rendering {name} ({size}px)…")
    buf = render_logo(size, bg=True)
    write_png(os.path.join(iconset, f"{name}.png"), buf, size, size)

print("Running iconutil…")
os.system(f'iconutil -c icns "{iconset}" -o "{assets}/Clipo.icns"')
print("✓ Clipo.icns created")

# 2. Menu bar icon (18pt @2x = 36px PNG, template-ready)
print("  rendering menubar@2x (36px)…")
mb2 = render_menubar(36)
write_png(os.path.join(assets, "menubar@2x.png"), mb2, 36, 36)

print("  rendering menubar (18px)…")
mb1 = render_menubar(18)
write_png(os.path.join(assets, "menubar.png"), mb1, 18, 18)

print("✓ menubar PNGs created")
print("Done.")
