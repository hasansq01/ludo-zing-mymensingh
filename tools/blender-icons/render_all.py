# Renders every icon collection from ui-icons.blend as it is (your edits kept, nothing rebuilt, file not saved).
import bpy, os
from mathutils import Vector
HERE = os.path.dirname(os.path.abspath(__file__)); OUT = os.path.join(HERE, 'renders')
SHOTS = [('icon_ludo_board', 'icon01_ludo_board', (0, -5.4, 5.6), (0, .08, .1), 84),
         ('icon_snake_ladder', 'icon02_snake_ladder', (1.0, -7.8, 3.1), (.35, 0, 1.4), 72),
         ('icon_play', 'icon03_play', (0, -6.4, 1.6), (0, 0, 0), 64),
         ('icon_friends', 'icon04_friends', (0, -7.2, 2.6), (.02, .25, 1.0), 66),
         ('icon_robot', 'icon05_robot', (0, -6.6, 2.2), (0, 0, .95), 62),
         ('icon_swap', 'icon06_swap', (0, -7.4, 2.2), (0, 0, .76), 74),
         ('icon_house', 'icon07_house', (-5.4, -5.8, 3.7), (.05, 0, .95), 66),
         ('icon_bag', 'icon08_bag', (2.4, -6.4, 2.7), (0, 0, 1.05), 70),
         ('icon_trophy', 'icon09_trophy', (0, -7.2, 2.6), (0, 0, 1.12), 64),
         ('icon_chest', 'icon10_chest', (2.6, -6.3, 3.0), (0, 0, .82), 64)]
sc = bpy.context.scene
p = bpy.context.preferences.addons['cycles'].preferences; p.compute_device_type = 'METAL'; p.get_devices()
for d in p.devices: d.use = True
sc.cycles.device = 'GPU'
cam = bpy.data.objects['camera']
for col, name, loc, target, lens in SHOTS:
    for c in sc.collection.children:
        bpy.context.view_layer.layer_collection.children[c.name].exclude = c.name not in (col, 'studio')
    cam.location = loc; cam.data.lens = lens
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = os.path.join(OUT, name + '.png'); bpy.ops.render.render(write_still=True); print('RENDERED', name)
