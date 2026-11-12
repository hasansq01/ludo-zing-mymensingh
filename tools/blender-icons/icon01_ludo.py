import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
sc = open_file(); col = new_icon('icon_ludo_board')
for n in ['mat_wood','mat_cream','mat_red','mat_green','mat_blue','mat_yellow2','mat_pawn_red','mat_pawn_green','mat_pawn_blue','mat_pawn_yellow']:
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(wood=mat('mat_wood', '#b25a26', .62, .12), cream=mat('mat_cream', '#f6ead6', .6, .15),
         red=mat('mat_red', '#e8382c', .55, .15), green=mat('mat_green', '#5cb030', .55, .15), blue=mat('mat_blue', '#2f72dc', .55, .15), yellow=mat('mat_yellow2', '#f8b81c', .55, .15),
         pred=mat('mat_pawn_red', '#e0281f', .42, .2), pgreen=mat('mat_pawn_green', '#4aa526', .42, .2), pblue=mat('mat_pawn_blue', '#2464d6', .42, .2), pyellow=mat('mat_pawn_yellow', '#f4a514', .42, .2))
# tray: a rounded slab with a recess (raised rim)
S, TH, RIM, DEP = 2.4, .32, .2, .13
me = bpy.data.meshes.new('tray'); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
for v in bm.verts: v.co.x *= S; v.co.y *= S; v.co.z = (v.co.z + .5) * TH
top = [f for f in bm.faces if f.normal.z > .9][0]
r = bmesh.ops.inset_region(bm, faces=[top], thickness=RIM, depth=0)
bmesh.ops.translate(bm, vec=(0, 0, -DEP), verts=top.verts)
bm.to_mesh(me); bm.free()
tray = finish(col, bpy.data.objects.new('tray', me), M['wood'], .09, 8)
floor = TH - DEP
# play area: big coloured corners, cream strips of three cells, a centre with four triangles
inner = S - 2 * RIM; big, nar = .82, inner - 2 * .82
xs = [-inner/2 + big/2, 0, inner/2 - big/2]; ws = [big, nar, big]
corner = {(0, 0): 'blue', (2, 0): 'yellow', (0, 2): 'red', (2, 2): 'green'}   # (column, row from front)
gap, T = .022, .08
for i in range(3):
    for j in range(3):
        x, y, w, h = xs[i], xs[j], ws[i], ws[j]
        if (i, j) in corner:
            box(col, f'tile_{corner[(i, j)]}', (w - gap, h - gap, T), (x, y, floor + T/2), M[corner[(i, j)]], .03)
        elif (i, j) == (1, 1):
            box(col, 'tile_centre', (w - gap, h - gap, T), (x, y, floor + T/2), M['cream'], .025)
        else:   # strips: three cells along the long side
            n = 3; along_x = w > h
            for k in range(n):
                if along_x: cx, cy, cw, chh = x - w/2 + w/n*(k + .5), y, w/n - gap, h - gap
                else: cx, cy, cw, chh = x, y - h/2 + h/n*(k + .5), w - gap, h/n - gap
                box(col, f'tile_strip_{i}{j}_{k}', (cw, chh, T), (cx, cy, floor + T/2), M['cream'], .025)
# the four triangles on the centre tile
z0 = floor + T; c = (nar - gap) / 2 * .78
for nm, pts in [('red', [(-c, -c), (-c, c), (0, 0)]), ('green', [(-c, c), (c, c), (0, 0)]), ('yellow', [(c, c), (c, -c), (0, 0)]), ('blue', [(c, -c), (-c, -c), (0, 0)])]:
    prism(col, f'centre_{nm}', pts, .025, (0, 0, z0 - .005), M[nm], .006, axis='z')
# pawns: a soft cone with a collar and a round head, one per corner
prof = [(0, 0), (.2, 0), (.215, .035), (.19, .075), (.135, .2), (.095, .31), (.125, .34), (.12, .37), (.06, .385), (0, .385)]
for (i, j), k in corner.items():
    x, y = xs[i], xs[j]; s = .86
    p = lathe(col, f'pawn_{k}_body', [(r * s, z * s) for r, z in prof], (x, y, floor + T), M['p' + k])
    sphere(col, f'pawn_{k}_head', .13 * s, (x, y, floor + T + .5 * s), M['p' + k])
aim_camera((0, -5.4, 5.6), (0, .08, .1), 84)
render('icon_ludo_board', os.path.join(HERE, 'icon01_ludo_board.png'))
