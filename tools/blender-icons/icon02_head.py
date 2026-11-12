# Turns the white sphere the user added into the snake head, with eyes + forked tongue
# parented to it: rotate snake_head and the eyes/tongue follow where it looks.
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from lib import srgb, mat, render

col = bpy.data.collections['icon_snake_ladder']
src = bpy.data.objects.get('Quadsphere') or bpy.data.objects['snake_head']
body = bpy.data.objects['snake_body']

# where the head looks: along the body's last segment (neck -> head)
pts = body.data.splines[0].points
d = (Vector(pts[-1].co[:3]) - Vector(pts[-2].co[:3])).normalized()
up = Vector((0, 0, 1)); y = up.cross(d).normalized(); z = d.cross(y).normalized()
rot = Matrix((d, y, z)).transposed()          # local X = forward, Z = up

center = src.matrix_world.translation.copy()
R = max(src.dimensions) / 2
# reshape the sphere in its own space: longer, flatter, a gently narrower snout
me = src.data; mw = src.matrix_world.copy()
for v in me.vertices:
    p = ((mw @ v.co) - center) / R
    p = Vector((p.dot(Vector((1,0,0))), p.dot(Vector((0,1,0))), p.dot(Vector((0,0,1)))))  # world-aligned unit
    x, yy, zz = p
    t = max(x, 0)
    nx = x * (1.32 if x > 0 else 1.55)
    ny = yy * (1.06 - .2 * t * t)
    nz = zz * (.80 - .12 * t * t) * (.9 if zz > 0 else 1.0)
    v.co = Vector((nx, ny, nz)) * R
src.name = 'snake_head'; src.data.name = 'snake_head'
src.matrix_world = Matrix.Translation(center) @ rot.to_4x4()
for c in list(src.users_collection): c.objects.unlink(src)
col.objects.link(src)
for p in me.polygons: p.use_smooth = True
if not any(m.type == 'SUBSURF' for m in src.modifiers):
    s = src.modifiers.new('Subdivision', 'SUBSURF'); s.levels = 1; s.render_levels = 2

# head material: green top, soft yellow underside, same soft SSS as the body
hm = bpy.data.materials.get('mat_snake_head') or bpy.data.materials.new('mat_snake_head'); hm.use_nodes = True; nt = hm.node_tree
for n in list(nt.nodes):
    if n.type != 'OUTPUT_MATERIAL': nt.nodes.remove(n)
bs = nt.nodes.new('ShaderNodeBsdfPrincipled'); nt.links.new(bs.outputs[0], nt.nodes['Material Output'].inputs['Surface'])
bs.inputs['Roughness'].default_value = .5; bs.inputs['Subsurface Weight'].default_value = .25; bs.inputs['Subsurface Scale'].default_value = .04
bs.inputs['Subsurface Radius'].default_value = (1, .55, .35); bs.inputs['Specular IOR Level'].default_value = .35
tc = nt.nodes.new('ShaderNodeTexCoord'); sp = nt.nodes.new('ShaderNodeSeparateXYZ'); nt.links.new(tc.outputs['Object'], sp.inputs[0])
mr = nt.nodes.new('ShaderNodeMapRange'); mr.interpolation_type = 'SMOOTHSTEP'
mr.inputs['From Min'].default_value = -.02; mr.inputs['From Max'].default_value = -.11   # 0 on top -> 1 underneath
nt.links.new(sp.outputs['Z'], mr.inputs['Value'])
mx = nt.nodes.new('ShaderNodeMix'); mx.data_type = 'RGBA'
mx.inputs['A'].default_value = (*srgb('#5fae32'), 1); mx.inputs['B'].default_value = (*srgb('#f8d76e'), 1)
nt.links.new(mr.outputs['Result'], mx.inputs['Factor']); nt.links.new(mx.outputs['Result'], bs.inputs['Base Color'])
me.materials.clear(); me.materials.append(hm)

M = dict(white=mat('mat_eye_white', '#ffffff', .3, .1), black=mat('mat_eye_black', '#1b1b22', .2, 0), tongue=mat('mat_tongue', '#e8404a', .45, .2))
for n in [o.name for o in bpy.data.objects if o.name.startswith(('snake_eye', 'snake_pupil', 'snake_tongue', 'snake_smile'))]:
    bpy.data.objects.remove(bpy.data.objects[n])

def child(o):
    col.objects.link(o); o.parent = src; o.matrix_parent_inverse = Matrix.Identity(4); return o
def ball(name, r, loc, m):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=r)
    me2 = bpy.data.meshes.new(name); bm.to_mesh(me2); bm.free()
    for p in me2.polygons: p.use_smooth = True
    me2.materials.append(m); o = bpy.data.objects.new(name, me2); o.location = loc; return child(o)
def tube(name, pts, radii, depth, m):
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = depth; cu.bevel_resolution = 6; cu.use_fill_caps = True
    s = cu.splines.new('NURBS'); s.points.add(len(pts) - 1); s.use_endpoint_u = True; s.order_u = min(3, len(pts))
    for p, (q, r) in zip(s.points, zip(pts, radii)): p.co = (*q, 1); p.radius = r
    cu.materials.append(m); return child(bpy.data.objects.new(name, cu))

# eyes: up on the sides, a little forward; pupils look the way the head faces
L = 1.32 * R
for side, sy in (('L', 1), ('R', -1)):
    e = Vector((.30 * R, sy * .58 * R, .44 * R)); er = .092
    ball(f'snake_eye_{side}', er, e, M['white'])
    look = (Vector((1, 0, 0)) * .85 + Vector((0, sy, .25)).normalized() * .5).normalized()
    ball(f'snake_pupil_{side}', .052, e + look * (er - .035), M['black'])
    ball(f'snake_glint_{side}', .016, e + look * (er - .035) + Vector((.025, sy * .01, .035)) + look * .045, M['white'])

# forked tongue out of the snout, pointing forward
b = Vector((L - .06, 0, -.07))
tip = b + Vector((.17, 0, -.035))
tube('snake_tongue', [b, b + Vector((.09, 0, -.03)), tip], [1, 1, .85], .026, M['tongue'])
tube('snake_tongue_forkA', [tip, tip + Vector((.05, .015, -.005)), tip + Vector((.09, .05, .01))], [.85, .7, .5], .026, M['tongue'])
tube('snake_tongue_forkB', [tip, tip + Vector((.05, -.015, -.005)), tip + Vector((.09, -.05, .01))], [.85, .7, .5], .026, M['tongue'])

render('icon_snake_ladder', os.path.join(HERE, os.environ.get('OUT', 'icon02_snake_head.png')))
