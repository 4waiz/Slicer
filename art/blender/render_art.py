"""Kanban Slicer - renders the game's 2D art from the shipped 3D assets.

World banners and the store icon are rendered from the exact GLB files the
game loads, so the menu art and the gameplay can never drift apart.

Run after ``kanban_lib.py`` has been exec'd in the same namespace.
"""

import math
import os

import bpy
from mathutils import Vector


def _pick_engine():
    engines = {e.identifier for e in
               bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items}
    for name in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
        if name in engines:
            return name
    return 'BLENDER_WORKBENCH'


def setup_scene(width, height, bg="#0B1E26", samples=48):
    scene = bpy.context.scene
    scene.render.engine = _pick_engine()
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    try:
        scene.eevee.taa_render_samples = samples
    except AttributeError:
        pass
    try:
        scene.cycles.samples = samples
    except AttributeError:
        pass

    # Blender defaults to AgX, which is built to tame photographic highlights
    # and desaturates these flat vivid materials into pastel mush. The game
    # renders in plain sRGB, so the art has to as well.
    try:
        scene.view_settings.view_transform = 'Standard'
        scene.view_settings.look = 'None'
        scene.view_settings.exposure = 0.0
        scene.view_settings.gamma = 1.0
    except (AttributeError, TypeError):
        pass

    # Controlled bloom, as called for by the art direction.
    try:
        scene.eevee.use_bloom = True
        scene.eevee.bloom_intensity = 0.045
        scene.eevee.bloom_threshold = 0.9
    except AttributeError:
        pass

    # Dark teal environment with a soft cyan lift.
    world = bpy.data.worlds.get("KS_World") or bpy.data.worlds.new("KS_World")
    world.use_nodes = True
    bg_node = world.node_tree.nodes.get("Background")
    r, g, b = col(bg)
    bg_node.inputs[0].default_value = (r, g, b, 1.0)
    bg_node.inputs[1].default_value = 0.85
    scene.world = world
    return scene


def add_lights(centre, radius):
    """Key, fill and rim -- the same three-light read the engine uses.

    Sun lamps rather than area lamps: their intensity does not fall off with
    distance, so the same values frame every asset regardless of its size.
    """
    specs = [
        ("key", (-1.0, -0.9, 1.5), 3.6, "#FFF4E0", 0.09),
        ("fill", (1.4, -0.6, 0.4), 1.5, "#5A9CB4", 0.30),
        ("rim", (0.5, 1.5, 0.7), 2.8, "#35D6F0", 0.15),
    ]
    for name, direction, power, colour, angle in specs:
        data = bpy.data.lights.new("L_" + name, type='SUN')
        data.energy = power
        data.color = col(colour)
        data.angle = angle
        obj = bpy.data.objects.new("L_" + name, data)
        bpy.context.collection.objects.link(obj)
        d = Vector(direction).normalized()
        obj.location = centre + d * (radius * 4.0)
        obj.rotation_mode = 'QUATERNION'
        obj.rotation_quaternion = (-d).to_track_quat('-Z', 'Y')


def frame_camera(centre, radius, azimuth=38.0, elevation=22.0, fill=0.78):
    cam_data = bpy.data.cameras.new("KS_Cam")
    cam_data.lens_unit = 'FOV'
    cam_data.angle = math.radians(38.0)
    cam = bpy.data.objects.new("KS_Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    dist = radius / (math.tan(cam_data.angle * 0.5) * fill)
    a = math.radians(azimuth)
    e = math.radians(elevation)
    offset = Vector((
        math.cos(e) * math.sin(a),
        -math.cos(e) * math.cos(a),
        math.sin(e),
    )) * dist
    cam.location = centre + offset
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = (-offset).to_track_quat('-Z', 'Y')
    return cam


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
    return new


def bounds_of(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    centre = (lo + hi) * 0.5
    radius = max((hi - lo).length * 0.5, 0.5)
    return centre, radius


def add_pad(colour, x, size=2.0):
    """Glowing landing pad, matching the in-game look."""
    bpy.ops.mesh.primitive_plane_add(size=size, location=(x, 0, 0))
    pad = bpy.context.object
    m = bpy.data.materials.new("PadGlow_%s" % colour)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    r, g, b = col(colour)
    bsdf.inputs["Base Color"].default_value = (r * 0.3, g * 0.3, b * 0.3, 1)
    if "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.2
    pad.data.materials.append(m)
    return pad


def render_to(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


# ---------------------------------------------------------------------------
# Deliverables
# ---------------------------------------------------------------------------

WORLD_HEROES = [
    (1, "crystal_cluster_large.glb", 34.0),
    (2, "layered_jelly.glb", 40.0),
    (3, "watermelon_tower.glb", 30.0),
    (4, "block_city.glb", 44.0),
    (5, "reactor_machine.glb", 36.0),
    (6, "kanban_planet.glb", 38.0),
]


def render_world_banners(models_dir, out_dir, width=1024, height=576):
    out = []
    for world, model, azimuth in WORLD_HEROES:
        reset_scene()
        setup_scene(width, height)
        objs = import_glb(os.path.join(models_dir, model))
        if not objs:
            continue
        centre, radius = bounds_of(objs)
        add_lights(centre, radius)
        frame_camera(centre, radius, azimuth=azimuth, elevation=16.0, fill=0.80)
        path = os.path.join(out_dir, "world%d.png" % world)
        render_to(path)
        out.append({"world": world, "file": os.path.basename(path),
                    "kb": round(os.path.getsize(path) / 1024.0, 1)})
    return out


def render_store_icon(models_dir, out_dir, size=512):
    """Square hero shot: the Kanban structure above its two glowing pads."""
    reset_scene()
    setup_scene(size, size)
    objs = import_glb(os.path.join(models_dir, "kanban_core_structure.glb"))
    centre, radius = bounds_of(objs)
    for o in objs:
        o.location.z += radius * 0.85
    centre.z += radius * 0.55

    add_pad("cyan", -radius * 0.75, size=radius * 1.05)
    add_pad("green", radius * 0.75, size=radius * 1.05)

    add_lights(centre, radius * 1.25)
    frame_camera(centre, radius * 1.30, azimuth=32.0, elevation=19.0, fill=0.92)
    path = os.path.join(out_dir, "store_icon.png")
    render_to(path)
    return {"file": "store_icon.png",
            "kb": round(os.path.getsize(path) / 1024.0, 1)}


def render_all(root):
    models = os.path.join(root, "assets", "models")
    images = os.path.join(root, "assets", "images")
    banners = render_world_banners(models, images)
    icon = render_store_icon(models, images)
    return {"banners": banners, "icon": icon}
