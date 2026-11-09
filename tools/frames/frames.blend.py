# Ludo Zing profile frames: thick cast frames with crests, banners and ornaments, lit like jewellery, rendered in
# Blender (Cycles) to transparent PNGs. The avatar tile is the rounded square -1..1 (corner radius 0.56, the game's
# rx 11.2/40); the canvas is -C..C (C = 1.75, Collection.FRAME_CANVAS) so ornaments break out of the square.
# Rebuild the game's frames (from the repo root):
#   SAMPLES=128 /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/frames/frames.blend.py -- /tmp/frames [ids...]
#   then each /tmp/frames/<id>.png -> godot/assets/frames/<id>.webp at 512 x 512 (WebP quality 88).
# rickshaw_band.png (the Rickshaw Art band) comes from paint_rickshaw.py.
import bpy, bmesh, math, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/frames"
ONLY = set(argv[1:])
HERE = os.path.dirname(os.path.abspath(__file__))
C = 1.75
RES = 1024
TR = 0.56

# ------------------------------------------------------------------------------------------------------------ scene
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(os.environ.get("SAMPLES", "128"))
    sc.cycles.use_denoising = True
    try:
        pr = bpy.context.preferences.addons["cycles"].preferences
        pr.compute_device_type = "METAL"; pr.get_devices()
        for dv in pr.devices: dv.use = True
        sc.cycles.device = "GPU"
    except Exception:
        pass
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.cycles.max_bounces = 12; sc.cycles.transmission_bounces = 12; sc.cycles.glossy_bounces = 8
    cam = bpy.data.cameras.new("cam"); cam.type = "ORTHO"; cam.ortho_scale = 2 * C
    co = bpy.data.objects.new("cam", cam); co.location = (0, 0, 10); sc.collection.objects.link(co); sc.camera = co
    # dark studio: a dim HDRI for variation, bright softboxes that show up in the metal
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    nt = w.node_tree; bg = nt.nodes["Background"]
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    f = os.path.join(bpy.utils.resource_path("LOCAL"), "datafiles", "studiolights", "world", "city.exr")
    if os.path.exists(f): env.image = bpy.data.images.load(f)
    nt.links.new(env.outputs["Color"], bg.inputs["Color"]); bg.inputs["Strength"].default_value = float(os.environ.get("WORLD", "0.14"))
    def area(name, loc, power, sx, sy=None, color=(1, 1, 1), shape="RECTANGLE"):
        l = bpy.data.lights.new(name, "AREA"); l.energy = power; l.shape = shape; l.size = sx; l.size_y = sy or sx; l.color = color
        o = bpy.data.objects.new(name, l); o.location = loc
        o.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(o)
    area("key", (-3.0, 3.5, 5.0), 520, 2.5, 4.0, (1.0, 0.96, 0.9))
    area("strip", (4.0, 1.0, 3.0), 260, 0.6, 5.0, (1.0, 1.0, 1.0))
    area("soft", (2.5, 4.5, 5.5), 260, 1.2, 3.0, (1.0, 0.98, 0.95))
    area("bounce", (0.5, -4.0, 1.5), 160, 5.0, 1.0, (1.0, 0.85, 0.65))
    # shadow catcher only under the avatar tile: the frame's shadow falls on the picture, never outside it (outside it
    # would be a grey smudge on the game's light backgrounds)
    bpy.ops.mesh.primitive_plane_add(size=2.0, location=(0, 0, 0))
    bpy.context.object.is_shadow_catcher = True
    return sc

# -------------------------------------------------------------------------------------------------------- materials
def lin(h):
    h = h.lstrip("#"); c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)

_mats = {}
def mat(key, color, metallic=0.0, rough=0.3, coat=0.0, trans=0.0, ior=1.5, emit=None, emit_s=0.0, spec=0.5, aniso=0.0):
    if key in _mats: return _mats[key]
    m = bpy.data.materials.new(key); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1); b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough; b.inputs["Coat Weight"].default_value = coat
    b.inputs["Transmission Weight"].default_value = trans; b.inputs["IOR"].default_value = ior
    b.inputs["Specular IOR Level"].default_value = spec
    if aniso: b.inputs["Anisotropic"].default_value = aniso
    if emit: b.inputs["Emission Color"].default_value = (*emit, 1); b.inputs["Emission Strength"].default_value = emit_s
    _mats[key] = m; return m

GOLD = lambda: mat("gold", lin("#ffbf3c"), 1, 0.13)
GOLD_D = lambda: mat("goldd", lin("#d98d1a"), 1, 0.2)
SILVER = lambda: mat("silver", lin("#eef1f6"), 1, 0.1)
CHROME = lambda: mat("chrome", lin("#ffffff"), 1, 0.03)
ROSE = lambda: mat("rose", lin("#f5a890"), 1, 0.12)
PLAT = lambda: mat("plat", lin("#f4f6fa"), 1, 0.06)
def enamel(h, coat=0.6): return mat("en" + h, lin(h), 0, 0.18, coat=coat)
def paint(h): return mat("pt" + h, lin(h), 0, 0.25, coat=1.0)
def gem(h, ior=1.77, glow=0.4):
    c = lin(h); return mat("gem" + h, c, 0, 0.0, trans=0.85, ior=ior, spec=1.0, emit=c, emit_s=glow)
DIA = lambda: mat("dia", (1, 1, 1), 0, 0.0, trans=0.9, ior=2.42, spec=1.0, emit=(0.85, 0.92, 1.0), emit_s=0.2)

def wood():
    if "wood" in _mats: return _mats["wood"]
    m = bpy.data.materials.new("wood"); m.use_nodes = True; nt = m.node_tree
    b = nt.nodes["Principled BSDF"]; b.inputs["Roughness"].default_value = 0.4; b.inputs["Coat Weight"].default_value = 0.35
    wv = nt.nodes.new("ShaderNodeTexWave"); wv.wave_type = "BANDS"; wv.inputs["Scale"].default_value = 9
    wv.inputs["Distortion"].default_value = 6; wv.inputs["Detail"].default_value = 3
    rp = nt.nodes.new("ShaderNodeValToRGB")
    rp.color_ramp.elements[0].color = (*lin("#4e2611"), 1); rp.color_ramp.elements[1].color = (*lin("#b36a33"), 1)
    nt.links.new(wv.outputs["Fac"], rp.inputs["Fac"]); nt.links.new(rp.outputs["Color"], b.inputs["Base Color"])
    _mats["wood"] = m; return m

def image_mat(key, path, rough=0.25, coat=1.0):
    m = bpy.data.materials.new(key); m.use_nodes = True; nt = m.node_tree
    b = nt.nodes["Principled BSDF"]; b.inputs["Roughness"].default_value = rough; b.inputs["Coat Weight"].default_value = coat
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(path)
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"]); return m

# --------------------------------------------------------------------------------------------------------- geometry
def link(o): bpy.context.scene.collection.objects.link(o); return o

def rr_path(off, n_corner=32, n_side=28):
    h = 1.0 - TR; r = TR + off; out = []
    sides = [((-h, h + r), (h, h + r), (0, 1)), ((h + r, h), (h + r, -h), (1, 0)),
             ((h, -h - r), (-h, -h - r), (0, -1)), ((-h - r, -h), (-h - r, h), (-1, 0))]
    arcs = [((h, h), 90, 0), ((h, -h), 0, -90), ((-h, -h), -90, -180), ((-h, h), 180, 90)]
    for i in range(4):
        (x0, y0), (x1, y1), n = sides[i]
        for k in range(n_side):
            t = k / n_side; out.append((Vector((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 0)), Vector((*n, 0))))
        (cx, cy), a0, a1 = arcs[i]
        for k in range(n_corner):
            a = math.radians(a0 + (a1 - a0) * k / n_corner); nv = Vector((math.cos(a), math.sin(a), 0))
            out.append((Vector((cx, cy, 0)) + nv * r, nv))
    return out

def sweep(name, prof, mats, mat_fn=None, uv_repeat=0):
    path = rr_path(0.0); me = bpy.data.meshes.new(name); bm = bmesh.new()
    uvl = bm.loops.layers.uv.new() if uv_repeat else None
    rows = [[bm.verts.new(p + n * d + Vector((0, 0, z))) for d, z in prof] for p, n in path]
    lens = [0.0]
    for i in range(1, len(path) + 1):
        lens.append(lens[-1] + (path[i % len(path)][0] - path[i - 1][0]).length)
    tot = lens[-1]
    for i in range(len(rows)):
        a, b = rows[i], rows[(i + 1) % len(rows)]
        for j in range(len(prof) - 1):
            f = bm.faces.new((a[j], b[j], b[j + 1], a[j + 1]))
            if mat_fn: f.material_index = mat_fn(path[i][0])
            if uvl:
                u0, u1 = lens[i] / tot * uv_repeat, lens[i + 1] / tot * uv_repeat
                d0 = min(d for d, z in prof); d1 = max(d for d, z in prof)
                v0, v1 = (prof[j][0] - d0) / (d1 - d0), (prof[j + 1][0] - d0) / (d1 - d0)
                for lp, uv in zip(f.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]):
                    lp[uvl].uv = uv
    bm.normal_update(); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    o = link(bpy.data.objects.new(name, me))
    for m in (mats if isinstance(mats, list) else [mats]): o.data.materials.append(m)
    return o

def arc(cx, cz, r, a0, a1, n=10):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)), cz + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]

def molding(i=-0.1, o=0.3, h=0.18, b=0.045):
    """Thick cast moulding: inner bead, deep cove, a flat field, raised outer roll and a step down."""
    p = [(i, 0.0)] + arc(i + b, h * 0.62, b, 180, 0, 10)
    m0 = i + 2 * b
    p += [(m0 + 0.015, h * 0.42), (m0 + 0.06, h * 0.38)]
    p += [(m0 + 0.08, h * 0.55), (o - 0.13, h * 0.55)]          # flat field
    rr = 0.055; p += arc(o - 0.07 - rr + rr, h * 0.62, rr, 180, 0, 10)
    p += [(o - 0.015, h * 0.25), (o, h * 0.2), (o, 0.0)]
    return p

def band(i, o, h, r=0.025):
    return [(i, 0), (i, h - r)] + arc(i + r, h - r, r, 180, 90, 5) + arc(o - r, h - r, r, 90, 0, 5) + [(o, 0)]

def bead_row(off, z, r, m, step=5):
    for p, n in rr_path(off)[::step]:
        sphere((p.x + n.x * 0, p.y, z), r, m, 16)

def sphere(loc, r, m, seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=seg // 2)
    o = bpy.context.object; o.data.materials.append(m); bpy.ops.object.shade_smooth(); return o

def extrude2d(name, pts, m, depth=0.05, bevel=0.025, z=0.0, res=3):
    cu = bpy.data.curves.new(name, "CURVE"); cu.dimensions = "2D"; cu.fill_mode = "BOTH"
    cu.extrude = depth; cu.bevel_depth = bevel; cu.bevel_resolution = res
    sp = cu.splines.new("POLY"); sp.points.add(len(pts) - 1)
    for k, (x, y) in enumerate(pts): sp.points[k].co = (x, y, 0, 1)
    sp.use_cyclic_u = True
    o = link(bpy.data.objects.new(name, cu)); o.location.z = z + depth + bevel; o.data.materials.append(m); return o

def tube(pts, m, r=0.03, z=0.15, cyclic=False):
    cu = bpy.data.curves.new("t", "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = r; cu.bevel_resolution = 5; cu.use_fill_caps = True
    sp = cu.splines.new("POLY"); sp.points.add(len(pts) - 1)
    for k, p in enumerate(pts):
        sp.points[k].co = (p[0], p[1], p[2] if len(p) > 2 else z, 1)
    sp.use_cyclic_u = cyclic
    o = link(bpy.data.objects.new("t", cu)); o.data.materials.append(m); return o

def lathe(prof, loc, m, axis="Y", scale=1.0, seg=40, rot_z=0.0):
    """Revolve [(r, h)] round an axis lying in the picture plane (a pawn standing up the screen)."""
    me = bpy.data.meshes.new("lathe"); bm = bmesh.new(); rings = []
    for r, h in prof:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            ring.append(bm.verts.new((r * math.cos(a) * scale, h * scale, r * math.sin(a) * scale)))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for k in range(seg):
            bm.faces.new((rings[j][k], rings[j][(k + 1) % seg], rings[j + 1][(k + 1) % seg], rings[j + 1][k]))
    bm.normal_update(); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    o = link(bpy.data.objects.new("lathe", me)); o.location = loc; o.rotation_euler.z = rot_z; o.data.materials.append(m); return o

PAWN = [(0.0, 0.0), (0.42, 0.0), (0.44, 0.06), (0.4, 0.12), (0.26, 0.2), (0.2, 0.32), (0.16, 0.55), (0.24, 0.62),
        (0.25, 0.66), (0.14, 0.7), (0.2, 0.8), (0.24, 0.9), (0.22, 1.0), (0.15, 1.08), (0.0, 1.12)]

def brilliant(loc, r, m, setting=None, h=None, rot=0.0, sq=1.0):
    me = bpy.data.meshes.new("gem"); bm = bmesh.new(); n = 16; h = h or r * 0.9
    tb = [bm.verts.new((r * .55 * math.cos(2 * math.pi * k / 8 + rot), r * .55 * math.sin(2 * math.pi * k / 8 + rot) * sq, h * .45)) for k in range(8)]
    st = [bm.verts.new((r * .8 * math.cos(2 * math.pi * (k + .5) / 8 + rot), r * .8 * math.sin(2 * math.pi * (k + .5) / 8 + rot) * sq, h * .3)) for k in range(8)]
    gd = [bm.verts.new((r * math.cos(2 * math.pi * k / n + rot), r * math.sin(2 * math.pi * k / n + rot) * sq, 0)) for k in range(n)]
    cu = bm.verts.new((0, 0, -h * .9)); bm.faces.new(tb)
    for k in range(8):
        bm.faces.new((tb[k], st[k], tb[(k + 1) % 8])); bm.faces.new((st[k], gd[2 * k + 1], gd[(2 * k + 2) % n]))
        bm.faces.new((tb[k], gd[2 * k], gd[2 * k + 1], st[k])); bm.faces.new((tb[(k + 1) % 8], st[k], gd[(2 * k + 2) % n]))
    for k in range(n): bm.faces.new((gd[k], cu, gd[(k + 1) % n]))
    bm.normal_update(); bm.to_mesh(me); bm.free()
    o = link(bpy.data.objects.new("gem", me)); o.location = loc; o.data.materials.append(m)
    if setting:
        bpy.ops.mesh.primitive_torus_add(major_radius=r * 1.04, minor_radius=r * 0.2, location=(loc[0], loc[1], loc[2]))
        t = bpy.context.object; t.scale.y = sq; t.data.materials.append(setting); bpy.ops.object.shade_smooth()
        for k in range(4):   # claws
            a = math.pi / 4 + k * math.pi / 2
            sphere((loc[0] + math.cos(a) * r * 0.95, loc[1] + math.sin(a) * r * 0.95 * sq, loc[2] + h * 0.35), r * 0.14, setting, 12)
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=0.02, location=(loc[0], loc[1], loc[2] - h * 0.95))
        c = bpy.context.object; c.scale.y = sq; c.data.materials.append(setting)
    return o

def leaf_pts(cx, cy, ang, ln, w, n=12):
    a = math.radians(ang); d = Vector((math.cos(a), math.sin(a))); nr = Vector((-d.y, d.x)); b = Vector((cx, cy)); pts = []
    for k in range(n + 1):
        t = k / n; pts.append(tuple(b + d * ln * t + nr * w * math.sin(math.pi * t) ** 0.9))
    for k in range(n - 1, 0, -1):
        t = k / n; pts.append(tuple(b + d * ln * t - nr * w * math.sin(math.pi * t) ** 0.9))
    return pts

def laurel(side, m, m2=None, count=8, r=1.32, a0=-70, a1=40, z=0.04, size=1.0):
    """A laurel branch curving up one side, leaves alternating out / in."""
    pts = []
    for k in range(count):
        t = k / (count - 1); a = math.radians(a0 + (a1 - a0) * t)
        x, y = side * r * math.cos(a), r * math.sin(a)
        pts.append((x, y, z + 0.03))
        tang = math.degrees(a) + 90
        tang = tang if side > 0 else 180 - tang
        for s, mm in ((1, m), (-1, m2 or m)):
            extrude2d("leaf", leaf_pts(x, y, tang + s * side * 40, 0.24 * size, 0.07 * size), mm, depth=0.02, bevel=0.02, z=z)
    tube(pts, m, 0.025)

def banner(y, w, h, face, edge, z=0.2):
    """A ribbon banner across the bottom with folded tails."""
    def ribbon(sc, m, zz):
        pts = []
        for k in range(21):
            t = k / 20; x = -w + 2 * w * t; pts.append((x * sc, y + 0.07 * math.cos(math.pi * (t - 0.5)) * -1 + h * sc / 2))
        for k in range(20, -1, -1):
            t = k / 20; x = -w + 2 * w * t; pts.append((x * sc, y + 0.07 * math.cos(math.pi * (t - 0.5)) * -1 - h * sc / 2))
        extrude2d("rib", pts, m, depth=0.03, bevel=0.02, z=zz)
    for s in (1, -1):   # tails
        tx = s * w * 1.02
        extrude2d("tail", [(tx, y + h * 0.4), (tx + s * 0.3, y + h * 0.4 + 0.02), (tx + s * 0.22, y - 0.02), (tx + s * 0.32, y - h * 0.55), (tx, y - h * 0.5)],
                  face, depth=0.02, bevel=0.018, z=z - 0.05)
    ribbon(1.04, edge, z - 0.02)
    ribbon(0.98, face, z)

def die(loc, s, rot, body, pip):
    bpy.ops.mesh.primitive_cube_add(size=s, location=loc, rotation=rot)
    o = bpy.context.object; o.data.materials.append(body)
    bv = o.modifiers.new("b", "BEVEL"); bv.width = s * 0.2; bv.segments = 8; bpy.ops.object.shade_smooth()
    M = o.matrix_world; q = s * 0.25; e = s * 0.5 + 0.002
    faces = {(0, 0, 1): [(0, 0), (q, q), (-q, -q), (q, -q), (-q, q)], (1, 0, 0): [(0, 0), (q, q), (-q, -q)],
             (0, -1, 0): [(q, q), (-q, -q)], (0, 1, 0): [(q, q), (-q, -q), (q, -q), (-q, q)], (-1, 0, 0): [(q, q), (-q, -q), (q, -q), (-q, q), (q, 0), (-q, 0)]}
    for (nx, ny, nz), ps in faces.items():
        for a, b in ps:
            if nz: lp = Vector((a, b, e * nz))
            elif nx: lp = Vector((e * nx, a, b))
            else: lp = Vector((a, e * ny, b))
            sphere(M @ lp, s * 0.085, pip, 12).scale.z = 0.5

def fleur(cx, cy, s, m, z=0.12):
    """A fleur-de-lis style crest built from three petals and a collar."""
    extrude2d("pc", leaf_pts(cx, cy - 0.05 * s, 90, 0.5 * s, 0.13 * s), m, depth=0.05, bevel=0.03, z=z)
    for sgn in (1, -1):
        pts = []
        for k in range(16):
            t = k / 15; a = math.radians(200 - 150 * t) if sgn > 0 else math.radians(-20 + 150 * t)
            pts.append((cx + sgn * (0.12 + 0.18 * math.sin(math.pi * t)) * s, cy + (-0.02 + 0.32 * t) * s))
        pts += [(cx + sgn * 0.05 * s, cy + 0.06 * s)]
        extrude2d("ps", pts, m, depth=0.04, bevel=0.03, z=z)
    extrude2d("coll", [(cx - 0.2 * s, cy - 0.04 * s), (cx + 0.2 * s, cy - 0.04 * s), (cx + 0.2 * s, cy + 0.04 * s), (cx - 0.2 * s, cy + 0.04 * s)], m, depth=0.05, bevel=0.03, z=z + 0.02)

def halo(r, color, strength=2.0):
    """A soft glow disc behind the frame (emissive, alpha-faded). Off: haze on light screens (HALO=1 to draw it)."""
    if os.environ.get("HALO") != "1":
        return None
    bpy.ops.mesh.primitive_circle_add(vertices=64, radius=r, fill_type="TRIFAN", location=(0, 0, -0.01))
    o = bpy.context.object
    m = bpy.data.materials.new("halo"); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); mix = nt.nodes.new("ShaderNodeMixShader")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent"); em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*lin(color), 1); em.inputs["Strength"].default_value = strength
    grad = nt.nodes.new("ShaderNodeTexGradient"); grad.gradient_type = "SPHERICAL"
    tc = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (1 / r, 1 / r, 1)
    rp = nt.nodes.new("ShaderNodeValToRGB"); rp.color_ramp.elements[0].position = 0.0; rp.color_ramp.elements[1].position = 0.55
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"]); nt.links.new(mp.outputs["Vector"], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Fac"], rp.inputs["Fac"]); nt.links.new(rp.outputs["Color"], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2]); nt.links.new(mix.outputs[0], out.inputs["Surface"])
    o.data.materials.append(m); o.visible_shadow = False; return o

CORNERS = [(1, 1), (-1, 1), (1, -1), (-1, -1)]
def corner_gems(metal, stone, r=0.12, k=0.93):
    for sx, sy in CORNERS:
        brilliant((sx * k, sy * k, 0.26), r, stone, setting=metal)

# ----------------------------------------------------------------------------------------------------------- frames
def f_classic():   # carved wood with brass corner caps
    sweep("ring", molding(-0.1, 0.26, 0.15), wood())
    b = mat("brass", lin("#d9a441"), 1, 0.25)
    for sx, sy in CORNERS:
        extrude2d("cap", [(sx * 0.98, sy * 0.62), (sx * 1.22, sy * 0.62), (sx * 1.22, sy * 1.22), (sx * 0.62, sy * 1.22), (sx * 0.62, sy * 0.98)][:], b, depth=0.02, bevel=0.02, z=0.12)
        sphere((sx * 1.02, sy * 1.02, 0.2), 0.05, b)

def f_silver():
    s = SILVER(); sap = gem("#2f6bff")
    sweep("ring", molding(-0.1, 0.3, 0.18), s)
    bead_row(0.27, 0.06, 0.03, s, 6)
    corner_gems(s, sap, 0.1)
    fleur(0, 1.3, 0.8, s)
    brilliant((0, 1.24, 0.3), 0.09, sap, setting=s)

def f_gold():
    g = GOLD(); gd = GOLD_D(); ruby = gem("#ff2a3d")
    sweep("ring", molding(-0.1, 0.32, 0.2), g)
    bead_row(0.3, 0.07, 0.035, gd, 5)
    corner_gems(g, ruby, 0.11)
    fleur(0, 1.34, 1.0, g)
    brilliant((0, 1.26, 0.34), 0.11, ruby, setting=g)
    fleur(0, -1.34, 0.7, g, z=0.12); bpy.context.object.rotation_euler.z = math.pi  # collar only flips; fine

def f_mint():      # Emerald: gold + green enamel, laurel branches, a big emerald crest
    g = GOLD(); e = enamel("#0a7a47"); em = gem("#11d983")
    sweep("ring", molding(-0.1, 0.32, 0.2), g)
    sweep("inlay", band(0.02, 0.16, 0.13, 0.015), e)
    laurel(1, g, GOLD_D()); laurel(-1, g, GOLD_D())
    corner_gems(g, em, 0.1)
    extrude2d("crestplate", [(0, 1.62), (0.26, 1.32), (0, 1.12), (-0.26, 1.32)], g, depth=0.05, bevel=0.03, z=0.12)
    brilliant((0, 1.34, 0.36), 0.17, em, setting=g, sq=1.25)

def crown(cx, cy, s, g, jewel, side_jewel):
    w, h = 0.5 * s, 0.38 * s
    pts = [(-w, 0), (w, 0), (w * 1.08, h * 0.95), (w * 0.62, h * 0.5), (w * 0.32, h * 1.05), (0, h * 0.6),
           (-w * 0.32, h * 1.05), (-w * 0.62, h * 0.5), (-w * 1.08, h * 0.95)]
    extrude2d("crown", [(cx + x, cy + y) for x, y in pts], g, depth=0.06 * s, bevel=0.035 * s, z=0.1)
    for x, y in [(w * 1.08, h * 0.95), (w * 0.32, h * 1.05), (-w * 0.32, h * 1.05), (-w * 1.08, h * 0.95)]:
        sphere((cx + x, cy + y + 0.03 * s, 0.24), 0.055 * s, g)
    extrude2d("cb", [(cx - w * 1.06, cy - 0.04), (cx + w * 1.06, cy - 0.04), (cx + w * 1.06, cy + h * 0.32), (cx - w * 1.06, cy + h * 0.32)], g, depth=0.07, bevel=0.035, z=0.12)
    brilliant((cx, cy + h * 0.14, 0.34), 0.09 * s, jewel, setting=g)
    for x in (-w * 0.62, w * 0.62):
        brilliant((cx + x, cy + h * 0.14, 0.32), 0.055 * s, side_jewel, setting=g)

def f_royal():
    g = GOLD(); velvet = mat("velvet", lin("#5b22c7"), 0, 0.55, coat=0.2)
    halo(1.7, "#9b6bff", 0.9)
    sweep("ring", band(-0.08, 0.3, 0.1, 0.03), velvet)
    sweep("lin", band(-0.1, -0.03, 0.17, 0.025), g); sweep("lout", band(0.24, 0.32, 0.17, 0.025), g)
    bead_row(0.11, 0.12, 0.028, g, 7)
    corner_gems(g, gem("#ff2a3d"), 0.1)
    crown(0, 1.13, 1.15, g, gem("#ff2a3d"), gem("#2f6bff"))
    banner(-1.28, 0.62, 0.2, mat("bannerp", lin("#6a2ee0"), 0, 0.3, coat=0.8), g)

def f_ludo():      # the board's colours, a die on top, a pawn on each lower corner
    g = GOLD()
    cols = [enamel("#ffc400"), enamel("#1f63d6"), enamel("#e0222a"), enamel("#14a052")]
    def side(p):
        if abs(p.y) >= abs(p.x): return 0 if p.y > 0 else 2
        return 1 if p.x > 0 else 3
    sweep("ring", band(-0.08, 0.3, 0.12, 0.035), cols, mat_fn=side)
    sweep("lin", band(-0.1, -0.03, 0.17, 0.025), g); sweep("lout", band(0.24, 0.32, 0.17, 0.025), g)
    for sx, sy in CORNERS:
        sphere((sx * 0.93, sy * 0.93, 0.2), 0.09, g)
    die((0, 1.24, 0.42), 0.42, (math.radians(28), math.radians(-32), math.radians(12)), mat("die", lin("#e3262d"), 0, 0.16, coat=1.0), mat("pip", lin("#ffffff"), 0, 0.3))
    for sx, c in ((1, "#1f63d6"), (-1, "#e0222a")):
        lathe(PAWN, (sx * 1.18, -1.42, 0.35), mat("pawn" + c, lin(c), 0, 0.12, coat=1.0), scale=0.42)
    for sx, c in ((1, "#14a052"), (-1, "#ffc400")):
        lathe(PAWN, (sx * 0.86, -1.5, 0.3), mat("pawn" + c, lin(c), 0, 0.12, coat=1.0), scale=0.34)

def f_rose():
    r = ROSE(); pk = gem("#ff4f8b", 1.6, 0.5); pearl = mat("pearl", lin("#fff4ee"), 0, 0.15, coat=1.0)
    halo(1.6, "#ff7aa8", 1.2)
    sweep("ring", molding(-0.1, 0.3, 0.18), r)
    bead_row(0.3, 0.05, 0.035, pearl, 6)
    def heart(cx, cy, s, n=48):
        return [(cx + 16 * math.sin(2 * math.pi * k / n) ** 3 * s / 17,
                 cy + (13 * math.cos(2 * math.pi * k / n) - 5 * math.cos(4 * math.pi * k / n) - 2 * math.cos(6 * math.pi * k / n) - math.cos(8 * math.pi * k / n)) * s / 17) for k in range(n)]
    extrude2d("hb", heart(0, 1.3, 0.42), r, depth=0.04, bevel=0.03, z=0.1)
    extrude2d("h", heart(0, 1.31, 0.33), pk, depth=0.05, bevel=0.03, z=0.17)
    for sx, sy in CORNERS:
        extrude2d("hc", heart(sx * 0.95, sy * 0.95, 0.17), pk, depth=0.04, bevel=0.025, z=0.16)
    for sx in (1, -1):
        for k in range(5):
            sphere((sx * (0.25 + k * 0.12), 1.28 - k * 0.035, 0.22), 0.04, pearl, 16)

def f_ice():
    s = SILVER(); ice = mat("ice", lin("#b8e6ff"), 0, 0.02, trans=1.0, ior=1.31, spec=1.0, emit=lin("#8fd8ff"), emit_s=0.25)
    frost = mat("frost", lin("#6cc2f0"), 0, 0.1, trans=0.5, ior=1.31, emit=lin("#9fdcff"), emit_s=0.2)
    halo(1.65, "#7fd3ff", 1.4)
    sweep("ring", band(-0.08, 0.3, 0.15, 0.04), frost)
    sweep("lin", band(-0.1, -0.04, 0.18, 0.025), s); sweep("lout", band(0.25, 0.32, 0.18, 0.025), s)
    def shard(cx, cy, ang, ln, w, z=0.12):
        a = math.radians(ang); d = Vector((math.cos(a), math.sin(a))); n = Vector((-d.y, d.x)); b = Vector((cx, cy))
        pts = [b - n * w, b + d * ln * 0.35 - n * w * 1.15, b + d * ln, b + d * ln * 0.35 + n * w * 1.15, b + n * w]
        extrude2d("sh", [tuple(p) for p in pts], ice, depth=0.05, bevel=0.035, z=z, res=1)
    for ang, ln, w, ox in [(90, 0.62, 0.11, 0), (72, 0.46, 0.085, 0.22), (108, 0.46, 0.085, -0.22), (55, 0.32, 0.065, 0.42), (125, 0.32, 0.065, -0.42)]:
        shard(ox, 1.16, ang, ln, w)
    for ang, ln, w, ox in [(-90, 0.4, 0.08, 0), (-72, 0.28, 0.06, 0.18), (-108, 0.28, 0.06, -0.18)]:
        shard(ox, -1.16, ang, ln, w)
    for sx, sy in CORNERS:   # snowflakes
        cx, cy = sx * 0.95, sy * 0.95
        for k in range(6):
            a = math.pi / 6 + k * math.pi / 3
            tube([(cx, cy), (cx + 0.15 * math.cos(a), cy + 0.15 * math.sin(a))], s, 0.02, 0.24)
        sphere((cx, cy, 0.25), 0.045, ice)

def f_wings():
    g = GOLD(); gd = GOLD_D(); ruby = gem("#ff2a3d")
    halo(1.75, "#ffc34d", 1.5)
    feather_w = mat("featherw", lin("#fff6e0"), 0, 0.3, coat=0.6)
    for side in (1, -1):
        piv = Vector((side * 1.1, 0.42))
        layers = [(gd, 0.95, 0.12, [84, 68, 52, 36, 20, 4, -12, -28], 0.0),
                  (g, 0.74, 0.11, [78, 62, 46, 30, 14, -2, -18], 0.025),
                  (feather_w, 0.5, 0.1, [72, 56, 40, 24, 8, -8], 0.05)]
        for m, ln, w, angs, dz in layers:
            for i, a in enumerate(angs):
                aa = a if side > 0 else 180 - a
                L = ln * (1 - 0.055 * i)
                extrude2d("f", leaf_pts(piv.x, piv.y, aa, L, w), m, depth=0.025, bevel=0.022, z=0.02 + dz)
    sweep("ring", molding(-0.1, 0.32, 0.2), g)
    bead_row(0.3, 0.07, 0.035, gd, 5)
    corner_gems(g, ruby, 0.1)
    fleur(0, 1.36, 1.05, g)
    brilliant((0, 1.28, 0.36), 0.13, ruby, setting=g)
    banner(-1.3, 0.55, 0.19, mat("bred", lin("#c8102e"), 0, 0.3, coat=0.8), g)

def f_diamond():
    p = PLAT(); d = DIA()
    halo(1.7, "#cfe6ff", 1.1)
    sweep("ring", band(-0.09, 0.3, 0.11, 0.035), p)
    sweep("lin", band(-0.11, -0.04, 0.16, 0.025), p); sweep("lout", band(0.24, 0.32, 0.16, 0.025), p)
    for pt, n in rr_path(0.105)[::5]:
        brilliant((pt.x, pt.y, 0.14), 0.075, d)
    # a tiara of diamonds on top
    for k, (x, sz) in enumerate([(0, 0.17), (0.3, 0.11), (-0.3, 0.11), (0.55, 0.08), (-0.55, 0.08)]):
        yy = 1.36 - abs(x) * 0.25
        extrude2d("prong", [(x - 0.05, 1.12), (x + 0.05, 1.12), (x + 0.02, yy), (x - 0.02, yy)], p, depth=0.03, bevel=0.02, z=0.1)
        brilliant((x, yy + sz * 0.6, 0.3), sz, d, setting=p)
    brilliant((0, -1.24, 0.25), 0.12, d, setting=p)

def f_rickshaw():  # Dhaka rickshaw art: painted flower band, chrome trim, a petal fan, plastic tassels
    band_m = image_mat("rick", os.path.join(HERE, "rickshaw_band.png"), 0.3, 1.0)
    ch = CHROME()
    sweep("ring", band(-0.08, 0.3, 0.12, 0.03), band_m, uv_repeat=5)
    sweep("lin", band(-0.1, -0.03, 0.17, 0.025), ch); sweep("lout", band(0.25, 0.32, 0.17, 0.025), ch)
    cols = ["#e8197a", "#18c3f0", "#ffd400", "#0aa84f", "#ff6a00"]
    # petal fan crest (like the rickshaw hood art), mirror in the middle
    for k in range(11):
        a = 15 + k * 15
        extrude2d("pet", leaf_pts(0, 1.2, a, 0.52, 0.11), paint(cols[k % len(cols)]), depth=0.025, bevel=0.02, z=0.06 + 0.004 * (k % 2))
    for k in range(9):
        a = 25 + k * 16.25
        extrude2d("pet2", leaf_pts(0, 1.2, a, 0.34, 0.08), paint(cols[(k + 2) % len(cols)]), depth=0.02, bevel=0.018, z=0.11)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.15, depth=0.04, location=(0, 1.22, 0.2)); bpy.context.object.data.materials.append(paint("#e3001b"))
    bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.05, location=(0, 1.22, 0.23)); bpy.context.object.data.materials.append(ch)
    # corner mirrors with painted petal rings
    for sx, sy in CORNERS:
        cx, cy = sx * 0.93, sy * 0.93
        for k in range(8):
            a = k * 45
            extrude2d("cp", leaf_pts(cx, cy, a, 0.17, 0.05), paint(cols[(k + (sx > 0)) % len(cols)]), depth=0.015, bevel=0.012, z=0.14)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.04, location=(cx, cy, 0.22)); bpy.context.object.data.materials.append(ch)
    # tassel fringe hanging from the bottom edge
    for k in range(13):
        x = -0.9 + k * 0.15
        c = paint(cols[k % len(cols)])
        top = -1.27; ln = 0.22 + 0.06 * math.sin(k * 1.3)
        tube([(x, top, 0.12), (x, top - ln, 0.12)], c, 0.018)
        sphere((x, top - ln - 0.03, 0.12), 0.045, c, 16)
    tube([(-0.95, -1.27, 0.14), (0.95, -1.27, 0.14)], ch, 0.03)

FRAMES = dict(classic=f_classic, silver=f_silver, gold=f_gold, mint=f_mint, royal=f_royal, ludo=f_ludo,
              rose=f_rose, ice=f_ice, wings=f_wings, diamond=f_diamond, rickshaw=f_rickshaw)

os.makedirs(OUT, exist_ok=True)
for fid, fn in FRAMES.items():
    if ONLY and fid not in ONLY: continue
    _mats.clear()
    sc = reset(); fn()
    sc.render.filepath = os.path.join(OUT, fid + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", fid)
