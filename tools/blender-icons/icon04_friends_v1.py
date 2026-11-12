# Icon 4: two friends - a boy in a blue hoodie and a girl in a purple hoodie, faceless, soft clay look.
import sys, os, math, bmesh, bpy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from mathutils import Vector
sc = open_file(); col = new_icon('icon_friends')
NAMES = ['mat_skin', 'mat_hoodie_blue', 'mat_hoodie_blue_dark', 'mat_hoodie_purple', 'mat_hoodie_purple_dark', 'mat_hair_boy', 'mat_hair_girl', 'mat_string']
for n in NAMES:
    if n in bpy.data.materials: bpy.data.materials.remove(bpy.data.materials[n])
M = dict(skin=mat('mat_skin', '#f0bd92', .55, .35, .06),
         blue=mat('mat_hoodie_blue', '#5a8edc', .7, .2), blue_d=mat('mat_hoodie_blue_dark', '#4a7bcb', .7, .2),
         purple=mat('mat_hoodie_purple', '#9d78d8', .7, .2), purple_d=mat('mat_hoodie_purple_dark', '#8866c8', .7, .2),
         hair_b=mat('mat_hair_boy', '#5e3c2b', .6, .15), hair_g=mat('mat_hair_girl', '#4c2e23', .6, .15),
         string=mat('mat_string', '#f6ead6', .6, .15))

def hair(name, r, loc, m, keep, thick=.05):
    """A hair shell: a sphere around the head, trimmed by keep(x, y, z) on the unit sphere."""
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=32, radius=1)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(*v.co)], context='VERTS')
    for v in bm.verts: v.co *= r
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.location = loc; finish(col, o, m, 0)
    so = o.modifiers.new('Thickness', 'SOLIDIFY'); so.thickness = thick; so.offset = 1
    s = o.modifiers.new('Smooth', 'SUBSURF'); s.levels = 2; s.render_levels = 2
    return o

def person(tag, x, y, sc_, coat, coat_d, hair_m, girl):
    rig = bpy.data.objects.new(f'{tag}', None); col.objects.link(rig); rig.location = (x, y, 0); rig.scale = (sc_,) * 3
    parts = []
    body = lathe(col, f'{tag}_hoodie', [(.62, 0), (.68, .12), (.69, .42), (.64, .66), (.5, .84), (.28, .95), (0, .98)], (0, 0, 0), coat)
    body.scale = (1, .8, 1); parts.append(body)
    bpy.ops.mesh.primitive_torus_add(major_radius=.33, minor_radius=.13, major_segments=48, minor_segments=16, location=(0, .07, .93), rotation=(math.radians(14), 0, 0))
    hood = finish(col, bpy.context.object, coat_d, 0); hood.name = f'{tag}_hood'; parts.append(hood)
    pocket = sphere(col, f'{tag}_pocket', 1, (0, -.5, .3), coat_d, (.3, .07, .13)); parts.append(pocket)
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_cylinder_add(radius=.028, depth=.3, location=(sx * .1, -.5, .74))
        parts.append(finish(col, bpy.context.object, M['string'], 0))
        parts.append(sphere(col, f'{tag}_string_tip', .042, (sx * .1, -.52, .58), M['string']))
    hz = 1.36
    head = sphere(col, f'{tag}_head', .42, (0, 0, hz), M['skin']); parts.append(head)
    for sx in (-1, 1): parts.append(sphere(col, f'{tag}_ear', .085, (sx * .41, .02, hz - .03), M['skin'], (.6, 1, 1)))
    if girl:   # long bob framing the face, down past the jaw
        keep = lambda vx, vy, vz: vz > .28 or (vy > -.15 and vz > -.95) or (abs(vx) > .78 and vz > -.95)
        parts.append(hair(f'{tag}_hair', .445, (0, .01, hz + .02), hair_m, keep, .07))
        parts.append(sphere(col, f'{tag}_hair_bun', .17, (0, .32, hz + .38), hair_m))
    else:      # short hair with a soft fringe
        keep = lambda vx, vy, vz: vz > .3 or (vy > .1 and vz > -.35) or (abs(vx) > .85 and vz > .05 and vy > -.3)
        parts.append(hair(f'{tag}_hair', .44, (0, .01, hz + .03), hair_m, keep, .07))
    for p in parts: p.parent = rig
    return rig

boy = person('boy', -.62, 0, 1.0, M['blue'], M['blue_d'], M['hair_b'], False)
girl = person('girl', .62, .35, .95, M['purple'], M['purple_d'], M['hair_g'], True)
boy.rotation_euler = (0, 0, math.radians(8)); girl.rotation_euler = (0, 0, math.radians(-10))
aim_camera((0, -7.2, 2.6), (-.08, .15, .88), 70)
render('icon_friends', os.path.join(HERE, 'icon04_friends.png'))
