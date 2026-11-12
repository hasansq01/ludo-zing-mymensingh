# Icon 3: play button - thick rounded cream tile with a soft raised orange play triangle.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector
sc = open_file(); col = new_icon('icon_play')
for n in ('mat_play_tile', 'mat_play_orange'):
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(tile=mat('mat_play_tile', '#f6ead6', .55, .25), orange=mat('mat_play_orange', '#f39237', .45, .3))

def rounded(pts, r, segs=14):
    """Outline of a polygon with every corner rounded by radius r."""
    out = []; n = len(pts)
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        a, b = (p0 - p1).normalized(), (p2 - p1).normalized()
        half = a.angle(b) / 2; dist = r / math.tan(half)
        c = p1 + (a + b).normalized() * (r / math.sin(half))
        s, e = p1 + a * dist, p1 + b * dist
        a0 = math.atan2(s.y - c.y, s.x - c.x); a1 = math.atan2(e.y - c.y, e.x - c.x)
        da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        for k in range(segs + 1):
            t = a0 + da * k / segs; out.append((c.x + r * math.cos(t), c.y + r * math.sin(t)))
    return out

def slab(name, outline, z0, h, m, bevel, loc=(0, 0, 0)):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((x, y, z0)) for x, y in outline])
    if f.normal.z < 0: f.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, 0, h), verts=[v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.location = loc
    finish(col, o, m, 0)
    b = o.modifiers.new('Bevel', 'BEVEL'); b.width = bevel; b.segments = 8; b.limit_method = 'ANGLE'; b.angle_limit = math.radians(60)
    o.modifiers.new('Weighted Normal', 'WEIGHTED_NORMAL').keep_sharp = False
    return o

S, R, TH = 2.3, .52, .42                          # tile size, corner radius, thickness
h = S / 2
tile = slab('play_tile', rounded([(-h, -h), (h, -h), (h, h), (-h, h)], R), 0, TH, M['tile'], .16)
# play triangle, pointing right, nudged right so it looks centred
T = 1.18; cx = .1
tri = [(cx - T * .42, -T / 2), (cx + T * .58, 0), (cx - T * .42, T / 2)]
play = slab('play_triangle', rounded(tri, .2), TH - .02, .24, M['orange'], .1)

# stand the button up, leaning back a little, turned slightly to show its thickness
rig = bpy.data.objects.new('play_button', None); col.objects.link(rig)
for o in (tile, play): o.parent = rig
rig.rotation_euler = (math.radians(78), 0, 0); rig.location = (0, 0, 0)
aim_camera((0, -6.4, 1.6), (0, 0, 0), 64)
render('icon_play', os.path.join(HERE, 'icon03_play.png'))
