#!/usr/bin/env python3
"""Generate AppIcon variants from the exact logo served by AxonHub beta10.

Install Pillow to regenerate. No logo redraw, external font, or unstable logo.
The dark variant keeps the AH silhouette and teal, with white rather than black
arcs for visibility; the light variant preserves the deployed source verbatim.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'scripts/assets/axonhub-web-logo.jpg'


def variants():
    image = Image.open(SOURCE).convert('RGB').resize((1024, 1024), Image.Resampling.LANCZOS)
    dark = image.convert('RGBA')
    result = []
    for red, green, blue in image.get_flattened_data():
        # JPEG white/black antialiasing: neutral background becomes transparent,
        # neutral dark arcs become white; retain the actual teal logo pixels.
        if max(red, green, blue) - min(red, green, blue) < 40:
            result.append((255, 255, 255, 255 - max(red, green, blue)))
        else:
            result.append((red, green, blue, 255))
    dark.putdata(result)
    return image, dark


def main():
    light, dark = variants()
    root = ROOT / 'Axonhub/Assets.xcassets'
    for name in ['AppIcon', 'AppIconLight', 'AppIconDark']:
        folder = root / f'{name}.appiconset'
        light.save(folder / f'{name}.png')
        dark.save(folder / 'dark.png')
    print('All AppIcon sets regenerated from deployed AH logo (1024x1024, RGB/RGBA)')


if __name__ == '__main__':
    main()
