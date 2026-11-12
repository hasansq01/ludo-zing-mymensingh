# Icon 4: two friends - a boy in a blue hoodie and a girl in a purple hoodie, faceless, soft clay look.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector, Matrix, Euler
sc = open_file(); col = new_icon('icon_friends')
NAMES = ['mat_skin', 'mat_hoodie_blue', 'mat_hoodie_blue_dark', 'mat_hoodie_purple', 'mat_hoodie_purple_dark', 'mat_hair_boy', 'mat_hair_girl', 'mat_string']
for n in NAMES:
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(skin=mat('mat_skin', '#f0aa7c', .55, .35, .06),
         blue=mat('mat_hoodie_blue', '#4f98e2', .7, .2), blue_d=mat('mat_hoodie_blue_dark', '#4288d4', .7, .2),
         purple=mat('mat_hoodie_purple', '#c274cf', .7, .2), purple_d=mat('mat_hoodie_purple_dark', '#b064c0', .7, .2),
         hair_b=mat('mat_hair_boy', '#a5684a', .6, .2), hair_g=mat('mat_hair_girl', '#a5684a', .6, .2),
         string=mat('mat_string', '#f6ead6', .6, .15))

def lumps(name, pieces, loc):
    bm = bmesh.new()
    for loc_, scl, rot in pieces:
        M4 = Matrix.Translation(loc_) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4() @ Matrix.Diagonal((*scl, 1))
        bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=1, matrix=M4)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.location = loc; col.objects.link(o); return o

def hair(tag, hz, m, pieces, fringe, mass_bottom, cut_loc, cut_scale, sweep):
    """One connected hair volume, built like sculpting:
    1. <tag>_hair: the hair mass (lumps melted by Remesh), cut flat underneath
    2. <tag>_face_cutter (hidden egg) carves the face out
    3. <tag>_fringe (hidden lumps) is added back over the forehead
    4. a second Remesh melts it all into ONE surface, Smooth rounds every join.
    Move/scale the cutter, the fringe or Tab into the hair lumps: it all updates live."""
    o = lumps(f'{tag}_hair', pieces, (0, 0, hz))
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, mass_bottom), plane_no=(0, 0, 1), clear_inner=True)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary]); bm.to_mesh(o.data); bm.free()
    col.objects.unlink(o); finish(col, o, m, 0)
    r1 = o.modifiers.new('Melt lumps', 'REMESH'); r1.mode = 'VOXEL'; r1.voxel_size = .02
    cu = sphere(col, f'{tag}_face_cutter', 1, (cut_loc[0], cut_loc[1], hz + cut_loc[2]), None, cut_scale)
    cu.rotation_euler = (0, math.radians(sweep), 0); cu.display_type = 'WIRE'; cu.hide_render = True
    b1 = o.modifiers.new('Face cut', 'BOOLEAN'); b1.operation = 'DIFFERENCE'; b1.object = cu; b1.solver = 'EXACT'
    fr = lumps(f'{tag}_fringe', fringe, (0, 0, hz)); fr.display_type = 'WIRE'; fr.hide_render = True
    b2 = o.modifiers.new('Add fringe', 'BOOLEAN'); b2.operation = 'UNION'; b2.object = fr; b2.solver = 'EXACT'
    r2 = o.modifiers.new('Melt all', 'REMESH'); r2.mode = 'VOXEL'; r2.voxel_size = .016
    sm = o.modifiers.new('Soften', 'SMOOTH'); sm.factor = 1.0; sm.iterations = 14
    o.data.polygons.foreach_set('use_smooth', [True] * len(o.data.polygons))
    return [o, cu, fr]

def person(tag, x, y, sc_, coat, coat_d, hair_m, girl):
    rig = bpy.data.objects.new(f'{tag}', None); col.objects.link(rig); rig.location = (x, y, 0); rig.scale = (sc_,) * 3
    parts = []
    body = lathe(col, f'{tag}_hoodie', [(.7, 0), (.76, .12), (.77, .38), (.7, .6), (.52, .78), (.28, .88), (0, .9)], (0, 0, 0), coat)
    body.scale = (1, .78, 1); parts.append(body)
    bpy.ops.mesh.primitive_torus_add(major_radius=.33, minor_radius=.16, major_segments=48, minor_segments=16, location=(0, .06, .86), rotation=(math.radians(16), 0, 0))
    hood = finish(col, bpy.context.object, coat_d, 0); hood.name = f'{tag}_hood'; parts.append(hood)
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_cylinder_add(radius=.026, depth=.24, location=(sx * .09, -.54, .64))
        parts.append(finish(col, bpy.context.object, M['string'], 0))
        parts.append(sphere(col, f'{tag}_string_tip', .04, (sx * .09, -.55, .51), M['string']))
    hz = 1.42
    head = sphere(col, f'{tag}_head', .5, (0, 0, hz), M['skin'], (1, 1, 1.08)); parts.append(head)
    if girl:   # crown + long hair behind + locks by the cheeks; fringe swept to her left
        pieces = [((0, .03, .06), (.585, .56, .6), (0, 0, 0)),
                  ((0, .2, -.42), (.56, .34, .7), (0, 0, 0)),
                  ((.45, .02, -.42), (.15, .2, .42), (0, -6, 0)), ((-.45, .02, -.42), (.15, .2, .42), (0, 6, 0))]
        fringe = [((.04, -.38, .25), (.47, .13, .18), (-12, 22, -8))]
        parts += hair(tag, hz, hair_m, pieces, fringe, -.9, (0, -.5, -.24), (.47, .5, .55), 16)
    else:      # full crown covering the ears; fringe swept to one side
        pieces = [((0, .03, .07), (.59, .56, .6), (0, 0, 0))]
        fringe = [((-.04, -.38, .26), (.49, .13, .18), (-12, -22, 8))]
        parts += hair(tag, hz, hair_m, pieces, fringe, -.24, (0, -.5, -.24), (.47, .5, .55), -16)
    for p in parts: p.parent = rig
    return rig

boy = person('boy', -.38, 0, 1.0, M['blue'], M['blue_d'], M['hair_b'], False)
girl = person('girl', .48, .55, 1.0, M['purple'], M['purple_d'], M['hair_g'], True)
boy.rotation_euler = (0, 0, math.radians(4)); girl.rotation_euler = (0, 0, math.radians(-6))
aim_camera((0, -7.2, 2.6), (.02, .25, 1.0), 66)
render('icon_friends', os.path.join(HERE, 'icon04_friends.png'))
