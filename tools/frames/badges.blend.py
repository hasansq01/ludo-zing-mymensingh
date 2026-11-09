# Ludo Zing level badges: the art behind the level number (the game draws the digits). One PNG per tier, rendered
# with the frames' studio (frames.blend.py's helpers). Shapes:
#   hex_<tier>    a wide hexagon gem: a metal rim round an enamel face, room for three digits
#   star_<tier>   a cast star with a ribbon across it (the number goes on the ribbon)
# Tiers follow the level: bronze 1-9, silver 10-24, gold 25-49, ruby 50-99, diamond 100+.
#   /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/frames/badges.blend.py -- <out_dir> [names...]
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "frames.blend.py")).read().split("FRAMES = dict(")[0]
exec(src)
C = 0.62            # half canvas: the badge fills it
RES = 512

TIERS = {
    "bronze": dict(rim=lambda: mat("bronze", lin("#d9884a"), 1, 0.2), face="#9a4214", gem=None),
    "silver": dict(rim=SILVER, face="#1c5ee0", gem=None),
    "gold": dict(rim=GOLD, face="#d81f2b", gem="#ffd23a"),
    "ruby": dict(rim=GOLD, face="#7a2cf0", gem="#ff2a3d"),
    "diamond": dict(rim=PLAT, face="#0b3a9a", gem="#ffffff"),
}

def face_mat(h):
    """Glossy enamel that keeps its colour (a little glow of its own, a thin coat)."""
    c = lin(h)
    return mat("face" + h, c, 0, 0.22, coat=0.25, emit=c, emit_s=0.25)

def hexagon(r, n=6, rot=0.0, sx=1.12):
    return [(sx * r * math.cos(math.radians(rot + 360 * k / n)), r * math.sin(math.radians(rot + 360 * k / n))) for k in range(n)]

def hex_badge(t):
    rim = t["rim"]()
    extrude2d("rim", hexagon(0.5), rim, depth=0.06, bevel=0.05, z=0.0, res=4)
    extrude2d("face", hexagon(0.39), face_mat(t["face"]), depth=0.03, bevel=0.025, z=0.17, res=3)
    if t["gem"]:   # a stone on top of the rim
        brilliant((0, 0.5, 0.3), 0.075, DIA() if t["gem"] == "#ffffff" else gem(t["gem"]), setting=rim)

def star_pts(r_out, r_in, n=5):
    return [((r_out if k % 2 == 0 else r_in) * math.cos(math.radians(90 + 180 * k / n)),
             (r_out if k % 2 == 0 else r_in) * math.sin(math.radians(90 + 180 * k / n))) for k in range(2 * n)]

def star_badge(t):
    rim = t["rim"]()
    extrude2d("star", star_pts(0.55, 0.26), rim, depth=0.07, bevel=0.05, z=0.0, res=4)
    extrude2d("starface", star_pts(0.42, 0.2), face_mat(t["face"]), depth=0.05, bevel=0.02, z=0.08, res=3)
    # the ribbon across the star's middle carries the number
    w, h, y = 0.5, 0.2, -0.06
    for s in (1, -1):
        extrude2d("tail", [(s * w, y + h * 0.45), (s * (w + 0.13), y + h * 0.4), (s * (w + 0.08), y), (s * (w + 0.13), y - h * 0.45), (s * w, y - h * 0.45)],
                  mat("ribd", lin("#8a1a1f"), 0, 0.3, coat=0.6), depth=0.02, bevel=0.015, z=0.14)
    extrude2d("rib", [(-w, y - h / 2), (w, y - h / 2), (w, y + h / 2), (-w, y + h / 2)], mat("rib", lin("#d8262c"), 0, 0.25, coat=0.8),
              depth=0.03, bevel=0.02, z=0.18)

SHAPES = {"hex": hex_badge, "star": star_badge}
os.makedirs(OUT, exist_ok=True)
for shape, fn in SHAPES.items():
    for tier, t in TIERS.items():
        name = f"{shape}_{tier}"
        if ONLY and name not in ONLY:
            continue
        _mats.clear()
        sc = reset()
        sc.render.resolution_x = sc.render.resolution_y = RES
        for o in list(bpy.data.objects):          # no shadow catcher: a badge sits on any background
            if getattr(o, "is_shadow_catcher", False):
                bpy.data.objects.remove(o, do_unlink=True)
        fn(t)
        sc.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED", name)
