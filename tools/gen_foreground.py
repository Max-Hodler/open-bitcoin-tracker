"""Regenerate the light-mode launcher icon assets (three orange rounded
rectangles), then run `dart run flutter_launcher_icons` to propagate to
every Android mipmap density.

Geometry is parameterized by `SCALE`. The original foreground used a
540x446 stack inside a 1024x1024 canvas; bumping `SCALE` enlarges the
stack around the canvas center while preserving the gap and corner-radius
ratios.

Outputs:
  - assets/launcher/ic_launcher_foreground.png  (bars on transparent)
  - assets/launcher/ic_launcher.png             (bars on solid white)
"""

from PIL import Image, ImageDraw
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
OUT_FG = os.path.join(ROOT, "assets/launcher/ic_launcher_foreground.png")
OUT_LEGACY = os.path.join(ROOT, "assets/launcher/ic_launcher.png")

CANVAS = 1024
ORANGE = (0xF7, 0x93, 0x1A, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)

# Original geometry (measured from the prior foreground).
BASE_BAR_W = 540
BASE_BAR_H = 126
BASE_GAP = 34
BASE_RADIUS = 29  # ≈ 0.23 * bar_height

SCALE = 1.08  # ~8% larger rectangles


def render_bars(background):
    bar_w = round(BASE_BAR_W * SCALE)
    bar_h = round(BASE_BAR_H * SCALE)
    gap = round(BASE_GAP * SCALE)
    radius = round(BASE_RADIUS * SCALE)

    total_h = bar_h * 3 + gap * 2
    x0 = (CANVAS - bar_w) // 2
    y0 = (CANVAS - total_h) // 2

    # Render at 4x for clean rounded corners, then downsample.
    SS = 4
    big = Image.new("RGBA", (CANVAS * SS, CANVAS * SS), background)
    draw = ImageDraw.Draw(big)
    for i in range(3):
        y = y0 + i * (bar_h + gap)
        draw.rounded_rectangle(
            [(x0 * SS, y * SS), ((x0 + bar_w) * SS - 1, (y + bar_h) * SS - 1)],
            radius=radius * SS,
            fill=ORANGE,
        )
    return big.resize((CANVAS, CANVAS), Image.LANCZOS), (bar_w, bar_h, gap, radius)


def main():
    fg, geom = render_bars((0, 0, 0, 0))
    fg.save(OUT_FG)
    legacy, _ = render_bars(WHITE)
    legacy.save(OUT_LEGACY)
    bar_w, bar_h, gap, radius = geom
    print(
        f"bar={bar_w}x{bar_h}  gap={gap}  radius={radius}\n"
        f"wrote {OUT_FG}\nwrote {OUT_LEGACY}"
    )


if __name__ == "__main__":
    main()
