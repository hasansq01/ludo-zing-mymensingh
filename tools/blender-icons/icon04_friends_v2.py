# Icon 4: two friends - a boy in a blue hoodie and a girl in a purple hoodie, faceless, soft clay look.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector
sc = open_file(); col = new_icon('icon_friends')
NAMES = ['mat_skin', 'mat_hoodie_blue', 'mat_hoodie_blue_dark', 'mat_hoodie_purple', 'mat_hoodie_purple_dark', 'mat_hair_boy', 'mat_hair_girl', 'mat_string']
for n in NAMES:
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(skin=mat('mat_skin', '#f0aa7c', .55, .35, .06),
         blue=mat('mat_hoodie_blue', '#4f98e2', .7, .2), blue_d=mat('mat_hoodie_blue_dark', '#4288d4', .7, .2),
         purple=mat('mat_hoodie_purple', '#c274cf', .7, .2), purple_d=mat('mat_hoodie_purple_dark', '#b064c0', .7, .2),
         hair_b=mat('mat_hair_boy', '#a5684a', .6, .2), hair_g=mat('mat_hair_girl', '#a5684a', .6, .2),
         string=mat('mat_string', '#f6ead6', .6, .15))

def hair(tag, r, loc, m, bottom, sweep, cut_scale, cut_z):
    """Hair = a soft ball around the head, cut flat underneath (clean plane) and with the face
    carved out by an egg-shaped cutter (Boolean, live - move/scale 'face_cutter' to restyle the fringe)."""
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=40, radius=r)
    g = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=g, plane_co=(0, 0, bottom * r), plane_no=(0, 0, 1), clear_inner=True)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary])
    me = bpy.data.meshes.new(f'{tag}_hair'); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(f'{tag}_hair', me); o.location = loc; o.scale = (1.06, 1.0, 1.08); finish(col, o, m, 0)
    cu = sphere(col, f'{tag}_face_cutter', 1, (loc[0], loc[1] - r * 1.0, loc[2] + cut_z), None, cut_scale)
    cu.rotation_euler = (0, sweep, 0); cu.display_type = 'WIRE'; cu.hide_render = True
    bo = o.modifiers.new('Face cut', 'BOOLEAN'); bo.operation = 'DIFFERENCE'; bo.object = cu; bo.solver = 'EXACT'
    bv = o.modifiers.new('Soft edge', 'BEVEL'); bv.width = .03; bv.segments = 4; bv.limit_method = 'ANGLE'; bv.angle_limit = math.radians(35)
    return o, cu

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
    if girl:   # fringe swept to her left, long hair falling behind the shoulders
        h, cu = hair(tag, .545, (0, .03, hz + .04), hair_m, -.62, math.radians(22), (.5, .55, .64), -.3)
        parts += [h, cu]
        f = sphere(col, f'{tag}_fringe', 1, (.1, -.4, hz + .2), hair_m, (.34, .16, .15)); f.rotation_euler = (math.radians(-20), math.radians(24), math.radians(-14)); parts.append(f)
        parts.append(sphere(col, f'{tag}_hair_back', 1, (0, .22, hz - .4), hair_m, (.56, .34, .76)))
        for sx in (-1, 1): parts.append(sphere(col, f'{tag}_hair_lock', 1, (sx * .45, .02, hz - .5), hair_m, (.14, .2, .4)))
    else:      # full rounded hair, fringe swept to one side, covering the ears
        h, cu = hair(tag, .55, (0, .03, hz + .05), hair_m, -.42, math.radians(-22), (.5, .55, .62), -.28)
        parts += [h, cu]
        f = sphere(col, f'{tag}_fringe', 1, (-.1, -.4, hz + .22), hair_m, (.36, .16, .15)); f.rotation_euler = (math.radians(-20), math.radians(-24), math.radians(14)); parts.append(f)
    for p in parts: p.parent = rig
    return rig

boy = person('boy', -.38, 0, 1.0, M['blue'], M['blue_d'], M['hair_b'], False)
girl = person('girl', .48, .55, 1.0, M['purple'], M['purple_d'], M['hair_g'], True)
boy.rotation_euler = (0, 0, math.radians(4)); girl.rotation_euler = (0, 0, math.radians(-6))
aim_camera((0, -7.2, 2.6), (.02, .25, 1.0), 66)
render('icon_friends', os.path.join(HERE, 'icon04_friends.png'))
