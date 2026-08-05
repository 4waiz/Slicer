"""Kanban Slicer - Blender procedural asset library.

Shared helpers used by every asset build script in ``art/blender/``.
Style target: faceted low-poly, chunky readable silhouettes, vibrant colour
sections, satin plastic/crystal materials -- matching ``icon.png`` (art bible).

All meshes produced here are:
  * closed / manifold (safe for runtime plane slicing + cap triangulation)
  * flat shaded with applied transforms
  * Y-up on export (glTF convention), origin at the volumetric centre
  * built from primitives + bevel only (no booleans, which break manifoldness)

Usage from Blender MCP:
    exec(open(r"<repo>/art/blender/kanban_lib.py").read())
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
# Palette (sampled from the art bible icon.png)
# ---------------------------------------------------------------------------

PALETTE = {
    "orange":       "#F07A2A",
    "orange_deep":  "#D95A16",
    "orange_light": "#FF9E4D",
    "yellow":       "#F5C93A",
    "gold":         "#FFD84D",
    "amber":        "#E8A317",
    "purple":       "#A05FD0",
    "purple_deep":  "#7A3FA8",
    "magenta":      "#C householder",  # replaced below
    "cyan":         "#35D6F0",
    "cyan_deep":    "#1BA8C4",
    "green":        "#3CE08A",
    "green_deep":   "#22A862",
    "steel":        "#7FA8C4",
    "steel_deep":   "#4A7089",
    "silver":       "#E8F4FA",
    "metal":        "#9FB4C4",
    "metal_dark":   "#2A3D4A",
    "teal_dark":    "#12303A",
    "teal_deep":    "#0B1E26",
    "white":        "#F2FBFF",
    "red":          "#F0524A",
    "pink":         "#F576B0",
    "lime":         "#B6E84A",
    "ice":          "#B8E8F5",
}
PALETTE["magenta"] = "#D94FA0"


def hex_to_rgb(h):
    """'#RRGGBB' -> linear (r, g, b) floats for Blender material nodes."""
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]

    def to_linear(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return tuple(to_linear(c) for c in srgb)


def col(name):
    """Palette name or raw hex -> linear rgb tuple."""
    return hex_to_rgb(PALETTE.get(name, name))


# ---------------------------------------------------------------------------
# Scene / material helpers
# ---------------------------------------------------------------------------

def reset_scene():
    """Wipe all objects and orphan data so each build starts clean."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def mat(name, colour, metallic=0.0, roughness=0.42, emission=0.0):
    """Create (or fetch) a satin material. ``colour`` is a palette key or hex."""
    key = "M_%s" % name
    if key in bpy.data.materials:
        return bpy.data.materials[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    r, g, b = col(colour)
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    m.diffuse_color = (r, g, b, 1.0)
    return m


def assign(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)
    return obj


def flat_shade(obj):
    mesh = obj.data
    for poly in mesh.polygons:
        poly.use_smooth = False
    return obj


def bevel(obj, width=0.02, segments=1, angle_deg=32.0):
    """Chunky edge bevel - gives the faceted 'moulded plastic' read."""
    md = obj.modifiers.new("bev", "BEVEL")
    md.width = width
    md.segments = segments
    md.limit_method = "ANGLE"
    md.angle_limit = math.radians(angle_deg)
    md.harden_normals = False
    _apply_modifiers(obj)
    return obj


def _apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for md in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=md.name)
        except RuntimeError:
            obj.modifiers.remove(md)


def _new(obj, name, material, loc, rot, scale):
    obj.name = name
    obj.location = loc
    if rot:
        obj.rotation_euler = [math.radians(a) for a in rot]
    if scale:
        obj.scale = scale
    if material:
        assign(obj, material)
    flat_shade(obj)
    return obj


# ---------------------------------------------------------------------------
# Primitive builders (all manifold)
# ---------------------------------------------------------------------------

def ico(name, r=0.5, subdiv=1, material=None, loc=(0, 0, 0), rot=None, scale=None):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=subdiv, location=loc)
    return _new(bpy.context.object, name, material, loc, rot, scale)


def cyl(name, r=0.5, depth=1.0, verts=10, material=None, loc=(0, 0, 0), rot=None, scale=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=loc)
    return _new(bpy.context.object, name, material, loc, rot, scale)


def cube(name, size=1.0, material=None, loc=(0, 0, 0), rot=None, scale=None):
    bpy.ops.mesh.primitive_cube_add(size=size, location=loc)
    return _new(bpy.context.object, name, material, loc, rot, scale)


def cone(name, r1=0.5, r2=0.0, depth=1.0, verts=8, material=None, loc=(0, 0, 0), rot=None, scale=None):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth, vertices=verts, location=loc)
    return _new(bpy.context.object, name, material, loc, rot, scale)


def torus(name, major=0.6, minor=0.16, mseg=12, nseg=6, material=None, loc=(0, 0, 0), rot=None, scale=None):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor,
        major_segments=mseg, minor_segments=nseg, location=loc)
    return _new(bpy.context.object, name, material, loc, rot, scale)


def gem(name, r=0.5, table=0.42, crown=0.30, pavilion=0.72, sides=8,
        material=None, loc=(0, 0, 0), rot=None, scale=None):
    """Classic faceted gem: flat table, crown facets, girdle, pavilion point.

    This is the yellow / purple crystal read from the art bible.
    """
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    girdle, crown_ring = [], []
    for i in range(sides):
        a = 2 * math.pi * i / sides
        girdle.append(bm.verts.new((r * math.cos(a), r * math.sin(a), 0.0)))
    for i in range(sides):
        a = 2 * math.pi * (i + 0.5) / sides  # offset ring -> staggered facets
        crown_ring.append(bm.verts.new((r * table * math.cos(a), r * table * math.sin(a), crown)))
    tip = bm.verts.new((0.0, 0.0, -pavilion))
    bm.verts.ensure_lookup_table()

    bm.faces.new(crown_ring)                                   # table
    for i in range(sides):                                     # crown facets
        j = (i + 1) % sides
        bm.faces.new((girdle[i], girdle[j], crown_ring[j]))
        bm.faces.new((girdle[i], crown_ring[j], crown_ring[i]))
    for i in range(sides):                                     # pavilion
        j = (i + 1) % sides
        bm.faces.new((girdle[j], girdle[i], tip))

    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    return _new(obj, name, material, loc, rot, scale)


def shard(name, r=0.22, h=0.55, sides=5, material=None, loc=(0, 0, 0), rot=None, scale=None):
    """Small angular fragment - crystal shards / debris pieces."""
    return cone(name, r1=r, r2=r * 0.18, depth=h, verts=sides,
                material=material, loc=loc, rot=rot, scale=scale)


def slab(name, w=1.0, d=1.0, h=0.2, material=None, loc=(0, 0, 0), rot=None, bev=0.03):
    o = cube(name, size=1.0, material=material, loc=loc, rot=rot, scale=(w, d, h))
    apply_transforms(o)
    if bev:
        bevel(o, bev, 1)
    return o


def ring_of(builder, count, radius, z=0.0, tilt=0.0, **kw):
    """Radially clone a builder ``count`` times - gear teeth, crystal clusters."""
    out = []
    for i in range(count):
        a = 2 * math.pi * i / count
        loc = (radius * math.cos(a), radius * math.sin(a), z)
        rot = kw.pop("rot", None) or (0, tilt, math.degrees(a))
        out.append(builder(loc=loc, rot=rot, **kw))
    return out


# ---------------------------------------------------------------------------
# Object assembly / finalisation
# ---------------------------------------------------------------------------

def apply_transforms(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def join(objs, name):
    """Join a list of objects into one multi-material mesh."""
    objs = [o for o in objs if o is not None]
    for o in objs:
        apply_transforms(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name
    return obj


def finalize(obj, name=None, origin="BOUNDS"):
    """Apply transforms, centre the pivot, recalc normals, flat shade."""
    if name:
        obj.name = name
        obj.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    if origin == "BOUNDS":
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    elif origin == "MASS":
        bpy.ops.object.origin_set(type="ORIGIN_CENTER_OF_VOLUME")
    obj.location = (0.0, 0.0, 0.0)

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    flat_shade(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def tri_count(obj):
    """Triangle count after triangulation (what the GLB will contain)."""
    n = 0
    for p in obj.data.polygons:
        n += max(1, len(p.vertices) - 2)
    return n


def mat_count(obj):
    return max(1, len(obj.data.materials))


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

EXPORT_DIR = None  # set by build scripts


def export_glb(obj, filename, export_dir=None):
    """Export a single object as GLB. Returns a manifest dict."""
    out_dir = export_dir or EXPORT_DIR
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, filename)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
        export_yup=True,
        export_normals=True,
        export_texcoords=False,
        export_tangents=False,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_extras=False,
    )
    return {
        "name": obj.name,
        "file": filename,
        "tris": tri_count(obj),
        "materials": mat_count(obj),
        "size": round(os.path.getsize(path) / 1024.0, 1),
        "dims": [round(d, 3) for d in obj.dimensions],
    }


def save_source(blend_path):
    os.makedirs(os.path.dirname(blend_path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    return blend_path
