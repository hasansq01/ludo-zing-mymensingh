# Icon 6: swap players - a red and a blue pawn-person side by side (no arrows).
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector
sc = open_file(); col = new_icon('icon_swap')
for n in ('mat_swap_red', 'mat_swap_blue', 'mat_swap_arrow'):
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(red=mat('mat_swap_red', '#e4493b', .45, .3), blue=mat('mat_swap_blue', '#3f7ad8', .45, .3))

# pawn-people: a big ball head sitting right on a soft bell-shaped body (like the reference)
PROF = [(.56, 0), (.6, .05), (.6, .14), (.55, .32), (.44, .55), (.3, .76), (.14, .88), (0, .9)]
def pawn(tag, x, y, m):
    rig = bpy.data.objects.new(f'pawn_{tag}', None); col.objects.link(rig); rig.location = (x, y, 0)
    body = lathe(col, f'pawn_{tag}_body', PROF, (0, 0, 0), m); body.parent = rig
    head = sphere(col, f'pawn_{tag}_head', .4, (0, 0, 1.16), m); head.parent = rig
    for o in (body, head):
        for f in o.data.polygons: f.use_smooth = True
    return rig

pawn('red', -.52, .12, M['red']); pawn('blue', .52, -.08, M['blue'])
aim_camera((0, -7.4, 2.2), (0, 0, .76), 74)
render('icon_swap', os.path.join(HERE, 'icon06_swap.png'))
