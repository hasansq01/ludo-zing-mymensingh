# Ludo Zing UI art in the frames' 3D style (frames.blend.py's studio and helpers): place medals, achievement medals,
# nameplates and the Lucky Draw wheel. Numbers and names are drawn by the game on top.
#   /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/frames/ui_art.blend.py -- <out_dir> [names...]
# Outputs (PNG, transparent):
#   place_1..3        256 x 256   round medals: metal rim, enamel face (the game writes the place on it), a crown on 1st
#   medal_<ach>       320 x 320   achievement medals: ribbon, gold rim, enamel face in the achievement's colour, emblem
#   plate_<id>        768 x 192   nameplates in three slices: caps 192 px each end, a centre that stretches sideways
#   wheel_face        640 x 640   the spinning face: 8 enamel wedges (clockwise from 12 o'clock), gold dividers
#   wheel_rim         640 x 640   the fixed gold rim with 16 bulbs (lit by the game while it spins)
#   wheel_hub         256 x 256   the gold hub with a ruby
#   wheel_pointer     192 x 192   the jewelled pointer
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE, "frames.blend.py")).read().split("FRAMES = dict(")[0])
from mathutils import Vector

def no_catcher():
    for o in list(bpy.data.objects):
        if getattr(o, "is_shadow_catcher", False):
            bpy.data.objects.remove(o, do_unlink=True)

def circle(r, n=96, cx=0.0, cy=0.0):
    return [(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n)) for k in range(n)]

def face_mat(h, glow=0.22):
    c = lin(h)
    return mat("face" + h, c, 0, 0.22, coat=0.3, emit=c, emit_s=glow)

BRONZE = lambda: mat("bronze", lin("#d9884a"), 1, 0.2)

def curl(x0, y0, dirx, diry, length, m, r=0.03, z=0.12, turn=1):
    """A filigree scroll: runs along (dirx, diry), then rolls up into a spiral."""
    d = Vector((dirx, diry)).normalized(); nr = Vector((-d.y, d.x)) * turn
    pts = [tuple(Vector((x0, y0)) + d * (length * 0.6 * k / 15) + nr * (0.03 * math.sin(math.pi * k / 15))) for k in range(16)]
    c = Vector(pts[-1]) + nr * 0.08
    a0 = math.atan2(pts[-1][1] - c.y, pts[-1][0] - c.x)
    for k in range(1, 26):
        a = a0 - turn * k * 0.26
        rr = 0.08 * (1 - k / 32)
        pts.append((c.x + rr * math.cos(a), c.y + rr * math.sin(a)))
    return tube([(px, py, z) for px, py in pts], m, r)

# ------------------------------------------------------------------------------------------------------ place medals
def place(n):
    rim = {1: GOLD, 2: SILVER, 3: BRONZE}[n]()
    face = {1: "#c8102e", 2: "#1d5fd8", 3: "#1d8a4f"}[n]
    extrude2d("rim", circle(0.5), rim, depth=0.05, bevel=0.05, z=0.0, res=4)
    extrude2d("face", circle(0.38), face_mat(face), depth=0.03, bevel=0.02, z=0.16, res=3)
    for k in range(16):    # beads round the rim
        a = 2 * math.pi * k / 16
        sphere((0.45 * math.cos(a), 0.45 * math.sin(a), 0.22), 0.025, rim, 12)
    if n == 1:             # a small crown on the winner's medal
        w, h, y = 0.17, 0.1, 0.36
        extrude2d("crown", [(-w, y), (w, y), (w * 1.1, y + h), (w * 0.5, y + h * 0.5), (0, y + h * 1.2), (-w * 0.5, y + h * 0.5), (-w * 1.1, y + h)], rim, depth=0.03, bevel=0.025, z=0.24)

# ------------------------------------------------------------------------------------------------ achievement medals
ACH = {"first": "#e0a100", "streak": "#e5484d", "veteran": "#3b7be0", "pairs": "#2fa86b", "party": "#7c4dff", "coins": "#d98a0b"}
CUP = [(0.0, 0.0), (0.3, 0.0), (0.3, 0.05), (0.12, 0.1), (0.08, 0.3), (0.1, 0.36), (0.3, 0.5), (0.38, 0.85), (0.4, 0.92), (0.0, 0.92)]

def medal(ach):
    g = GOLD()
    col = ACH[ach]
    # ribbon: two tails from the top corners to the disc, the colour with a white stripe
    rib = mat("rib" + col, lin(col), 0, 0.3, coat=0.5)
    white = mat("ribw", lin("#fff4e0"), 0, 0.3, coat=0.5)
    for s in (1, -1):
        extrude2d("tail", [(s * 0.05, -0.05), (s * 0.34, 0.6), (s * 0.12, 0.6), (s * -0.08, 0.05)], rib, depth=0.015, bevel=0.012, z=0.0)
        extrude2d("stripe", [(s * 0.13, 0.2), (s * 0.26, 0.6), (s * 0.2, 0.6), (s * 0.07, 0.2)], white, depth=0.015, bevel=0.008, z=0.03)
    cy = -0.14
    extrude2d("rim", circle(0.4, cx=0, cy=cy), g, depth=0.05, bevel=0.045, z=0.08, res=4)
    extrude2d("face", circle(0.3, cx=0, cy=cy), face_mat(col), depth=0.03, bevel=0.02, z=0.24, res=3)
    zt = 0.36
    if ach == "first":
        lathe(CUP, (0, cy - 0.17, zt), g, scale=0.38)
        for s in (1, -1):
            tube([(s * 0.1, cy + 0.12, zt), (s * 0.19, cy + 0.12, zt), (s * 0.19, cy + 0.02, zt), (s * 0.08, cy - 0.03, zt)], g, 0.018)
    elif ach == "streak":
        outer = [(0.0, cy + 0.24), (0.1, cy + 0.08), (0.17, cy - 0.05), (0.15, cy - 0.15), (0.06, cy - 0.21), (-0.06, cy - 0.21), (-0.15, cy - 0.15), (-0.17, cy - 0.04), (-0.12, cy + 0.06), (-0.07, cy + 0.0), (-0.04, cy + 0.12)]
        extrude2d("flame", outer, g, depth=0.03, bevel=0.025, z=zt - 0.06)
        inner = [(0.0, cy + 0.06), (0.06, cy - 0.04), (0.06, cy - 0.12), (0.0, cy - 0.16), (-0.06, cy - 0.12), (-0.05, cy - 0.04)]
        extrude2d("flame2", inner, mat("flamein", lin("#ffd23a"), 0, 0.2, coat=0.8, emit=lin("#ffb000"), emit_s=0.4), depth=0.02, bevel=0.015, z=zt + 0.0)
    elif ach == "veteran":
        pts = [((0.22 if k % 2 == 0 else 0.095) * math.cos(math.radians(90 + 36 * k)), cy + (0.22 if k % 2 == 0 else 0.095) * math.sin(math.radians(90 + 36 * k))) for k in range(10)]
        extrude2d("star", pts, g, depth=0.04, bevel=0.03, z=zt - 0.06)
    elif ach == "pairs":
        lathe(PAWN, (-0.07, cy - 0.17, zt - 0.04), g, scale=0.3)
        lathe(PAWN, (0.07, cy - 0.19, zt + 0.02), GOLD_D(), scale=0.3)
    elif ach == "party":
        for x, sc_, dz, m in ((-0.12, 0.24, 0.0, GOLD_D()), (0.12, 0.24, 0.0, GOLD_D()), (0.0, 0.3, 0.05, g)):
            lathe(PAWN, (x, cy - 0.18, zt + dz), m, scale=sc_)
    elif ach == "coins":
        for k, (dx, dy) in enumerate(((-0.09, -0.05), (0.09, -0.05), (0.0, 0.06))):
            extrude2d("coin", circle(0.12, 48, dx, cy + dy), g if k == 2 else GOLD_D(), depth=0.02, bevel=0.02, z=zt - 0.05 + 0.04 * k, res=3)
            extrude2d("coinf", circle(0.075, 48, dx, cy + dy), GOLD(), depth=0.01, bevel=0.01, z=zt - 0.0 + 0.04 * k, res=2)

# -------------------------------------------------------------------------------------------------------- nameplates
# Plate units: x -2..2, y -0.5..0.5 on a 4.2 x 1.05 canvas (768 x 192). Caps live at |x| > 1.05; the centre is the
# same all along, so the game can stretch it.
PLATES = {
    "espresso": dict(band="wood", lip=lambda: mat("brass", lin("#d9a441"), 1, 0.22), cap="brass"),
    "ruby": dict(band="#c8102e", lip=GOLD, cap="ribbon"),
    "scroll": dict(band="gold", lip=GOLD_D, cap="scroll"),
    "velvet": dict(band="#5b22c7", lip=GOLD, cap="fleur"),
    "neon": dict(band="#141428", lip=None, cap="neon"),
    "paint": dict(band="#e8197a", lip=CHROME, cap="flower"),
    "crystal": dict(band="#0b2f7a", lip=PLAT, cap="diamond"),
}

def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]

def plate(pid):
    p = PLATES[pid]
    L = 1.75           # the band runs to x = +-L (the caps cover its ends)
    if p["band"] == "wood":
        band = wood()
    elif p["band"] == "gold":
        band = GOLD()
    elif pid == "neon":
        band = mat("glass", lin("#141428"), 0, 0.08, coat=1.0)
    else:
        band = face_mat(p["band"], 0.18)
    extrude2d("band", rect(-L, -0.3, L, 0.3), band, depth=0.04, bevel=0.04, z=0.0, res=3)
    if p["lip"]:
        lip = p["lip"]()
        for y in (0.3, -0.3):
            tube([(-L, y, 0.17), (L, y, 0.17)], lip, 0.04)
    if pid == "paint":      # yellow / green stripes along the band, as on the hood art
        for y, c in ((0.2, "#ffd400"), (0.14, "#0aa84f"), (-0.2, "#ffd400"), (-0.14, "#0aa84f")):
            extrude2d("str", rect(-L, y - 0.025, L, y + 0.025), paint(c), depth=0.005, bevel=0.004, z=0.16)
    cap = p["cap"]
    for s in (1, -1):
        x = s * 1.62
        if cap == "brass":
            b = p["lip"]()
            extrude2d("cap", rect(x - 0.3, -0.38, x + 0.3, 0.38), b, depth=0.04, bevel=0.04, z=0.1)
            for yy in (0.2, -0.2):
                sphere((x + s * 0.12, yy, 0.3), 0.045, b, 14)
        elif cap == "ribbon":
            dark = mat("ribdark", lin("#7a0a18"), 0, 0.3, coat=0.6)
            extrude2d("tail", [(x - s * 0.2, 0.32), (x + s * 0.42, 0.32), (x + s * 0.26, 0.0), (x + s * 0.42, -0.32), (x - s * 0.2, -0.32)], dark, depth=0.02, bevel=0.02, z=-0.05)
            tube([(x - s * 0.1, 0.36, 0.19), (x - s * 0.1, -0.36, 0.19)], GOLD(), 0.04)
        elif cap == "scroll":
            for yy, turn in ((0.28, 1), (-0.28, -1)):
                curl(x - s * 0.25, yy, s, 0, 0.6, GOLD(), r=0.04, z=0.19, turn=turn * s)
            sphere((x + s * 0.05, 0.0, 0.22), 0.08, gem("#ff2a3d"), 16)
        elif cap == "fleur":
            fleur(x, -0.24, 0.62, GOLD(), z=0.16)
        elif cap == "neon":
            tube([(x - s * 0.1, 0.32, 0.19)] + [(x + s * 0.14 * math.sin(math.radians(a)), 0.32 * math.cos(math.radians(a)), 0.19) for a in range(0, 181, 15)] + [(x - s * 0.1, -0.32, 0.19)],
                 mat("neonp", lin("#ff3fa8"), 0, 0.2, emit=lin("#ff3fa8"), emit_s=6.0), 0.045)
        elif cap == "flower":
            cols = ["#18c3f0", "#ffd400", "#0aa84f", "#ff6a00", "#ffffff"]
            for k in range(8):
                extrude2d("pet", leaf_pts(x, 0.0, k * 45, 0.3, 0.08), paint(cols[k % len(cols)]), depth=0.015, bevel=0.012, z=0.17)
            bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.05, location=(x, 0.0, 0.3)); bpy.context.object.data.materials.append(CHROME())
        elif cap == "diamond":
            for (dx, dy, r) in ((0.0, 0.0, 0.14), (s * 0.2, 0.18, 0.08), (s * 0.2, -0.18, 0.08)):
                brilliant((x + dx, dy, 0.3), r, DIA(), setting=PLAT())
    if pid == "neon":       # the glowing cyan tubes along the edges
        cy_ = mat("neonc", lin("#3ff3ff"), 0, 0.2, emit=lin("#3ff3ff"), emit_s=6.0)
        for y in (0.3, -0.3):
            tube([(-1.62, y, 0.19), (1.62, y, 0.19)], cy_, 0.045)

# -------------------------------------------------------------------------------------------------------------- wheel
# The wheel's units: its control is 220 across (the game's d), here 2.0 across: r_game / 110.
SEG = ["#e5484d", "#f4c430", "#2fa86b", "#3b7be0", "#e5484d", "#7c4dff", "#2fa86b", "#3b7be0"]

def wedge(k, r0, r1, gap=0.012, n=24):
    # clockwise from 12 o'clock: segment k spans [k*45, (k+1)*45] degrees clockwise -> math angle 90 - deg
    a0 = math.radians(90 - k * 45) - gap; a1 = math.radians(90 - (k + 1) * 45) + gap
    pts = [(r0 * math.cos(a0), r0 * math.sin(a0))]
    pts += [(r1 * math.cos(a0 + (a1 - a0) * j / n), r1 * math.sin(a0 + (a1 - a0) * j / n)) for j in range(n + 1)]
    pts += [(r0 * math.cos(a1), r0 * math.sin(a1))]
    return pts

def wheel_face():
    g = GOLD()
    extrude2d("back", circle(0.93), GOLD_D(), depth=0.02, bevel=0.01, z=-0.05)
    for k in range(8):
        extrude2d("w", wedge(k, 0.05, 0.9), face_mat(SEG[k], 0.5), depth=0.03, bevel=0.035, z=0.0, res=4)
    for k in range(8):
        a = math.radians(90 - k * 45)
        tube([(0.17 * math.cos(a), 0.17 * math.sin(a), 0.1), (0.9 * math.cos(a), 0.9 * math.sin(a), 0.1)], g, 0.012)

def wheel_rim():
    g = GOLD()
    bpy.ops.mesh.primitive_torus_add(major_radius=0.94, minor_radius=0.06, location=(0, 0, 0.08), major_segments=160, minor_segments=24)
    o = bpy.context.object; o.data.materials.append(g); bpy.ops.object.shade_smooth()
    bulb = mat("bulb", lin("#fff1cc"), 0, 0.05, trans=0.6, ior=1.45, emit=lin("#ffe6a8"), emit_s=0.6)
    for k in range(16):
        a = math.radians(90 - k * 22.5)
        x, y = 0.94 * math.cos(a), 0.94 * math.sin(a)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.034, depth=0.02, location=(x, y, 0.13)); bpy.context.object.data.materials.append(GOLD_D())
        sphere((x, y, 0.16), 0.028, bulb, 16)

def wheel_hub():
    g = GOLD()
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, location=(0, 0, 0), segments=48, ring_count=24)
    o = bpy.context.object; o.scale.z = 0.4; o.data.materials.append(g); bpy.ops.object.shade_smooth()
    extrude2d("ring", circle(0.56), mat("hubw", lin("#fff4e6"), 0, 0.2, coat=0.8), depth=0.02, bevel=0.02, z=-0.08)
    brilliant((0, 0, 0.24), 0.22, gem("#ff2a3d"), setting=g)

def wheel_pointer():
    g = GOLD()
    pts = [(0.0, -0.75), (0.32, 0.05)] + [(0.34 * math.cos(math.radians(a)), 0.15 + 0.34 * math.sin(math.radians(a))) for a in range(0, 181, 12)] + [(-0.32, 0.05)]
    extrude2d("ptr", pts, g, depth=0.05, bevel=0.05, z=0.0, res=4)
    brilliant((0, 0.15, 0.2), 0.17, gem("#ff2a3d"), setting=g)

JOBS = {}
for n in (1, 2, 3): JOBS[f"place_{n}"] = (0.55, 256, 256, lambda n=n: place(n))
for a in ACH: JOBS[f"medal_{a}"] = (0.66, 320, 320, lambda a=a: medal(a))
for pid in PLATES: JOBS[f"plate_{pid}"] = (2.1, 768, 192, lambda pid=pid: plate(pid))
JOBS["wheel_face"] = (1.0, 640, 640, wheel_face)
JOBS["wheel_rim"] = (1.0, 640, 640, wheel_rim)
JOBS["wheel_hub"] = (0.62, 256, 256, wheel_hub)
JOBS["wheel_pointer"] = (0.85, 192, 192, wheel_pointer)

os.makedirs(OUT, exist_ok=True)
for name, (half, rx, ry, fn) in JOBS.items():
    if ONLY and name not in ONLY:
        continue
    _mats.clear()
    C = half
    sc = reset()
    no_catcher()
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    sc.camera.data.ortho_scale = 2 * half
    fn()
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", name)
