# Shared kit for the cozy UI icons: one .blend (ui-icons.blend) with a collection per icon, shared soft materials,
# one studio (lights + world), and a render helper that shows only the icon being rendered.
import bpy, bmesh, math, os, sys
from mathutils import Vector
HERE = os.path.dirname(os.path.abspath(__file__)); BLEND = os.path.join(HERE, 'ui-icons.blend')

def srgb(h): return tuple(((int(h[i:i+2], 16) / 255) ** 2.2) for i in (1, 3, 5))

def open_file():
    if os.path.exists(BLEND): bpy.ops.wm.open_mainfile(filepath=BLEND)
    else: bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    if 'studio' not in bpy.data.collections: make_studio(sc)
    return sc

def mat(name, hexcol, rough=.6, sss=.25, sss_scale=.04, metal=0.0, emit=None):
    """Soft clay-like material, shared by name (re-used if it already exists)."""
    if name in bpy.data.materials: return bpy.data.materials[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']; c = srgb(hexcol)
    b.inputs['Base Color'].default_value = (*c, 1); b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if 'Subsurface Weight' in b.inputs:        # soft light bleeding through, like clay or soft plastic
        b.inputs['Subsurface Weight'].default_value = sss; b.inputs['Subsurface Scale'].default_value = sss_scale
        b.inputs['Subsurface Radius'].default_value = (1.0, .55, .35)
    if 'Specular IOR Level' in b.inputs: b.inputs['Specular IOR Level'].default_value = .35
    if emit:
        b.inputs['Emission Color'].default_value = (*srgb(emit[0]), 1); b.inputs['Emission Strength'].default_value = emit[1]
    return m

def new_icon(name):
    """A fresh collection for this icon (an old one of the same name is removed)."""
    if name in bpy.data.collections:
        c = bpy.data.collections[name]
        for o in list(c.objects): bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c)
    c = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(c); return c

def _link(col, o):
    for c in list(o.users_collection): c.objects.unlink(o)
    col.objects.link(o)

def finish(col, o, m, bevel=.04, seg=5, smooth=True):
    _link(col, o)
    if m: o.data.materials.clear(); o.data.materials.append(m)
    if bevel:
        b = o.modifiers.new('Bevel', 'BEVEL'); b.width = bevel; b.segments = seg; b.limit_method = 'ANGLE'; b.harden_normals = bevel >= .03
    if smooth:
        for p in o.data.polygons: p.use_smooth = True
    return o

def box(col, name, size, loc, m, bevel=.04, rot=(0, 0, 0), seg=5):
    me = bpy.data.meshes.new(name); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts: v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.location = loc; o.rotation_euler = rot
    return finish(col, o, m, min(bevel, min(size) * .49) if bevel else 0, seg)

def sphere(col, name, r, loc, m, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=48, ring_count=24, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale; return finish(col, o, m, 0)

def lathe(col, name, prof, loc, m, segs=64):
    """A round shape spun from a side profile [(radius, z), ...] (bottom to top)."""
    me = bpy.data.meshes.new(name); bm = bmesh.new(); rings = []
    for r, z in prof:
        ring = [bm.verts.new((r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs), z)) for k in range(segs)]; rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            j = (k + 1) % segs; bm.faces.new((a[k], a[j], b[j], b[k]))
    if prof[0][0] > 0: bm.faces.new(rings[0][::-1])
    if prof[-1][0] > 0: bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.location = loc
    s = o.modifiers.new('Smooth', 'SUBSURF'); s.levels = 2; s.render_levels = 2
    return finish(col, o, m, 0)

def prism(col, name, pts, depth, loc, m, bevel=.03, axis='y'):
    """Extrude a 2D outline [(x, z), ...] along y (or z when axis='z': outline in x, y)."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    if axis == 'y': f = [bm.verts.new((x, -depth/2, z)) for x, z in pts]; k = [bm.verts.new((x, depth/2, z)) for x, z in pts]
    else: f = [bm.verts.new((x, y, 0)) for x, y in pts]; k = [bm.verts.new((x, y, depth)) for x, y in pts]
    bm.faces.new(f); bm.faces.new(k[::-1])
    n = len(pts)
    for i in range(n): j = (i + 1) % n; bm.faces.new((f[i], f[j], k[j], k[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.location = loc; return finish(col, o, m, bevel)

def make_studio(sc):
    st = bpy.data.collections.new('studio'); sc.collection.children.link(st)
    def light(name, loc, energy, size, rgb):
        d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.size = size; d.color = rgb
        o = bpy.data.objects.new(name, d); o.location = loc; st.objects.link(o)
        o.rotation_euler = (Vector((0, 0, .6)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    light('key', (-3.5, -4.5, 5.5), 1300, 4.5, (1, .97, .92))
    light('fill', (5, -2.5, 2.5), 220, 6, (.93, .95, 1))
    light('rim', (1.5, 5, 4), 500, 4, (1, 1, 1))
    w = bpy.data.worlds.new('world'); sc.world = w; w.use_nodes = True
    w.node_tree.nodes['Background'].inputs['Color'].default_value = (.6, .6, .62, 1); w.node_tree.nodes['Background'].inputs['Strength'].default_value = .45
    cd = bpy.data.cameras.new('camera'); cam = bpy.data.objects.new('camera', cd); st.objects.link(cam); sc.camera = cam
    sc.render.engine = 'CYCLES'; sc.cycles.samples = 96; sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = 768; sc.render.film_transparent = True
    sc.view_settings.view_transform = 'AgX'
    try: sc.view_settings.look = 'AgX - Medium High Contrast'
    except Exception: pass

def aim_camera(loc, target, lens):
    cam = bpy.data.objects['camera']; cam.location = loc; cam.data.lens = lens
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()

def render(icon, out_png):
    sc = bpy.context.scene
    try:
        p = bpy.context.preferences.addons['cycles'].preferences; p.compute_device_type = 'METAL'; p.get_devices()
        for d in p.devices: d.use = True
        sc.cycles.device = 'GPU'
    except Exception as e: print('gpu', e)
    for c in sc.collection.children:      # only this icon (and the studio) in the render
        lc = bpy.context.view_layer.layer_collection.children[c.name]; lc.exclude = c.name not in (icon, 'studio')
    sc.render.filepath = out_png; bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print('DONE', icon)
