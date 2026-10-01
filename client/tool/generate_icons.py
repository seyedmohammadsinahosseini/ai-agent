"""Generate AI Terminal web and Windows icons with Pillow.

Run from the repository root:
    python3 -m pip install Pillow
    python3 client/tool/generate_icons.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
WEB = ROOT / "client" / "web"
WINDOWS_ICON = ROOT / "client" / "windows" / "runner" / "resources" / "app_icon.ico"


def make_icon(size: int, *, maskable: bool = False) -> Image.Image:
    scale = size / 512
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()

    # Product gradient: Plan blue in the upper-left, Build orange lower-right.
    for y in range(size):
        for x in range(size):
            t = (x + y) / max(1, 2 * (size - 1))
            r = round(71 + (255 - 71) * t)
            g = round(112 + (159 - 112) * t)
            b = round(255 + (90 - 255) * t)
            pixels[x, y] = (r, g, b, 255)

    if not maskable:
        radius = round(112 * scale)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
        image.putalpha(mask)

    draw = ImageDraw.Draw(image)
    inset = round((100 if maskable else 72) * scale)
    terminal = (inset, inset, size - inset, size - inset)
    draw.rounded_rectangle(
        terminal,
        radius=round(48 * scale),
        fill=(11, 13, 18, 238),
        outline=(255, 255, 255, 58),
        width=max(1, round(4 * scale)),
    )

    # Minimal title-bar controls.
    dot_y = inset + round(45 * scale)
    for index, color in enumerate(((255, 92, 92, 255), (245, 197, 66, 255), (61, 220, 151, 255))):
        cx = inset + round((45 + index * 34) * scale)
        radius = max(1, round(7 * scale))
        draw.ellipse((cx - radius, dot_y - radius, cx + radius, dot_y + radius), fill=color)

    # Terminal prompt chevron and cursor; geometric shapes remain legible at 16px.
    line_width = max(2, round(22 * scale))
    x0, y0 = inset + round(85 * scale), inset + round(145 * scale)
    x1, y1 = inset + round(145 * scale), inset + round(205 * scale)
    draw.line((x0, y0, x1, y1), fill=(108, 140, 255, 255), width=line_width)
    draw.line((x1, y1, x0, y1 + round(60 * scale)), fill=(108, 140, 255, 255), width=line_width)
    draw.line(
        (inset + round(185 * scale), y1 + round(60 * scale),
         inset + round(265 * scale), y1 + round(60 * scale)),
        fill=(255, 159, 90, 255),
        width=line_width,
    )
    return image


def main() -> None:
    (WEB / "icons").mkdir(parents=True, exist_ok=True)
    WINDOWS_ICON.parent.mkdir(parents=True, exist_ok=True)

    make_icon(192).save(WEB / "icons" / "Icon-192.png", optimize=True)
    make_icon(512).save(WEB / "icons" / "Icon-512.png", optimize=True)
    make_icon(192, maskable=True).save(WEB / "icons" / "Icon-maskable-192.png", optimize=True)
    make_icon(512, maskable=True).save(WEB / "icons" / "Icon-maskable-512.png", optimize=True)
    make_icon(64).resize((32, 32), Image.Resampling.LANCZOS).save(WEB / "favicon.png", optimize=True)

    source = make_icon(512)
    source.save(
        WINDOWS_ICON,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("Generated AI Terminal web and Windows icons.")


if __name__ == "__main__":
    main()
