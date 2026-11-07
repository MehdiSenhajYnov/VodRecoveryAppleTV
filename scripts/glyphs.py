"""Formes communes aux icônes VOD Recovery et MyApps (sobres, pour pièce sombre)."""
import math
from PIL import Image, ImageDraw, ImageFilter

INK = (236, 234, 246, 255)

def charcoal(w, h, glow=(150, 140, 220), glow_alpha=70):
    """Fond graphite très sombre avec une lueur froide discrète au centre-haut."""
    s = 8
    sw, sh = max(w // s, 2), max(h // s, 2)
    small = Image.new("RGB", (sw, sh))
    px = small.load()
    for y in range(sh):
        for x in range(sw):
            t = y / sh * 0.7 + x / sw * 0.3
            v = (int(30 * (1 - t) + 13 * t), int(30 * (1 - t) + 13 * t), int(38 * (1 - t) + 17 * t))
            px[x, y] = v
    img = small.resize((w, h), Image.BICUBIC).convert("RGBA")
    g = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse((w * 0.15, -h * 0.55, w * 0.85, h * 0.75), fill=(*glow, glow_alpha))
    return Image.alpha_composite(img, g.filter(ImageFilter.GaussianBlur(w / 9)))

def rounded_triangle(d, pts, r, fill):
    cx = sum(p[0] for p in pts) / 3
    cy = sum(p[1] for p in pts) / 3
    inset = []
    for x, y in pts:
        dx, dy = cx - x, cy - y
        L = math.hypot(dx, dy)
        inset.append((x + dx / L * r * 2.0, y + dy / L * r * 2.0))
    d.polygon(inset, fill=fill)
    for i in range(3):
        d.line([inset[i], inset[(i + 1) % 3]], fill=fill, width=int(r * 2))
        x, y = inset[i]
        d.ellipse((x - r, y - r, x + r, y + r), fill=fill)

def recovery_glyph(w, h, color=INK, scale=1.0):
    """Flèche circulaire (retour en arrière) autour d'un bouton lecture."""
    s = 4
    W, H = w * s, h * s
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = W / 2, H / 2
    r = H * 0.29 * scale
    width = H * 0.05 * scale
    start, end = 222, 145 + 360  # PIL : sens horaire depuis start
    d.arc((cx - r, cy - r, cx + r, cy + r), start=start, end=end, fill=color, width=int(width))
    p = lambda deg, rr=r: (cx + rr * math.cos(math.radians(deg)), cy + rr * math.sin(math.radians(deg)))
    # bout arrondi
    ex, ey = p(end % 360, r - width / 2)
    d.ellipse((ex - width / 2, ey - width / 2, ex + width / 2, ey + width / 2), fill=color)
    # pointe de flèche à l'autre bout, tangente au cercle (sens antihoraire)
    t = math.radians(start)
    bx, by = p(start, r - width / 2)
    tx, ty = math.sin(t), -math.cos(t)      # direction du mouvement
    nx, ny = math.cos(t), math.sin(t)       # direction radiale
    hl, hw = H * 0.10 * scale, H * 0.085 * scale
    base = (bx - tx * hl * 0.05, by - ty * hl * 0.05)
    tri = [(base[0] + tx * hl, base[1] + ty * hl),
           (base[0] + nx * hw, base[1] + ny * hw),
           (base[0] - nx * hw, base[1] - ny * hw)]
    rounded_triangle(d, tri, width * 0.18, color)
    # lecture
    pt = H * 0.13 * scale
    rounded_triangle(d, [(cx - pt * 0.62, cy - pt), (cx - pt * 0.62, cy + pt), (cx + pt * 0.98, cy)], pt * 0.09, color)
    return img.resize((w, h), Image.LANCZOS)

def grid_glyph(w, h, scale=1.0):
    """Quatre carrés arrondis : le premier plein, les autres en verre dépoli."""
    s = 4
    W, H = w * s, h * s
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cell, gap = H * 0.22 * scale, H * 0.06 * scale
    total = cell * 2 + gap
    x0, y0 = (W - total) / 2, (H - total) / 2
    for i in range(2):
        for j in range(2):
            x, y = x0 + j * (cell + gap), y0 + i * (cell + gap)
            a = 240 if (i, j) == (0, 0) else 90
            d.rounded_rectangle((x, y, x + cell, y + cell), radius=cell * 0.3, fill=(236, 234, 246, a))
    return img.resize((w, h), Image.LANCZOS)
