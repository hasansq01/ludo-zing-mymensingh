# Icon 10: treasure chest - red-orange planks, round lid, soft yellow trim on the ends and seams, keyhole lock.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
sc = open_file(); col = new_icon('icon_chest')
for n in ('mat_chest_wood', 'mat_chest_gap', 'mat_chest_trim', 'mat_chest_hole'):
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(wood=mat('mat_chest_wood', '#de5f38', .55, .25), gap=mat('mat_chest_gap', '#9c3d24', .7, .1),
         trim=mat('mat_chest_trim', '#f0ad3a', .45, .3), hole=mat('mat_chest_hole', '#5a2e1c', .6, .05))
sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'; sc.view_settings.exposure = -.6   # medium saturation

W, D, H = 2.0, 1.3, .95; R = D / 2; E = .17          # width (x), depth (y), body height, lid radius, end-trim thickness
def end_profile(sc_=1.0, zc=0.0):
    """Side outline of the chest (y, z): box + half-round lid, optionally shrunk toward its middle."""
    pts = [(-R, 0), (R, 0)] + [(R * math.cos(math.radians(a)), H + R * math.sin(math.radians(a))) for a in range(0, 181, 6)] + [(-R, 0)]
    pts = pts[:-1]; cy, cz = 0, (H + R) / 2
    return [(cy + (y - cy) * sc_, cz + (z - cz) * sc_ + zc) for y, z in pts]
def side_slab(name, prof, x, depth, m, bevel):
    o = prism(col, name, prof, depth, (x, 0, 0), m, bevel); o.rotation_euler = (0, 0, math.pi / 2); return o

# inside block (seen through the plank gaps)
side_slab('chest_core', end_profile(.97), 0, W - .1, M['gap'], .03)
# body planks: three rows on front and back
for i in range(3):
    z0 = .04 + i * (H - .04) / 3; h = (H - .04) / 3 - .035
    for sy in (-1, 1):
        box(col, f'chest_plank_{"F" if sy < 0 else "B"}{i}', (W - 2 * E + .02, .1, h), (0, sy * (R - .02), z0 + h / 2), M['wood'], .035)
# lid planks: three curved strips
def lid_strip(name, a0, a1, t=.1):
    bm = bmesh.new(); n = 10; ring = []
    for x in (-(W - 2 * E + .02) / 2, (W - 2 * E + .02) / 2):
        outer = [bm.verts.new((x, R * math.cos(math.radians(a0 + (a1 - a0) * k / n)), H + R * math.sin(math.radians(a0 + (a1 - a0) * k / n)))) for k in range(n + 1)]
        inner = [bm.verts.new((x, (R - t) * math.cos(math.radians(a0 + (a1 - a0) * k / n)), H + (R - t) * math.sin(math.radians(a0 + (a1 - a0) * k / n)))) for k in range(n + 1)]
        ring.append(outer + inner[::-1])
    a, b = ring; m_ = len(a)
    bm.faces.new(a); bm.faces.new(b[::-1])
    for k in range(m_): j = (k + 1) % m_; bm.faces.new((a[k], a[j], b[j], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    return finish(col, bpy.data.objects.new(name, me), M['wood'], .035)
for i, (a0, a1) in enumerate(((2, 58), (62, 118), (122, 178))):
    lid_strip(f'chest_lid_plank{i}', a0, a1)
# yellow end frames with a red panel inside, at both ends
for sx in (-1, 1):
    side_slab(f'chest_end_frame_{"L" if sx < 0 else "R"}', end_profile(1.0), sx * (W / 2 - E / 2), E, M['trim'], .06)
    side_slab(f'chest_end_panel_{"L" if sx < 0 else "R"}', end_profile(.72), sx * (W / 2 - E / 2 + .025), E, M['wood'], .04)
# seam band, bottom band and the lock
box(col, 'chest_seam_band', (W - 2 * E + .06, D + .1, .14), (0, 0, H + .01), M['trim'], .05)
box(col, 'chest_bottom_band', (W - 2 * E + .06, D + .08, .12), (0, 0, .07), M['trim'], .05)
box(col, 'chest_lock', (.46, .14, .52), (0, -R - .07, H - .02), M['trim'], .09)
sphere(col, 'chest_keyhole', .065, (0, -R - .14, H + .04), M['hole'], (1, .4, 1))
box(col, 'chest_keyhole_slot', (.055, .05, .16), (0, -R - .14, H - .06), M['hole'], .02)
for o in col.objects:
    if o.type == 'MESH':
        for f in o.data.polygons: f.use_smooth = True
aim_camera((2.6, -6.3, 3.0), (0, 0, .82), 64)
render('icon_chest', os.path.join(HERE, 'icon10_chest.png'))
