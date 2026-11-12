# Icon 9: trophy - soft gold cup with a puffy star, loop handles, stem and foot, on a brown base with a gold plate.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector
sc = open_file(); col = new_icon('icon_trophy')
for n in ('mat_trophy_gold', 'mat_trophy_star', 'mat_trophy_base'):
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(gold=mat('mat_trophy_gold', '#eea432', .38, .25), star=mat('mat_trophy_star', '#f7c650', .4, .3), base=mat('mat_trophy_base', '#8c5333', .55, .2))
sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'; sc.view_settings.exposure = -.6   # medium saturation

# base: a soft brown block, a little narrower at the top
me = bpy.data.meshes.new('trophy_base'); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
for v in bm.verts:
    top = v.co.z > 0; v.co.x *= (1.25 if top else 1.5); v.co.y *= (.85 if top else 1.0); v.co.z = (v.co.z + .5) * .36
bm.to_mesh(me); bm.free()
base = finish(col, bpy.data.objects.new('trophy_base', me), M['base'], .07, 6)
plate = box(col, 'trophy_plate', (.62, .05, .14), (0, -.47, .18), M['gold'], .025, (math.atan2(.075, .36), 0, 0))
# gold cup: foot, stem with a knob, open bowl
lathe(col, 'trophy_foot', [(0, .36), (.44, .36), (.46, .41), (.4, .46), (.22, .55), (.15, .62), (0, .63)], (0, 0, 0), M['gold'])
lathe(col, 'trophy_stem', [(0, .6), (.13, .6), (.12, .74), (.19, .84), (.13, .94), (.17, 1.04), (0, 1.08)], (0, 0, 0), M['gold'])
lathe(col, 'trophy_cup', [(0, 1.02), (.24, 1.04), (.46, 1.18), (.63, 1.5), (.72, 1.9), (.75, 2.14), (.71, 2.2), (.65, 2.12),
                          (.6, 1.8), (.45, 1.42), (.2, 1.24), (0, 1.22)], (0, 0, 0), M['gold'])
for sx in (-1, 1):   # ear handles
    cu = bpy.data.curves.new('trophy_handle', 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = .075; cu.bevel_resolution = 6; cu.use_fill_caps = True
    s = cu.splines.new('NURBS'); pts = [(.66, 2.0), (.95, 2.04), (1.1, 1.85), (1.0, 1.55), (.75, 1.4), (.52, 1.32)]
    s.points.add(len(pts) - 1); s.use_endpoint_u = True; s.order_u = 4
    for p, (x, z) in zip(s.points, pts): p.co = (sx * x, 0, z, 1)
    cu.materials.append(M['gold']); o = bpy.data.objects.new(f'trophy_handle_{"L" if sx < 0 else "R"}', cu); col.objects.link(o)

def star_pts(R, r):
    return [((R if k % 2 == 0 else r) * math.cos(math.radians(90 + 36 * k)), (R if k % 2 == 0 else r) * math.sin(math.radians(90 + 36 * k))) for k in range(10)]
def rounded(pts, rad, segs=8):
    out = []; n = len(pts)
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        a, b = (p0 - p1).normalized(), (p2 - p1).normalized(); half = a.angle(b) / 2
        d = rad / math.tan(half); c = p1 + (a + b).normalized() * (rad / math.sin(half)); s_, e = p1 + a * d, p1 + b * d
        a0 = math.atan2(s_.y - c.y, s_.x - c.x); a1 = math.atan2(e.y - c.y, e.x - c.x); da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        out += [(c.x + rad * math.cos(a0 + da * k / segs), c.y + rad * math.sin(a0 + da * k / segs)) for k in range(segs + 1)]
    return out
star = prism(col, 'trophy_star', rounded(star_pts(.38, .185), .05), .14, (0, -.71, 1.74), M['star'], 0)
star.rotation_euler = (math.radians(13), 0, 0)
b2 = star.modifiers.new('Bevel', 'BEVEL'); b2.width = .045; b2.segments = 8; b2.limit_method = 'ANGLE'; b2.angle_limit = math.radians(60)
for o in col.objects:
    if o.type == 'MESH':
        for f in o.data.polygons: f.use_smooth = True
aim_camera((0, -7.2, 2.6), (0, 0, 1.12), 64)
render('icon_trophy', os.path.join(HERE, 'icon09_trophy.png'))
