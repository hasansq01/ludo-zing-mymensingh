import sys, os, math, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector
sc = open_file(); col = new_icon('icon_snake_ladder')
M = dict(wood=mat('mat_ladder', '#dc8a46', .6, .12), green=mat('mat_snake_green', '#5fae32', .5, .25),
         belly=mat('mat_snake_belly2', '#f4d272', .55, .25), white=mat('mat_eye_white', '#ffffff', .3, .1), black=mat('mat_eye_black', '#1b1b22', .2, 0),
         tongue=mat('mat_tongue', '#e8404a', .45, .2))
if 'mat_snake_belly' in bpy.data.materials: pass
# ---- ladder (leans a little), its own empty so it moves as one ----
lad = bpy.data.objects.new('ladder', None); col.objects.link(lad); lad.rotation_euler = (0, math.radians(6), 0)
HGT, GAP = 2.75, .66
for sx in (-1, 1):
    r = box(col, f'ladder_rail_{"L" if sx < 0 else "R"}', (.2, .18, HGT), (sx * GAP / 2, 0, HGT / 2), M['wood'], .05); r.parent = lad
for k in range(5):
    bpy.ops.mesh.primitive_cylinder_add(radius=.075, depth=GAP, vertices=32, location=(0, 0, .38 + k * .52), rotation=(0, math.pi / 2, 0))
    o = bpy.context.object; o.name = f'ladder_rung{k}'; finish(col, o, M['wood'], .02, 3); o.parent = lad

# ---- snake: a curve with a bevelled round section (editable path), fatter in the middle ----
def tube(name, pts, radii, depth, m):
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = depth; cu.bevel_resolution = 8; cu.resolution_u = 24
    cu.use_fill_caps = True
    sp = cu.splines.new('NURBS'); sp.points.add(len(pts) - 1); sp.order_u = 4; sp.use_endpoint_u = True
    for p, co, r in zip(sp.points, pts, radii): p.co = (*co, 1); p.radius = r
    o = bpy.data.objects.new(name, cu); col.objects.link(o); cu.materials.append(m); return o
# the reference's shape: tail in front of the ladder's foot, a big round C to the right, the neck back up to the head
SHIFT = -.3   # moves the whole snake sideways
P = [(x + SHIFT, y, z) for x, y, z in [(-.3, -.42, .8), (0.08, -.52, .48), (.7, -.48, .34), (1.26, -.32, .7), (1.46, -.2, 1.25), (1.26, -.24, 1.74),
     (.82, -.38, 1.98), (.92, -.42, 2.2), (1.1, -.4, 2.32)]]
R = [.18, .55, .85, 1.0, 1.0, 1.0, .9, .82, .78]
body = tube('snake_body', P, R, .31, M['green'])
# belly: painted into the skin — a soft cream band along the body (BELLY_SIDE turns it round the body), faint ridges across it
BELLY_SIDE = float(os.environ.get('BELLY_SIDE', '0.45'))
sk = bpy.data.materials.get('mat_snake_skin') or bpy.data.materials.new('mat_snake_skin'); sk.use_nodes = True; nt = sk.node_tree
for n in list(nt.nodes):
    if n.type not in ('OUTPUT_MATERIAL',): nt.nodes.remove(n)
bs = nt.nodes.new('ShaderNodeBsdfPrincipled'); nt.links.new(bs.outputs[0], nt.nodes['Material Output'].inputs['Surface'])
bs.inputs['Roughness'].default_value = .5; bs.inputs['Subsurface Weight'].default_value = .25; bs.inputs['Subsurface Scale'].default_value = .04
bs.inputs['Subsurface Radius'].default_value = (1, .55, .35); bs.inputs['Specular IOR Level'].default_value = .35
tc = nt.nodes.new('ShaderNodeTexCoord'); sep = nt.nodes.new('ShaderNodeSeparateXYZ'); nt.links.new(tc.outputs['UV'], sep.inputs[0])
d = nt.nodes.new('ShaderNodeMath'); d.operation = 'SUBTRACT'; d.inputs[1].default_value = BELLY_SIDE; nt.links.new(sep.outputs['Y'], d.inputs[0])
fr = nt.nodes.new('ShaderNodeMath'); fr.operation = 'PINGPONG'; fr.inputs[1].default_value = .5; nt.links.new(d.outputs[0], fr.inputs[0])   # distance round the body, 0..0.5
mr = nt.nodes.new('ShaderNodeMapRange'); mr.interpolation_type = 'SMOOTHSTEP'; mr.inputs['From Min'].default_value = .125; mr.inputs['From Max'].default_value = .085
nt.links.new(fr.outputs[0], mr.inputs['Value'])
rg = nt.nodes.new('ShaderNodeMath'); rg.operation = 'MULTIPLY'; rg.inputs[1].default_value = 170; nt.links.new(sep.outputs['X'], rg.inputs[0])
sn = nt.nodes.new('ShaderNodeMath'); sn.operation = 'SINE'; nt.links.new(rg.outputs[0], sn.inputs[0])
rr = nt.nodes.new('ShaderNodeMapRange'); rr.inputs['From Min'].default_value = -1; rr.inputs['To Min'].default_value = .55; rr.inputs['To Max'].default_value = 1.0; nt.links.new(sn.outputs[0], rr.inputs['Value'])
bel = nt.nodes.new('ShaderNodeMix'); bel.data_type = 'RGBA'; bel.inputs['A'].default_value = (*srgb('#dfb52e'), 1); bel.inputs['B'].default_value = (*srgb('#f3d14c'), 1); nt.links.new(rr.outputs[0], bel.inputs['Factor'])
mx = nt.nodes.new('ShaderNodeMix'); mx.data_type = 'RGBA'; mx.inputs['A'].default_value = (*srgb('#5fae32'), 1); nt.links.new(bel.outputs['Result'], mx.inputs['B']); nt.links.new(mr.outputs['Result'], mx.inputs['Factor'])
nt.links.new(mx.outputs['Result'], bs.inputs['Base Color'])
rm = nt.nodes.new('ShaderNodeMath'); rm.operation = 'MULTIPLY'; nt.links.new(rr.outputs[0], rm.inputs[0]); nt.links.new(mr.outputs['Result'], rm.inputs[1])
bp = nt.nodes.new('ShaderNodeBump'); bp.inputs['Strength'].default_value = .55; bp.inputs['Distance'].default_value = .02; nt.links.new(rm.outputs[0], bp.inputs['Height']); nt.links.new(bp.outputs['Normal'], bs.inputs['Normal'])
body.data.materials.clear(); body.data.materials.append(sk)
# head: a soft rounded wedge at the top, looking right
hx, hy, hz = 1.22 + SHIFT, -.44, 2.44
head = sphere(col, 'snake_head', .4, (hx, hy, hz), M['green'], (1.25, 1.0, .82))
head.rotation_euler = (0, math.radians(-12), math.radians(-18))
# face: big friendly eyes on the front of the head, a curved smile, the forked tongue out to the right
for sx in (-1, 1):
    ex = hx - .02 + sx * .15
    sphere(col, f'snake_eye_{"L" if sx < 0 else "R"}', .11, (ex, hy - .27, hz + .14), M['white'])
    sphere(col, f'snake_pupil_{"L" if sx < 0 else "R"}', .058, (ex + .025, hy - .36, hz + .15), M['black'])
    sphere(col, f'snake_glint_{"L" if sx < 0 else "R"}', .018, (ex + .045, hy - .41, hz + .18), M['white'])
tube('snake_smile', [(hx + .02, hy - .34, hz - .1), (hx + .15, hy - .36, hz - .17), (hx + .3, hy - .3, hz - .1)], [1, 1, 1], .022, M['black'])
tube('snake_tongue', [(hx + .34, hy - .2, hz - .12), (hx + .5, hy - .22, hz - .16), (hx + .62, hy - .2, hz - .12)], [1, 1, .8], .034, M['tongue'])
tube('snake_tongue_forkA', [(hx + .62, hy - .2, hz - .12), (hx + .72, hy - .2, hz - .05)], [.8, .6], .028, M['tongue'])
tube('snake_tongue_forkB', [(hx + .62, hy - .2, hz - .12), (hx + .73, hy - .2, hz - .19)], [.8, .6], .028, M['tongue'])
aim_camera((.55, -8.0, 2.6), (.5, 0, 1.4), 74)
render('icon_snake_ladder', os.path.join(HERE, os.environ.get('OUT', 'icon02_snake_ladder.png')))
