"""Génère les icônes tvOS (image stack 2 couches + Top Shelf) dans Resources/Assets.xcassets."""
import json, math, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(sys.argv[1]) / "Resources/Assets.xcassets"
BRAND = ROOT / "App Icon & Top Shelf Image.brandassets"
INFO = {"info": {"author": "xcode", "version": 1}}

def write(path, data):
    path.mkdir(parents=True, exist_ok=True)
    (path / "Contents.json").write_text(json.dumps(data, indent=2))

sys.path.insert(0, str(Path(__file__).parent))
from glyphs import charcoal, recovery_glyph

def back(w, h):
    return charcoal(w, h)

def front(w, h):
    return recovery_glyph(w, h)

def stack(name, size, scales):
    w, h = size
    base = BRAND / f"{name}.imagestack"
    write(base, {**INFO, "layers": [{"filename": "Front.imagestacklayer"}, {"filename": "Back.imagestacklayer"}]})
    for layer, fn in (("Front", front), ("Back", back)):
        lpath = base / f"{layer}.imagestacklayer"
        write(lpath, INFO)
        ipath = lpath / "Content.imageset"
        images = []
        for sc in scales:
            fname = f"{layer.lower()}@{sc}x.png"
            fn(w * sc, h * sc).save(ipath / fname) if ipath.exists() else (ipath.mkdir(parents=True), fn(w * sc, h * sc).save(ipath / fname))
            images.append({"idiom": "tv", "filename": fname, "scale": f"{sc}x"})
        write(ipath, {**INFO, "images": images})

def shelf(name, size):
    """Top Shelf : fond graphite, symbole centré."""
    w, h = size
    path = BRAND / f"{name}.imageset"
    path.mkdir(parents=True, exist_ok=True)
    images = []
    for sc in (1, 2):
        img = back(w * sc, h * sc)
        icon = front(h * sc, h * sc)
        img.alpha_composite(icon, ((w * sc - h * sc) // 2, 0))
        fname = f"shelf@{sc}x.png"
        img.convert("RGB").save(path / fname)
        images.append({"idiom": "tv", "filename": fname, "scale": f"{sc}x"})
    write(path, {**INFO, "images": images})

write(ROOT, INFO)
write(BRAND, {**INFO, "assets": [
    {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
    {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
    {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
    {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
]})
stack("App Icon", (400, 240), (1, 2))
stack("App Icon - App Store", (1280, 768), (1,))
shelf("Top Shelf Image", (1920, 720))
shelf("Top Shelf Image Wide", (2320, 720))
write(ROOT / "AccentColor.colorset", {**INFO, "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.68", "green": "0.64", "blue": "0.92", "alpha": "1.000"}}}]})
print("ok")
