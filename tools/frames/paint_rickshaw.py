"""The rickshaw-art band texture: hot pink ground, bold flowers with leaves, dotted borders (Dhaka rickshaw painting
colours). Tiles horizontally. Usage: python3 paint_rickshaw.py out.png"""
import sys, math
from PIL import Image, ImageDraw, ImageFilter

W, H = 1024, 256
im = Image.new("RGB", (W, H), "#e8197a")
d = ImageDraw.Draw(im)
# borders: yellow / green stripes with white dots
d.rectangle([0, 0, W, 34], fill="#ffd400"); d.rectangle([0, 34, W, 44], fill="#0aa84f")
d.rectangle([0, H - 34, W, H], fill="#ffd400"); d.rectangle([0, H - 44, W, H - 34], fill="#0aa84f")
for x in range(8, W, 32):
    d.ellipse([x, 10, x + 14, 24], fill="#e8197a"); d.ellipse([x, H - 24, x + 14, H - 10], fill="#e8197a")

def leaf(cx, cy, ang, ln, w, col):
    a = math.radians(ang); dx, dy = math.cos(a), math.sin(a); nx, ny = -dy, dx
    pts = []
    for k in range(13):
        t = k / 12; ww = w * math.sin(math.pi * t)
        pts.append((cx + dx * ln * t + nx * ww, cy + dy * ln * t + ny * ww))
    for k in range(12, -1, -1):
        t = k / 12; ww = w * math.sin(math.pi * t)
        pts.append((cx + dx * ln * t - nx * ww, cy + dy * ln * t - ny * ww))
    d.polygon(pts, fill=col, outline="#1a1a1a")
    d.line([(cx, cy), (cx + dx * ln * 0.85, cy + dy * ln * 0.85)], fill="#1a1a1a", width=2)

def flower(cx, cy, r, petal, center, n=8):
    for k in range(n):
        a = 2 * math.pi * k / n
        px, py = cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62
        d.ellipse([px - r * 0.42, py - r * 0.42, px + r * 0.42, py + r * 0.42], fill=petal, outline="#1a1a1a", width=2)
    d.ellipse([cx - r * 0.42, cy - r * 0.42, cx + r * 0.42, cy + r * 0.42], fill=center, outline="#1a1a1a", width=2)
    d.ellipse([cx - r * 0.18, cy - r * 0.18, cx + r * 0.18, cy + r * 0.18], fill="#ffffff")

palette = [("#ffd400", "#e3001b"), ("#18c3f0", "#ffd400"), ("#ffffff", "#e3001b"), ("#ff8a00", "#0aa84f")]
n = 4
for i in range(n):
    cx = W * (i + 0.5) / n; cy = H / 2
    for ang in (-35, 35, 145, 215):
        leaf(cx, cy, ang, 70, 16, "#0aa84f")
    p, c = palette[i % len(palette)]
    flower(cx, cy, 52, p, c)
    # small buds between the flowers
    bx = cx + W / n / 2
    d.ellipse([bx - 13, cy - 13, bx + 13, cy + 13], fill="#18c3f0", outline="#1a1a1a", width=2)
    d.ellipse([bx - 5, cy - 5, bx + 5, cy + 5], fill="#ffffff")
    for dy in (-48, 48):
        d.ellipse([bx - 7, cy + dy - 7, bx + 7, cy + dy + 7], fill="#ffd400", outline="#1a1a1a", width=2)
im = im.filter(ImageFilter.SMOOTH)
im.save(sys.argv[1])
