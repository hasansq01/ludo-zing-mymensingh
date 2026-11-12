# Icon 5: robot head - soft white head, dark visor with smiling cyan eyes, orange ear pads, antenna with a red ball.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector
sc = open_file(); col = new_icon('icon_robot')
for n in ('mat_robot_white', 'mat_robot_visor', 'mat_robot_eye', 'mat_robot_orange', 'mat_robot_red', 'mat_robot_grey'):
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(white=mat('mat_robot_white', '#f4f1ea', .45, .25), visor=mat('mat_robot_visor', '#2b3346', .22, .05),
         eye=mat('mat_robot_eye', '#4fd8ea', .3, 0, emit=('#4fd8ea', 1.4)), orange=mat('mat_robot_orange', '#f39237', .5, .3),
         red=mat('mat_robot_red', '#ec5a4c', .4, .3), grey=mat('mat_robot_grey', '#d9d5cd', .45, .2))

def rounded(w, h, r, segs=12):
    out = []
    for cx, cy, a0 in ((w/2 - r, h/2 - r, 0), (-w/2 + r, h/2 - r, 90), (-w/2 + r, -h/2 + r, 180), (w/2 - r, -h/2 + r, 270)):
        for k in range(segs + 1):
            t = math.radians(a0 + 90 * k / segs); out.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    return out

def slab(name, outline, depth, m, bevel, loc, rot=(math.pi / 2, 0, 0)):
    """Rounded outline extruded by depth (outline in the object's XY, depth along its Z)."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((x, y, 0)) for x, y in outline])
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, 0, depth), verts=[v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.location = loc; o.rotation_euler = rot; finish(col, o, m, 0)
    b = o.modifiers.new('Bevel', 'BEVEL'); b.width = bevel; b.segments = 8; b.limit_method = 'ANGLE'; b.angle_limit = math.radians(60)
    return o

def arc(name, cx, cz, y, r, m, depth=.05):
    """A happy closed eye: an upside-down U made from a curve tube."""
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = depth; cu.bevel_resolution = 6; cu.use_fill_caps = True
    s = cu.splines.new('POLY'); n = 24; s.points.add(n)
    for k in range(n + 1):
        t = math.radians(20 + 140 * k / n); s.points[k].co = (cx + r * math.cos(t), y, cz + r * math.sin(t) * .9, 1)
    cu.materials.append(m); o = bpy.data.objects.new(name, cu); col.objects.link(o); return o

W, H, D = 1.9, 1.55, 1.45              # head size
head = slab('robot_head', rounded(W, D, .5), H, M['white'], .32, (0, 0, 0), (0, 0, 0))
head.location = (0, 0, 0)               # outline in XY (width x depth), extruded up
for o in [head]: o.location.z = 0
visor = slab('robot_visor', rounded(1.5, .92, .4), .1, M['visor'], .05, (0, -D / 2 + .04, H * .5))
visor.location.y = -D / 2 - .02
for sx in (-1, 1):
    arc(f'robot_eye_{"L" if sx < 0 else "R"}', sx * .33, H * .5 - .1, -D / 2 - .13, .17, M['eye'])
mouth = arc('robot_smile', 0, H * .5 - .12, -D / 2 - .13, .1, M['eye'], .035)
mouth.scale = (1, 1, -1); mouth.location.z = 2 * (H * .5 - .12) - .2      # flip to a small smile under the eyes
for sx in (-1, 1):
    bpy.ops.mesh.primitive_cylinder_add(radius=.36, depth=.22, vertices=64, location=(sx * (W / 2 + .06), 0, H * .5), rotation=(0, math.pi / 2, 0))
    pad = finish(col, bpy.context.object, M['orange'], .07, 6); pad.name = f'robot_ear_{"L" if sx < 0 else "R"}'
    bpy.ops.mesh.primitive_cylinder_add(radius=.2, depth=.12, vertices=64, location=(sx * (W / 2 + .19), 0, H * .5), rotation=(0, math.pi / 2, 0))
    cap = finish(col, bpy.context.object, M['grey'], .04, 5); cap.name = f'robot_ear_cap_{"L" if sx < 0 else "R"}'
bpy.ops.mesh.primitive_cylinder_add(radius=.18, depth=.12, vertices=48, location=(0, 0, H + .02))
finish(col, bpy.context.object, M['grey'], .04, 5).name = 'robot_antenna_base'
bpy.ops.mesh.primitive_cylinder_add(radius=.045, depth=.42, vertices=32, location=(0, 0, H + .27))
finish(col, bpy.context.object, M['grey'], 0).name = 'robot_antenna'
sphere(col, 'robot_antenna_ball', .16, (0, 0, H + .55), M['red'])
for p in bpy.data.collections['icon_robot'].objects:
    if p.type == 'MESH':
        for f in p.data.polygons: f.use_smooth = True
aim_camera((0, -6.6, 2.2), (0, 0, .95), 62)
render('icon_robot', os.path.join(HERE, 'icon05_robot.png'))
