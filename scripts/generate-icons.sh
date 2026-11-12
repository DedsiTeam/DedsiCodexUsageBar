#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SRC_RAW="$ROOT/Assets/logo-source.png"
SRC_SQUARE="$ROOT/Assets/logo-square.png"
ICONSET="$ROOT/Resources/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$SRC_RAW" ]]; then
  echo "Missing source logo: $SRC_RAW" >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
try:
    from PIL import Image
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "-q"])
    from PIL import Image

src = Image.open("Assets/logo-source.png").convert("RGBA")
w, h = src.size
side = max(w, h)
# Solid white square background for macOS app icon.
canvas = Image.new("RGBA", (side, side), (255, 255, 255, 255))
canvas.paste(src, ((side - w) // 2, (side - h) // 2), src)
canvas.save("Assets/logo-square.png")
print(f"square={side}x{side}")

iconset = Path("Resources/AppIcon.iconset")
iconset.mkdir(parents=True, exist_ok=True)
# Clear old pngs
for p in iconset.glob("*.png"):
    p.unlink()

# name -> pixel size
sizes = {
    "icon_16x16.png": 16,
    "icon_16x16" + chr(64) + "2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32" + chr(64) + "2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128" + chr(64) + "2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256" + chr(64) + "2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512" + chr(64) + "2x.png": 1024,
}
for name, px in sizes.items():
    canvas.resize((px, px), Image.Resampling.LANCZOS).save(iconset / name)
canvas.resize((1024, 1024), Image.Resampling.LANCZOS).save("Assets/AppIcon-1024.png")
print(f"wrote {len(sizes)} iconset pngs")
PY

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Generated:"
echo "  $SRC_SQUARE"
echo "  $ICONSET"
echo "  $ICNS"
