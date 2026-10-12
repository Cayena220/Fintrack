"""Generates FinTrack's app icons from 1024px renders of the branding SVGs.

1. Render logo.svg and foreground.svg to logo-1024.png and foreground-1024.png
   (transparent background), e.g. with headless Chrome:
     chrome --headless=new --default-background-color=00000000 --window-size=1024,1024
            --screenshot=logo-1024.png page.html   (page.html shows the SVG at 1024px)
2. pip install pillow
3. python make_icons.py <dir with the PNGs and logo.svg> <repo root>

Writes the Windows .ico, Android launcher icons, the in-app logo and the
website icons. foreground.svg is the Android adaptive-icon layer.
"""
import shutil
import sys
from pathlib import Path

from PIL import Image

render_dir = Path(sys.argv[1])
repo = Path(sys.argv[2])

logo = Image.open(render_dir / "logo-1024.png").convert("RGBA")
foreground = Image.open(render_dir / "foreground-1024.png").convert("RGBA")
assert logo.getpixel((2, 2))[3] == 0, "logo corners should be transparent"


def resized(img, size):
    return img.resize((size, size), Image.LANCZOS)


written = []


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    written.append(path.relative_to(repo))


# Windows: multi-resolution .ico used by the exe, taskbar and installer.
ico = repo / "app/windows/runner/resources/app_icon.ico"
logo.save(ico, sizes=[(s, s) for s in (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)])
written.append(ico.relative_to(repo))

# Android legacy launcher icons (pre-8.0) and adaptive foregrounds (108dp canvas).
res = repo / "app/android/app/src/main/res"
for density, legacy, adaptive in [
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]:
    save(resized(logo, legacy), res / f"mipmap-{density}/ic_launcher.png")
    save(resized(foreground, adaptive), res / f"mipmap-{density}/ic_launcher_foreground.png")

# In-app logo (sign-in screen).
save(resized(logo, 512), repo / "app/assets/logo.png")

# Website.
save(resized(logo, 180), repo / "website/assets/apple-touch-icon.png")
save(resized(logo, 512), repo / "website/assets/icon-512.png")
shutil.copyfile(render_dir / "logo.svg", repo / "website/assets/logo.svg")
written.append(Path("website/assets/logo.svg"))

for p in written:
    print("wrote", p)
