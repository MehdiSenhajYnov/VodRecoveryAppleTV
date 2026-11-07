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

def back(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.6 + y / h * 0.4)
            r = int(120 * (1 - t) + 20 * t); g = int(60 * (1 - t) + 18 * t); b = int(235 * (1 - t) + 70 * t)
            px[x, y] = (r, g, b)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse((-w * 0.2, -h * 0.5, w * 0.7, h * 0.7), fill=(190, 120, 255, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(w / 12))
    img = Image.alpha_composite(img.convert("RGBA"), glow)
    return img

def front(w, h):
    s = 4  # supersampling
    W, H = w * s, h * s
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy, r = W / 2, H / 2, H * 0.30
    width = int(H * 0.055)
    # flèche circulaire « récupération »
    d.arc((cx - r, cy - r, cx + r, cy + r), start=-35, end=265, fill=(255, 255, 255, 255), width=width)
    a = math.radians(-35)
    tip = (cx + r * math.cos(a), cy + r * math.sin(a))
    head = H * 0.09
    d.polygon([
        (tip[0] - head * 0.9, tip[1] - head * 0.9 + width * 0.2),
        (tip[0] + head * 0.9, tip[1] - head * 0.3),
        (tip[0] + head * 0.05, tip[1] + head * 1.0),
    ], fill=(255, 255, 255, 255))
    # triangle « lecture »
    t = H * 0.16
    d.polygon([(cx - t * 0.7, cy - t), (cx - t * 0.7, cy + t), (cx + t * 1.05, cy)], fill=(255, 255, 255, 255))
    return img.resize((w, h), Image.LANCZOS)

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
    w, h = size
    path = BRAND / f"{name}.imageset"
    path.mkdir(parents=True, exist_ok=True)
    images = []
    for sc in (1, 2):
        img = back(w * sc // 4, h * sc // 4).resize((w * sc, h * sc), Image.BICUBIC)
        icon = front(h * sc, h * sc)
        img.alpha_composite(icon, (int(w * sc * 0.08), 0))
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
write(ROOT / "AccentColor.colorset", {**INFO, "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.62", "green": "0.40", "blue": "1.00", "alpha": "1.000"}}}]})
print("ok")
