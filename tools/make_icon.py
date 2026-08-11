"""Generate the Upkeep launcher icon.

The icon is the app's thesis in one mark: a gauge arc sitting at 90% —
the moment Upkeep exists to tell you about — wrapped around a wrench.

    python tools/make_icon.py
    dart run flutter_launcher_icons

Two files come out:
  assets/icon/upkeep_icon.png     legacy square icon, full canvas
  assets/icon/upkeep_icon_fg.png  adaptive foreground, transparent

Adaptive icons crop to the central 66% of the canvas, so the foreground's
content is drawn inside that safe box — anything outside it gets sliced
off by round/squircle launcher masks.
"""

import math
import os

from PIL import Image, ImageDraw

SIZE = 1024
BG = (10, 12, 15, 255)  # kBg
TRACK = (27, 33, 40, 255)  # kTrack
READY = (255, 176, 32, 255)  # kReady — the 90% state
STEEL = (155, 170, 184, 255)  # the wrench

SWEEP = 0.90  # where the needle sits: 90%, ready

# flutter_launcher_icons wraps the adaptive foreground in a 16% inset, so the
# art is shown at 68% of the layer. Drawn at 1.0 the mark ends up a small dot
# adrift in a big circle — this scales it back up to land at ~68% of the
# visible circle's radius. 1.30 is the most that still fits the canvas.
FG_SCALE = 1.30

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")


def draw_mark(img, cx, cy, scale):
    """Draw the gauge + wrench centred on (cx, cy). scale 1.0 == 1024 canvas."""
    d = ImageDraw.Draw(img)

    r = 340 * scale  # ring radius
    w = 78 * scale  # ring stroke

    box = [cx - r, cy - r, cx + r, cy + r]
    # Full track, then the amber arc over it, starting at 12 o'clock.
    d.arc(box, 0, 360, fill=TRACK, width=int(w))
    d.arc(box, -90, -90 + 360 * SWEEP, fill=READY, width=int(w))

    # ── wrench, drawn on its own layer so the notch can be cut cleanly ──
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)

    shaft_w = 52 * scale
    head_r = 112 * scale
    head_cy = cy - 78 * scale
    shaft_top = head_cy
    shaft_bot = cy + 205 * scale

    ld.rounded_rectangle(
        [cx - shaft_w / 2, shaft_top, cx + shaft_w / 2, shaft_bot],
        radius=shaft_w / 2,
        fill=STEEL,
    )
    ld.ellipse(
        [cx - head_r, head_cy - head_r, cx + head_r, head_cy + head_r],
        fill=STEEL,
    )
    # The V bite that makes it read as an open-end wrench rather than a
    # lollipop. Cut by writing transparent pixels straight over the layer.
    # Keep it modest: a wide, deep bite turns the head into a tuning fork.
    notch_w = 50 * scale
    ld.polygon(
        [
            (cx - notch_w, head_cy - head_r * 1.6),
            (cx + notch_w, head_cy - head_r * 1.6),
            (cx, head_cy - head_r * 0.12),
        ],
        fill=(0, 0, 0, 0),
    )

    img.alpha_composite(layer)


def main():
    os.makedirs(OUT, exist_ok=True)

    # ── legacy / square icon: mark on the app background ──
    legacy = Image.new("RGBA", (SIZE, SIZE), BG)
    draw_mark(legacy, SIZE / 2, SIZE / 2, 1.0)
    legacy.save(os.path.join(OUT, "upkeep_icon.png"))

    # ── adaptive foreground ──
    # Drawn FULL SIZE, not pre-shrunk into the safe box: flutter_launcher_icons
    # already wraps the foreground in a 16% inset, so scaling here too leaves
    # a tiny mark floating in a big empty circle.
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_mark(fg, SIZE / 2, SIZE / 2, FG_SCALE)
    fg.save(os.path.join(OUT, "upkeep_icon_fg.png"))

    # ── simulate what the launcher actually shows ──
    # background + foreground inset 16%, cropped to a circle. This is the
    # only honest check that the mark isn't clipped or lost.
    sim = Image.new("RGBA", (SIZE, SIZE), BG)
    inset = int(SIZE * 0.16)
    sim.alpha_composite(
        fg.resize((SIZE - inset * 2, SIZE - inset * 2), Image.LANCZOS),
        (inset, inset),
    )
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, SIZE, SIZE], fill=255)
    round_icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    round_icon.paste(sim, (0, 0), mask)
    round_icon.save(os.path.join(OUT, "_launcher_preview.png"))

    print("wrote upkeep_icon.png + upkeep_icon_fg.png")


if __name__ == "__main__":
    main()
