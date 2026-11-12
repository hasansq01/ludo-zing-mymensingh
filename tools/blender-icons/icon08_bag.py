# Icon 8: shopping bag - soft golden-orange bag with a puffy star, open top, cream rope handles on little rings.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector
sc = open_file(); col = new_icon('icon_bag')
for n in ('mat_bag', 'mat_bag_star', 'mat_bag_handle'):
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(bag=mat('mat_bag', '#eda03c', .55, .3), star=mat('mat_bag_star', '#f6c454', .45, .3), handle=mat('mat_bag_handle', '#f6e8d2', .55, .2))
sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'; sc.view_settings.exposure = -.6   # medium saturation, same as the house

WB, WT, D, H = 1.8, 1.55, 1.3, 1.5      # bottom width, top width, depth, height
me = bpy.data.meshes.new('bag_body'); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
for v in bm.verts:
    top = v.co.z > 0; v.co.x *= (WT if top else WB); v.co.y *= D; v.co.z = (v.co.z + .5) * H
topf = [f for f in bm.faces if f.normal.z > .9][0]
bmesh.ops.inset_region(bm, faces=[topf], thickness=.07, depth=0)
bmesh.ops.translate(bm, vec=(0, 0, -H * .7), verts=topf.verts)          # open top: a hollow bag
bm.to_mesh(me); bm.free()
body = finish(col, bpy.data.objects.new('bag_body', me), M['bag'], 0)
bv = body.modifiers.new('Bevel', 'BEVEL'); bv.width = .1; bv.segments = 8; bv.limit_method = 'ANGLE'
body.modifiers.new('Weighted Normal', 'WEIGHTED_NORMAL').keep_sharp = True

def star_pts(R, r, n=5):
    return [((R if k % 2 == 0 else r) * math.cos(math.radians(90 + 36 * k)), (R if k % 2 == 0 else r) * math.sin(math.radians(90 + 36 * k))) for k in range(2 * n)]
def rounded(pts, rad, segs=8):
    out = []; n = len(pts)
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        a, b = (p0 - p1).normalized(), (p2 - p1).normalized(); half = a.angle(b) / 2
        d = rad / math.tan(half); c = p1 + (a + b).normalized() * (rad / math.sin(half))
        s, e = p1 + a * d, p1 + b * d
        a0 = math.atan2(s.y - c.y, s.x - c.x); a1 = math.atan2(e.y - c.y, e.x - c.x); da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        out += [(c.x + rad * math.cos(a0 + da * k / segs), c.y + rad * math.sin(a0 + da * k / segs)) for k in range(segs + 1)]
    return out
star = prism(col, 'bag_star', rounded(star_pts(.56, .27), .06), .14, (0, -D / 2 - .03, H * .46), M['star'], 0)
b2 = star.modifiers.new('Bevel', 'BEVEL'); b2.width = .055; b2.segments = 8; b2.limit_method = 'ANGLE'; b2.angle_limit = math.radians(60)

def handle(tag, y):
    cu = bpy.data.curves.new(f'bag_handle_{tag}', 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = .055; cu.bevel_resolution = 6; cu.use_fill_caps = True
    s = cu.splines.new('POLY'); n = 32; s.points.add(n); hw, hh = .36, .6
    for k in range(n + 1):
        t = math.pi * k / n; s.points[k].co = (-hw * math.cos(t), y, H - .12 + hh * math.sin(t), 1)
    s.points[0].co = (-hw, y, H - .2 + .085, 1); s.points[n].co = (hw, y, H - .2 + .085, 1)
    cu.materials.append(M['handle']); o = bpy.data.objects.new(f'bag_handle_{tag}', cu); col.objects.link(o)
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_torus_add(major_radius=.085, minor_radius=.035, location=(sx * hw, y, H - .2), rotation=(math.pi / 2, 0, 0))
        finish(col, bpy.context.object, M['handle'], 0).name = f'bag_ring_{tag}'
handle('front', -D / 2 - .05); handle('back', D / 2 + .085)
aim_camera((2.4, -6.4, 2.7), (0, 0, 1.05), 70)
render('icon_bag', os.path.join(HERE, 'icon08_bag.png'))
