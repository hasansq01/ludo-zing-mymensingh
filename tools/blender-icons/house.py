# Cozy 3D Home icon test: soft rounded shapes, matte clay-like materials, big soft studio light.
# Everything stays editable: live Bevel modifiers, shared materials, named parts, one light rig, one camera.
import bpy, bmesh, math, sys
from mathutils import Vector
out_png = sys.argv[sys.argv.index('--') + 1]; out_blend = sys.argv[sys.argv.index('--') + 2]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---- shared materials ----
def mat(name, rgb, rough=.55, metal=0.0, coat=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*rgb, 1); b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if 'Coat Weight' in b.inputs: b.inputs['Coat Weight'].default_value = coat
    return m
srgb = lambda h: tuple(((int(h[i:i+2], 16) / 255) ** 2.2) for i in (1, 3, 5))
M = {'yellow': mat('mat_yellow', srgb('#ffc414'), .6, coat=0), 'white': mat('mat_white', srgb('#fbf8f3'), .6),
     'glass': mat('mat_glass', srgb('#dfe9f2'), .25), 'metal': mat('mat_knob', srgb('#c8c8c8'), .25, 1.0)}

col = bpy.data.collections.new('icon_home'); sc.collection.children.link(col)
def finish(o, m, bevel=.04, seg=5):
    col.objects.link(o)
    o.data.materials.append(M[m])
    if bevel:
        b = o.modifiers.new('Bevel', 'BEVEL'); b.width = bevel; b.segments = seg; b.limit_method = 'ANGLE'; b.harden_normals = bevel >= .03
    for p in o.data.polygons: p.use_smooth = True
    return o
def box(name, size, loc, m, bevel=.04, rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.scale = size; o.location = loc; o.rotation_euler = rot
    finish(o, m, bevel)
    return o
def apply_scale(o):
    me = o.data; mat_ = o.matrix_basis.copy(); s = o.scale.copy()
    for v in me.vertices: v.co = Vector((v.co.x * s.x, v.co.y * s.y, v.co.z * s.z))
    o.scale = (1, 1, 1)

W, D, H, R = 1.3, 1.5, 0.9, 0.58          # wall width (x), depth (y), wall height, roof rise
# base
b = box('base', (W + .5, D + .55, .16), (0, 0, .08), 'yellow'); apply_scale(b); b.modifiers['Bevel'].width = .07
# walls: a pentagon prism (gable at the front and back)
me = bpy.data.meshes.new('walls'); bm = bmesh.new()
prof = [(-W/2, .16), (W/2, .16), (W/2, .16 + H), (0, .16 + H + R), (-W/2, .16 + H)]
f = [bm.verts.new((x, -D/2, z)) for x, z in prof]; bk = [bm.verts.new((x, D/2, z)) for x, z in prof]
bm.faces.new(f[::-1]); bm.faces.new(bk)
for i in range(5): j = (i + 1) % 5; bm.faces.new((f[i], f[j], bk[j], bk[i]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
walls = finish(bpy.data.objects.new('walls', me), 'white', .03)
# roof: two thick slabs with an overhang
a = math.atan2(R, W/2); L = math.hypot(W/2, R) + .32; T = .17
for side in (1, -1):
    ridge = Vector((0, 0, .16 + H + R)); down = Vector((side * math.cos(a), 0, -math.sin(a))); n = Vector((side * math.sin(a), 0, math.cos(a)))
    c = ridge + down * (L / 2 - .07) + n * (T / 2)
    s = box(f'roof_{"right" if side > 0 else "left"}', (L, D + .34, T), c, 'yellow', rot=(0, side * a, 0)); apply_scale(s); s.modifiers['Bevel'].width = .07; s.modifiers['Bevel'].segments = 6
# chimney on the right slope
ch = box('chimney', (.24, .26, .62), (.36, .3, .16 + H + R - .05), 'white'); apply_scale(ch); ch.modifiers['Bevel'].width = .04
cap = box('chimney_cap', (.32, .34, .1), (.36, .3, .16 + H + R + .27), 'white'); apply_scale(cap); cap.modifiers['Bevel'].width = .04
# windows: frame bars + glass, a touch proud of the wall
def window(name, cx, cz, w, h, face):   # face: 'front' (-y) or 'side' (+x)
    parts = []
    t, d = .05, .05
    def place(o):
        if face == 'side': o.rotation_euler = (0, 0, math.radians(90))
        return o
    if face == 'front': base_ = Vector((cx, -D/2 - .015, cz)); ax = Vector((1, 0, 0))
    else: base_ = Vector((W/2 + .015, cx, cz)); ax = Vector((0, 1, 0))
    g = box(name + '_glass', (w, .02, h), base_, 'glass', 0); place(g); parts.append(g)
    for k, (dx, dz, sw, sh) in enumerate([(0, h/2, w + t, t), (0, -h/2, w + t, t), (-w/2, 0, t, h - t), (w/2, 0, t, h - t), (0, 0, w - t, t*.6), (0, 0, t*.6, h - t)]):
        o = box(f'{name}_frame{k}', (sw, d, sh), base_ + ax * dx + Vector((0, 0, dz)), 'yellow', .015); place(o); apply_scale(o); o.modifiers['Bevel'].width = .012; parts.append(o)
    return parts
window('win_front', .33, .16 + .5, .3, .3, 'front')
window('win_side', .1, .16 + .52, .34, .32, 'side')
window('win_gable', 0, .16 + H + .18, .2, .2, 'front')
# door, knob and steps
door = box('door', (.32, .06, .56), (-.3, -D/2 - .02, .16 + .28), 'yellow'); apply_scale(door); door.modifiers['Bevel'].width = .03
bpy.ops.mesh.primitive_uv_sphere_add(radius=.025, location=(-.2, -D/2 - .06, .16 + .27)); kn = bpy.context.object; kn.name = 'door_knob'
kn.data.materials.append(M['metal']); bpy.ops.object.shade_smooth(); sc.collection.objects.unlink(kn) if kn.name in sc.collection.objects else None; col.objects.link(kn) if kn.name not in col.objects else None
for i in range(2):   # two chunky steps up to the door, sitting on the base
    dy = .26 - i * .11; s = box(f'step{i}', (.4, dy, .07), (-.3, -D/2 - dy/2 - .005, .16 + .035 + i * .07), 'yellow'); apply_scale(s); s.modifiers['Bevel'].width = .02

# ---- studio: soft key, fill, rim, soft grey world; one camera ----
studio = bpy.data.collections.new('studio'); sc.collection.children.link(studio)
def light(name, loc, energy, size, rgb=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.size = size; d.color = rgb
    o = bpy.data.objects.new(name, d); o.location = loc; studio.objects.link(o)
    o.rotation_euler = (Vector((0, 0, .7)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler(); return o
light('key', (-3.5, -4.5, 5.5), 1300, 4.5, (1, .97, .92))
light('fill', (5, -2.5, 2.5), 220, 6, (.92, .95, 1))
light('rim', (1.5, 5, 4), 500, 4)
w = bpy.data.worlds.new('world'); sc.world = w; w.use_nodes = True; w.node_tree.nodes['Background'].inputs['Color'].default_value = (.55, .55, .58, 1); w.node_tree.nodes['Background'].inputs['Strength'].default_value = .4
cam_d = bpy.data.cameras.new('camera'); cam_d.lens = 100; cam = bpy.data.objects.new('camera', cam_d); studio.objects.link(cam); sc.camera = cam
cam.location = (5.6, -7.4, 4.6); cam.rotation_euler = (Vector((0.05, 0, .75)) - cam.location).to_track_quat('-Z', 'Y').to_euler()

# ---- render ----
sc.render.engine = 'CYCLES'; sc.cycles.samples = 64; sc.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type = 'METAL'; prefs.get_devices()
    for d in prefs.devices: d.use = True
    sc.cycles.device = 'GPU'
except Exception as e: print('gpu', e)
sc.render.resolution_x = sc.render.resolution_y = 768; sc.render.film_transparent = True
sc.view_settings.view_transform = 'AgX'
try: sc.view_settings.look = 'AgX - Medium High Contrast'
except Exception: pass
sc.render.filepath = out_png; bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=out_blend)
print('DONE')
