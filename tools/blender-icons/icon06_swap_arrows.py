# Icon 6: swap players - a red and a blue pawn-person with two soft yellow arrows circling between them.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector
sc = open_file(); col = new_icon('icon_swap')
for n in ('mat_swap_red', 'mat_swap_blue', 'mat_swap_arrow'):
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(red=mat('mat_swap_red', '#e8574a', .45, .3), blue=mat('mat_swap_blue', '#4f88dc', .45, .3), arrow=mat('mat_swap_arrow', '#f5b52a', .45, .3))

PROF = [(.4, 0), (.43, .05), (.42, .12), (.3, .2), (.22, .32), (.19, .6), (.18, .76), (.29, .8), (.3, .86), (.16, .9), (0, .91)]
def pawn(tag, x, m):
    rig = bpy.data.objects.new(f'pawn_{tag}', None); col.objects.link(rig); rig.location = (x, 0, 0)
    body = lathe(col, f'pawn_{tag}_body', PROF, (0, 0, 0), m); body.parent = rig
    head = sphere(col, f'pawn_{tag}_head', .27, (0, 0, 1.13), m); head.parent = rig
    for o in (body, head):
        for f in o.data.polygons: f.use_smooth = True
    return rig

pawn('red', -.62, M['red']); pawn('blue', .62, M['blue'])

C, R = Vector((0, 0, .66)), 1.22
def arrow(tag, a0, a1):
    """A thick round arc from angle a0 to a1 (degrees, in the front plane) with a soft arrowhead at a1."""
    cu = bpy.data.curves.new(f'arrow_{tag}', 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = .1; cu.bevel_resolution = 8; cu.use_fill_caps = True
    s = cu.splines.new('POLY'); n = 40; s.points.add(n)
    for k in range(n + 1):
        t = math.radians(a0 + (a1 - a0) * k / n); s.points[k].co = (C.x + R * math.cos(t), -.15, C.z + R * math.sin(t), 1)
    cu.materials.append(M['arrow']); o = bpy.data.objects.new(f'arrow_{tag}', cu); col.objects.link(o)
    t = math.radians(a1); sgn = 1 if a1 > a0 else -1
    tip_dir = Vector((-math.sin(t), 0, math.cos(t))) * sgn
    p = Vector((C.x + R * math.cos(t), -.15, C.z + R * math.sin(t)))
    h = prism(col, f'arrow_{tag}_head', [(0, -.27), (.62, 0), (0, .27)], .2, (0, 0, 0), M['arrow'], .07)
    h.location = p - tip_dir * .03; h.rotation_euler = (0, math.atan2(-tip_dir.z, tip_dir.x), 0)
    h.parent = o; h.matrix_parent_inverse = o.matrix_world.inverted()
    return o

arrow('top', 152, 48)       # over the heads, pointing right
arrow('bottom', 332, 228)   # under the feet, pointing left
aim_camera((0, -7.6, 1.8), (0, 0, .62), 62)
render('icon_swap', os.path.join(HERE, 'icon06_swap.png'))
