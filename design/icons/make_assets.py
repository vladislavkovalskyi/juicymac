"""Builds the app's asset catalog from the Blender renders.

Usage: python3 design/icons/make_assets.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RENDERS = os.path.join(ROOT, "design", "icons", "out")
CATALOG = os.path.join(ROOT, "App", "Resources", "Assets.xcassets")
ICONS = ["juice", "cpu", "memory", "disk", "fan", "temp", "battery", "bolt", "slice"]


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def squircle(size, radius):
    """Apple-style rounded square mask."""
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=radius * 4, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def gradient(size, stops):
    """Diagonal gradient through a list of (position, rgb) stops."""
    base = Image.new("RGB", (size, size))
    pixels = base.load()
    for y in range(size):
        for x in range(size):
            t = (x / size * 0.55 + y / size * 0.45)
            for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
                if p0 <= t <= p1:
                    k = (t - p0) / max(1e-6, p1 - p0)
                    pixels[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3))
                    break
            else:
                pixels[x, y] = stops[-1][1] if t > stops[-1][0] else stops[0][1]
    return base


def app_icon(size=1024):
    art = int(size * 0.805)          # macOS leaves a margin around the artwork
    radius = int(art * 0.2237)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    tile = gradient(art, [(0.0, (255, 154, 46)), (0.45, (255, 61, 127)), (1.0, (122, 43, 255))])
    tile.putalpha(squircle(art, radius))

    # Soft highlight along the top edge, the way glossy macOS icons catch light.
    sheen = Image.new("L", (art, art), 0)
    ImageDraw.Draw(sheen).ellipse([-art * 0.3, -art * 0.75, art * 1.3, art * 0.42], fill=90)
    tile = Image.alpha_composite(tile, Image.merge("RGBA", (
        Image.new("L", (art, art), 255), Image.new("L", (art, art), 255),
        Image.new("L", (art, art), 255), sheen.filter(ImageFilter.GaussianBlur(art * 0.04)),
    )).convert("RGBA").resize((art, art)))
    tile.putalpha(squircle(art, radius))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 110), (int((size - art) / 2), int((size - art) / 2) + int(art * 0.03)), squircle(art, radius))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(size * 0.022)))
    canvas.paste(tile, (int((size - art) / 2), int((size - art) / 2)), tile)

    glass = Image.open(os.path.join(RENDERS, "juice.png")).convert("RGBA")
    glass = glass.resize((int(art * 0.78), int(art * 0.78)), Image.LANCZOS)
    canvas.alpha_composite(glass, (int((size - glass.width) / 2), int((size - glass.height) / 2)))
    return canvas


def main():
    write(os.path.join(CATALOG, "Contents.json"), {"info": {"author": "xcode", "version": 1}})

    for name in ICONS:
        source = Image.open(os.path.join(RENDERS, f"{name}.png")).convert("RGBA")
        folder = os.path.join(CATALOG, f"icon-{name}.imageset")
        os.makedirs(folder, exist_ok=True)
        images = []
        for scale in (1, 2):
            side = 256 * scale
            filename = f"icon-{name}@{scale}x.png" if scale > 1 else f"icon-{name}.png"
            source.resize((side, side), Image.LANCZOS).save(os.path.join(folder, filename))
            images.append({"filename": filename, "idiom": "universal", "scale": f"{scale}x"})
        write(os.path.join(folder, "Contents.json"), {"images": images, "info": {"author": "xcode", "version": 1}})

    folder = os.path.join(CATALOG, "AppIcon.appiconset")
    os.makedirs(folder, exist_ok=True)
    icon = app_icon()
    icon.save(os.path.join(folder, "AppIcon-1024.png"))
    write(os.path.join(folder, "Contents.json"), {
        "images": [{"filename": "AppIcon-1024.png", "idiom": "mac", "scale": "1x", "size": "512x512"}],
        "info": {"author": "xcode", "version": 1},
    })
    print(f"Wrote {len(ICONS)} icons and the app icon to {CATALOG}")


if __name__ == "__main__":
    main()
