# Icon 7: house - cream walls, thick soft yellow roof, chimney, arched door with steps, yellow window frames, yellow base.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
sc = open_file(); col = new_icon('icon_house')
for n in ('mat_house_wall', 'mat_house_roof', 'mat_house_trim', 'mat_house_pane', 'mat_house_chimney'):
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(wall=mat('mat_house_wall', '#f6e8d2', .6, .25), roof=mat('mat_house_roof', '#eda03c', .5, .3),
         trim=mat('mat_house_trim', '#eea844', .5, .25), pane=mat('mat_house_pane', '#fbf4e8', .4, .15),
         chim=mat('mat_house_chimney', '#f1e4cf', .6, .25))
L, Dp, Hw = 2.0, 1.5, 1.05        # house length (x), depth (y), wall height
RISE = .7; Z0 = .16                # roof rise, top of the base
box(col, 'house_base', (L + .5, Dp + .5, Z0), (0, 0, Z0 / 2), M['trim'], .07)
box(col, 'house_walls', (L, Dp, Hw), (0, 0, Z0 + Hw / 2), M['wall'], .05)
for sx in (-1, 1):                 # gable triangles at both ends
    g = prism(col, f'house_gable_{"L" if sx < 0 else "R"}', [(-Dp / 2, 0), (Dp / 2, 0), (0, RISE)], .3, (sx * (L / 2 - .15), 0, Z0 + Hw - .01), M['wall'], .03)
    g.rotation_euler = (0, 0, math.pi / 2)
# roof: two thick soft slabs meeting at the ridge, overhanging all round
ang = math.atan2(RISE, Dp / 2); slope = math.hypot(RISE, Dp / 2) + .32; T = .17
for sy in (-1, 1):
    cy = sy * (slope / 2 - .1) * math.cos(ang); cz = Z0 + Hw + RISE - (slope / 2 - .1) * math.sin(ang) + T * .7
    box(col, f'house_roof_{"F" if sy < 0 else "B"}', (L + .42, slope, T), (0, cy, cz), M['roof'], .07, (-sy * ang, 0, 0))
box(col, 'house_chimney', (.3, .3, .7), (.45, .38, Z0 + Hw + RISE * .55 + .3), M['chim'], .04)
box(col, 'house_chimney_cap', (.4, .4, .1), (.45, .38, Z0 + Hw + RISE * .55 + .67), M['pane'], .04)

def arched(name, w, h, depth, loc, m, face='x', bevel=.025):
    """An arch-topped slab (door / window) as one piece: rectangle of height h with a half-circle on top."""
    r = w / 2; pts = [(-r, 0), (r, 0)] + [(r * math.cos(math.radians(a)), h + r * math.sin(math.radians(a))) for a in range(0, 181, 10)][1:-1] + [(-r, h + 0)]
    pts = [(-r, 0), (r, 0), (r, h)] + [(r * math.cos(math.radians(a)), h + r * math.sin(math.radians(a))) for a in range(10, 180, 10)] + [(-r, h)]
    o = prism(col, name, pts, depth, loc, m, bevel)
    if face == 'x': o.rotation_euler = (0, 0, math.pi / 2)
    return o

def window(name, face, u, z, w, h, arch=False):
    """Yellow frame, cream panes, a cross of glazing bars. face 'x' = on the -x gable end, 'y' = on the front (-y) wall."""
    def put(n, size, off, m, b=.02):
        sx, sy, sz = (size[0], size[1], size[2]) if face == 'x' else (size[1], size[0], size[2])
        loc = (-L / 2 - off, u, z) if face == 'x' else (u, -Dp / 2 - off, z)
        return box(col, n, (sx, sy, sz), loc, m, b)
    put(name + '_frame', (.08, w, h), .01, M['trim'], .03)
    put(name + '_pane', (.06, w - .1, h - .1), .04, M['pane'])
    put(name + '_bar_v', (.05, .035, h - .1), .07, M['trim'])
    put(name + '_bar_h', (.05, w - .1, .035), .07, M['trim'])
    if arch:
        for nm, ww, off, m, d in ((name + '_arch', w, .01, M['trim'], .08), (name + '_arch_pane', w - .1, .04, M['pane'], .06)):
            loc = (-L / 2 - off, u, z + h / 2 - .001) if face == 'x' else (u, -Dp / 2 - off, z + h / 2 - .001)
            arched(nm, ww, .001, d, loc, m, face, .02)

# gable end: arched door + steps, a window beside it, a little arched window up in the gable
dz = Z0 + .36
arched('house_door', .42, .5, .08, (-L / 2 - .02, -.3, Z0), M['trim'])
sphere(col, 'house_door_knob', .03, (-L / 2 - .08, -.18, dz), M['pane'])
box(col, 'house_step_1', (.22, .62, .07), (-L / 2 - .14, -.3, Z0 + .035), M['trim'], .025)
box(col, 'house_step_2', (.14, .54, .07), (-L / 2 - .1, -.3, Z0 + .1), M['trim'], .025)
window('house_win_end', 'x', .33, Z0 + .55, .36, .38)
window('house_win_gable', 'x', 0, Z0 + Hw + .18, .28, .2, arch=True)
window('house_win_front', 'y', .35, Z0 + .55, .42, .42)
for o in col.objects:
    if o.type == 'MESH':
        for f in o.data.polygons: f.use_smooth = True
# saturated colours: 'Standard' view keeps the yellows rich instead of AgX washing them out
sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'; sc.view_settings.exposure = -.6
aim_camera((-5.4, -5.8, 3.7), (.05, 0, .95), 66)
render('icon_house', os.path.join(HERE, 'icon07_house.png'))
