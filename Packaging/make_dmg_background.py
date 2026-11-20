#!/usr/bin/env python3
"""Render the Silverbox DMG window background.

Writes background.png (660x400 @72dpi) and background@2x.png (1320x800 @144dpi).
dmgbuild picks up the @2x file automatically and merges both into a HiDPI TIFF.

Scene: a light CRT screen, as the light site shows it. The ground is the site's warm
paper (#e6dccb), with faint scanlines and a dim vignette at the edges. A lighter screen
panel with round corners holds the two icon slots, each with a soft amber glow under it.
An arrow of square "pixels", in the app's amber accent, steps from the app to Applications
and ends in a head of pixels, as an old terminal would draw it.

The picture stays light behind Finder's icon labels, which Finder draws in black in both
appearances.

Usage: python3 make_dmg_background.py [outdir] [--guides]
  --guides also writes background-guides.png with the icon and label boxes outlined.
It needs numpy and Pillow; make dist does not run it, and uses the PNGs in Packaging/.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# --- Layout, in points (1x). Keep in sync with dmg_settings.py --------------
W, H = 660, 400
APP_POS = (180, 180)    # icon centres, as dmgbuild's icon_locations
APPS_POS = (480, 180)
ICON = 128
# Finder's labels: centred under each icon, ~13 pt tall, near y=262
LABELS = [(APP_POS[0], 262, 100), (APPS_POS[0], 262, 80)]   # (cx, cy, width)

# The screen panel around both icons.
PANEL = (40, 52, W - 40, 312)   # left, top, right, bottom
PANEL_RADIUS = 26

S = 4                   # master supersampling factor relative to 1x
MW, MH = W * S, H * S


def hexrgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], float) / 255


# The light site's tokens (docs/site/css/tokens.css) and the app's amber accent (Theme.swift).
GROUND_TOP = hexrgb("#ece4d6")
GROUND_LOW = hexrgb("#e2d7c4")
PANEL_FILL = hexrgb("#f4efe6")
PANEL_EDGE = (90, 66, 30)          # --line's colour
SCANLINE = hexrgb("#5a421e")       # --scanline's colour
GLOW = hexrgb("#ffb000")           # --phosphor (dark), the CRT amber
ACCENT = (0xB4, 0x6E, 0x12)        # Theme.accent, amber, light appearance
ACCENT_DEEP = (0x85, 0x59, 0x0A)   # --phosphor / --link (light)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def rounded_box_distance(x, y, box, radius):
    """Signed distance (points) to a rounded rectangle: negative inside."""
    l, t, r, b = box
    cx, cy = (l + r) / 2, (t + b) / 2
    hx, hy = (r - l) / 2 - radius, (b - t) / 2 - radius
    qx = np.abs(x - cx) - hx
    qy = np.abs(y - cy) - hy
    outside = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
    inside = np.minimum(np.maximum(qx, qy), 0)
    return outside + inside - radius


def render_master():
    ys, xs = np.mgrid[0:MH, 0:MW].astype(np.float64)
    x = (xs + 0.5) / S
    y = (ys + 0.5) / S

    # ---- Ground: warm paper, a little darker at the bottom ---------------------
    t = smoothstep(0, H, y)[..., None]
    img = GROUND_TOP * (1 - t) + GROUND_LOW * t

    # ---- The screen panel, with a soft shadow and a thin edge ------------------
    d = rounded_box_distance(x, y - 3, PANEL, PANEL_RADIUS)
    shadow = np.exp(-np.clip(d, 0, None) / 9.0) * (d > 0)
    img = img * (1 - 0.06 * shadow[..., None])
    d = rounded_box_distance(x, y, PANEL, PANEL_RADIUS)
    inside = np.clip(0.5 - d * S, 0, 1)[..., None]       # antialiased
    # The panel is lightest at its centre, like a lit screen.
    pcx, pcy = (PANEL[0] + PANEL[2]) / 2, (PANEL[1] + PANEL[3]) / 2
    pr = np.sqrt(((x - pcx) / ((PANEL[2] - PANEL[0]) / 2)) ** 2 + ((y - pcy) / ((PANEL[3] - PANEL[1]) / 2)) ** 2)
    panel = PANEL_FILL * (1 - 0.025 * smoothstep(0.3, 1.2, pr))[..., None]
    img = img * (1 - inside) + panel * inside
    edge = np.exp(-(d / 0.6) ** 2)[..., None]
    img = img * (1 - 0.10 * edge) + (np.array(PANEL_EDGE) / 255) * 0.10 * edge

    # ---- Amber glow under each icon (a tint, never darker) ---------------------
    for cx, cy in (APP_POS, APPS_POS):
        r2 = ((x - cx) ** 2 + (y - cy) ** 2) / (2 * 62.0 ** 2)
        a = (np.exp(-r2) * 0.16)[..., None]
        img = img * (1 - a) + (0.55 * img + 0.45 * GLOW) * a

    # ---- Scanlines: one dim line every 3 points, everywhere --------------------
    phase = np.mod(y, 3.0)
    line = smoothstep(1.6, 2.0, phase) * (1 - smoothstep(2.6, 3.0, phase))
    a = 0.055 * line[..., None]
    img = img * (1 - a) + SCANLINE * a

    # ---- Vignette: the edges of the window a little darker ---------------------
    vx = (x - W / 2) / (W / 2)
    vy = (y - H / 2) / (H / 2)
    v = smoothstep(0.55, 1.45, np.sqrt(vx * vx * 0.8 + vy * vy))
    img = img * (1 - 0.10 * v[..., None])
    return np.clip(img, 0, 1)


def draw_arrow(base):
    """A row of square pixels from the app to Applications, ending in a head of pixels."""
    layer = Image.new("RGBA", (MW, MH), (0, 0, 0, 0))
    dr = ImageDraw.Draw(layer)
    px = 5.0            # one "pixel" of the arrow, in points
    gap = 2.0
    step = px + gap
    cy = APP_POS[1]
    start = APP_POS[0] + ICON / 2 + 20
    end = APPS_POS[0] - ICON / 2 - 20
    head_cols = 4       # the head is 4 pixels deep
    shaft_end = end - head_cols * step
    xs = []
    xpos = start
    while xpos + px <= shaft_end:
        xs.append(xpos)
        xpos += step
    n = len(xs)
    for i, x0 in enumerate(xs):
        f = i / max(n - 1, 1)
        alpha = int(255 * (0.25 + 0.75 * f))
        dr.rectangle([x0 * S, (cy - px / 2) * S, (x0 + px) * S - 1, (cy + px / 2) * S - 1],
                     fill=ACCENT + (alpha,))
    # The head: a filled triangle of pixels, columns of 7, 5, 3, and 1.
    hx = xpos
    for col in range(head_cols):
        reach = head_cols - 1 - col          # rows above and below the centre
        for row in range(-reach, reach + 1):
            x0 = hx + col * step
            y0 = cy - px / 2 + row * step
            dr.rectangle([x0 * S, y0 * S, (x0 + px) * S - 1, (y0 + px) * S - 1],
                         fill=ACCENT_DEEP + (255,))
    glow = layer.filter(ImageFilter.GaussianBlur(4 * S))
    ga = np.array(glow.getchannel("A")).astype(np.float32) * 0.45
    tint = Image.new("RGBA", (MW, MH), (0xFF, 0xB0, 0x00, 0))
    tint.putalpha(Image.fromarray(ga.astype(np.uint8)))
    out = Image.alpha_composite(base.convert("RGBA"), tint)
    out = Image.alpha_composite(out, layer)
    return out.convert("RGB")


def label_contrast(lo):
    """Worst-case WCAG contrast of black text against each label box."""
    a = np.asarray(lo, float) / 255
    lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    Y = lin @ np.array([0.2126, 0.7152, 0.0722])
    res = []
    for cx, cy, w in LABELS:
        box = Y[int(cy - 9):int(cy + 9), int(cx - w / 2 - 6):int(cx + w / 2 + 6)]
        res.append((box.min() + 0.05) / 0.05)   # black text has luminance 0
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir", nargs="?", default=".")
    ap.add_argument("--guides", action="store_true")
    args = ap.parse_args()
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    arr = render_master()
    base = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGB")
    master = draw_arrow(base)
    hi = master.resize((W * 2, H * 2), Image.LANCZOS)
    lo = master.resize((W, H), Image.LANCZOS)
    hi.save(outdir / "background@2x.png", dpi=(144, 144), optimize=True)
    lo.save(outdir / "background.png", dpi=(72, 72), optimize=True)
    c = ", ".join(f"{v:.1f}:1" for v in label_contrast(lo))
    print(f"wrote {outdir}/background.png and background@2x.png; "
          f"black-label contrast (worst pixel) {c}")

    if args.guides:
        g = hi.convert("RGBA")
        d = ImageDraw.Draw(g)
        for cx, cy, w in LABELS:
            d.rectangle(((cx - w / 2) * 2, (cy - 7) * 2, (cx + w / 2) * 2, (cy + 7) * 2),
                        outline=(255, 0, 0, 255), width=2)
        for cx, cy in (APP_POS, APPS_POS):
            d.rectangle(((cx - 64) * 2, (cy - 64) * 2, (cx + 64) * 2, (cy + 64) * 2),
                        outline=(0, 120, 255, 255), width=2)
        g.convert("RGB").save(outdir / "background-guides.png")


if __name__ == "__main__":
    main()
