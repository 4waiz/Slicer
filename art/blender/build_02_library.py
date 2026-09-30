"""Kanban Slicer - full slicable asset library.

Every model is built from manifold primitives so the runtime slicer can cap
the cut cleanly. Nested shells (orb cores, planet layers) are intentional:
they only reveal themselves when the player cuts through, which is the whole
point of the protected-core and layered-planet mechanics.

Run after ``kanban_lib.py`` has been exec'd in the same namespace.
"""

import math

LIB = []


def _log(e):
    LIB.append(e)
    return e


def M(name, colour, metallic=0.0, rough=0.4, emis=0.0):
    return mat(name, colour, metallic, rough, emis)


def _finish(parts, name):
    obj = join(parts, name)
    finalize(obj, origin="BOUNDS")
    return _log(export_glb(obj, name + ".glb"))


# ===========================================================================
# WORLD 1 - CRYSTAL WORKSHOP
# ===========================================================================

def crystal_cluster_small():
    reset_scene()
    c, p, s = M("cyan", "cyan", 0.1, 0.22), M("purple", "purple", 0.1, 0.26), M("steel_deep", "steel_deep", 0.6, 0.4)
    parts = [
        slab("base", 1.5, 1.2, 0.22, s, (0, 0, -0.75)),
        gem("g1", 0.46, 0.40, 0.34, 0.62, 6, c, (-0.34, 0.06, 0.05)),
        gem("g2", 0.34, 0.42, 0.26, 0.46, 6, p, (0.38, -0.10, -0.12), (0, 14, 0)),
        gem("g3", 0.26, 0.44, 0.22, 0.38, 5, c, (0.16, 0.34, 0.30), (0, -20, 30)),
    ]
    return _finish(parts, "crystal_cluster_small")


def crystal_cluster_large():
    reset_scene()
    c = M("cyan", "cyan", 0.1, 0.2)
    cd = M("cyan_deep", "cyan_deep", 0.1, 0.28)
    p = M("purple", "purple", 0.1, 0.24)
    pd = M("purple_deep", "purple_deep", 0.1, 0.3)
    parts = [
        slab("base", 2.2, 1.6, 0.26, M("steel_deep", "steel_deep", 0.6, 0.42), (0, 0, -1.0)),
        gem("c1", 0.56, 0.38, 0.44, 0.80, 8, c, (-0.72, 0.02, 0.16)),
        gem("c2", 0.36, 0.42, 0.28, 0.52, 6, cd, (-0.32, 0.30, -0.22), (0, 18, 20)),
        gem("c3", 0.30, 0.44, 0.24, 0.44, 6, c, (-1.06, -0.26, -0.30), (0, -16, 0)),
        gem("p1", 0.52, 0.38, 0.40, 0.74, 8, p, (0.74, -0.04, 0.12), (0, 0, 24)),
        gem("p2", 0.34, 0.42, 0.26, 0.48, 6, pd, (0.34, 0.28, -0.24), (0, -14, 0)),
        gem("p3", 0.28, 0.44, 0.22, 0.40, 5, p, (1.10, 0.24, -0.28), (0, 20, 40)),
    ]
    return _finish(parts, "crystal_cluster_large")


def layered_crystal():
    reset_scene()
    c, p, y = M("cyan", "cyan", 0.1, 0.22), M("purple", "purple", 0.1, 0.26), M("yellow", "yellow", 0.1, 0.24)
    parts = [
        cyl("l1", 0.86, 0.34, 10, c, (0, 0, -0.62)),
        cyl("l2", 0.72, 0.32, 10, p, (0, 0, -0.26)),
        cyl("l3", 0.58, 0.30, 10, y, (0, 0, 0.08)),
        gem("cap", 0.50, 0.36, 0.44, 0.30, 8, c, (0, 0, 0.52)),
    ]
    return _finish(parts, "layered_crystal")


def crystal_orb():
    """Cyan shell around a hidden white core - a protected-core level."""
    reset_scene()
    c, y, w = M("cyan", "cyan", 0.1, 0.2), M("yellow", "yellow", 0.1, 0.24), M("white", "white", 0.0, 0.15, 1.4)
    parts = [
        ico("shell", 0.92, 2, c),
        ico("mantle", 0.58, 1, y),
        ico("core", 0.28, 1, w),
    ]
    return _finish(parts, "crystal_orb")


def crystal_ring():
    reset_scene()
    c, p = M("cyan", "cyan", 0.1, 0.22), M("purple", "purple", 0.1, 0.26)
    parts = [
        torus("ring", 0.86, 0.24, 14, 6, c),
        gem("node_a", 0.32, 0.42, 0.24, 0.42, 6, p, (0.86, 0, 0.0)),
        gem("node_b", 0.32, 0.42, 0.24, 0.42, 6, p, (-0.86, 0, 0.0), (180, 0, 0)),
    ]
    return _finish(parts, "crystal_ring")


def crystal_tower():
    reset_scene()
    c, p, s = M("cyan", "cyan", 0.1, 0.22), M("purple", "purple", 0.1, 0.26), M("steel_deep", "steel_deep", 0.6, 0.42)
    parts = [
        slab("foot", 1.3, 1.3, 0.24, s, (0, 0, -1.28)),
        cyl("t1", 0.58, 0.62, 8, p, (0, 0, -0.82)),
        cyl("t2", 0.48, 0.58, 8, c, (0, 0, -0.20)),
        cyl("t3", 0.38, 0.54, 8, p, (0, 0, 0.36)),
        gem("spire", 0.42, 0.30, 0.72, 0.26, 6, c, (0, 0, 0.92)),
    ]
    return _finish(parts, "crystal_tower")


def crystal_bridge():
    reset_scene()
    c, g, s = M("cyan", "cyan", 0.1, 0.22), M("green", "green", 0.1, 0.24), M("steel", "steel", 0.6, 0.36)
    parts = [
        slab("deck", 3.0, 0.7, 0.26, s, (0, 0, 0)),
        cyl("pillar_l", 0.30, 1.0, 8, c, (-1.16, 0, -0.58)),
        cyl("pillar_r", 0.30, 1.0, 8, g, (1.16, 0, -0.58)),
        gem("top_l", 0.40, 0.40, 0.34, 0.44, 6, c, (-1.16, 0, 0.46)),
        gem("top_r", 0.40, 0.40, 0.34, 0.44, 6, g, (1.16, 0, 0.46)),
    ]
    return _finish(parts, "crystal_bridge")


def crystal_core_machine():
    reset_scene()
    c = M("cyan", "cyan", 0.1, 0.22)
    o = M("orange", "orange", 0.2, 0.36)
    md = M("metal_dark", "metal_dark", 0.7, 0.46)
    p = M("purple", "purple", 0.1, 0.24)
    parts = [
        cyl("housing", 0.82, 1.10, 12, md, (0, 0, 0)),
        cyl("band_a", 0.90, 0.20, 12, o, (0, 0, 0.34)),
        cyl("band_b", 0.90, 0.20, 12, o, (0, 0, -0.34)),
        gem("core", 0.46, 0.40, 0.40, 0.52, 8, p),
        cyl("rod_l", 0.14, 0.9, 6, c, (-0.94, 0, 0), (0, 90, 0)),
        cyl("rod_r", 0.14, 0.9, 6, c, (0.94, 0, 0), (0, 90, 0)),
    ]
    return _finish(parts, "crystal_core_machine")


# ===========================================================================
# WORLD 2 - JELLY LABORATORY
# ===========================================================================

def _jelly_cube_obj(name, size, material, loc, bev=0.16):
    o = cube(name, size=size, material=material, loc=loc)
    apply_transforms(o)
    bevel(o, bev, 2)
    return o


def jelly_cube():
    reset_scene()
    pk, lm = M("pink", "pink", 0.0, 0.22), M("lime", "lime", 0.0, 0.22)
    parts = [
        _jelly_cube_obj("a", 1.2, pk, (0, 0, 0.32)),
        _jelly_cube_obj("b", 1.0, lm, (0, 0, -0.52), 0.14),
    ]
    return _finish(parts, "jelly_cube")


def jelly_tower():
    reset_scene()
    pk, lm, cy = M("pink", "pink", 0, 0.22), M("lime", "lime", 0, 0.22), M("cyan", "cyan", 0, 0.22)
    parts = [
        _jelly_cube_obj("a", 1.1, cy, (0, 0, -0.86), 0.14),
        _jelly_cube_obj("b", 0.94, pk, (0, 0, 0.0), 0.12),
        _jelly_cube_obj("c", 0.78, lm, (0, 0, 0.74), 0.10),
    ]
    return _finish(parts, "jelly_tower")


def jelly_ring():
    reset_scene()
    pk, cy = M("pink", "pink", 0, 0.22), M("cyan", "cyan", 0, 0.22)
    parts = [
        torus("ring", 0.84, 0.30, 14, 8, pk),
        ico("bead_a", 0.28, 1, cy, (0.84, 0, 0)),
        ico("bead_b", 0.28, 1, cy, (-0.84, 0, 0)),
    ]
    return _finish(parts, "jelly_ring")


def jelly_capsule():
    reset_scene()
    lm, pk = M("lime", "lime", 0, 0.22), M("pink", "pink", 0, 0.22)
    parts = [
        cyl("body", 0.52, 1.10, 12, lm, (0, 0, 0)),
        ico("cap_t", 0.52, 2, pk, (0, 0, 0.55)),
        ico("cap_b", 0.52, 2, pk, (0, 0, -0.55)),
    ]
    return _finish(parts, "jelly_capsule")


def layered_jelly():
    reset_scene()
    pk, lm, cy, y = (M("pink", "pink", 0, 0.22), M("lime", "lime", 0, 0.22),
                     M("cyan", "cyan", 0, 0.22), M("yellow", "yellow", 0, 0.22))
    parts = []
    cols = [pk, lm, cy, y]
    for i, c in enumerate(cols):
        parts.append(slab("layer_%d" % i, 1.7 - i * 0.16, 1.5 - i * 0.14, 0.30, c,
                          (0, 0, -0.72 + i * 0.36), bev=0.06))
    return _finish(parts, "layered_jelly")


def jelly_bridge():
    reset_scene()
    pk, cy, lm = M("pink", "pink", 0, 0.22), M("cyan", "cyan", 0, 0.22), M("lime", "lime", 0, 0.22)
    parts = [
        slab("span", 3.1, 0.8, 0.34, cy, (0, 0, 0.1), bev=0.10),
        ico("post_l", 0.46, 1, pk, (-1.24, 0, -0.52)),
        ico("post_r", 0.46, 1, lm, (1.24, 0, -0.52)),
    ]
    return _finish(parts, "jelly_bridge")


def jelly_machine():
    reset_scene()
    md = M("metal_dark", "metal_dark", 0.7, 0.46)
    pk, lm, cy = M("pink", "pink", 0, 0.22), M("lime", "lime", 0, 0.22), M("cyan", "cyan", 0, 0.22)
    parts = [
        cyl("tank", 0.74, 1.2, 12, cy, (0, 0, 0)),
        cyl("collar_t", 0.84, 0.18, 12, md, (0, 0, 0.62)),
        cyl("collar_b", 0.84, 0.18, 12, md, (0, 0, -0.62)),
        ico("blob_a", 0.40, 1, pk, (0, 0, 0.28)),
        ico("blob_b", 0.34, 1, lm, (0, 0, -0.30)),
        cyl("pipe", 0.13, 1.5, 6, md, (0.86, 0, 0), (0, 90, 0)),
    ]
    return _finish(parts, "jelly_machine")


# ===========================================================================
# WORLD 3 - FRUIT FOUNDRY
# ===========================================================================

def apple_structure():
    reset_scene()
    r, g, br, w = (M("red", "red", 0, 0.3), M("green", "green", 0, 0.3),
                   M("orange_deep", "orange_deep", 0, 0.5), M("white", "white", 0, 0.4))
    parts = [
        ico("flesh", 0.60, 1, w),
        ico("skin", 0.86, 2, r),
        cyl("stem", 0.07, 0.44, 5, br, (0, 0, 0.92)),
        slab("leaf", 0.44, 0.18, 0.06, g, (0.26, 0, 0.98), (0, 22, 0), bev=0.02),
    ]
    return _finish(parts, "apple_structure")


def watermelon_tower():
    reset_scene()
    g, w, r = (M("green_deep", "green_deep", 0, 0.34), M("white", "white", 0, 0.4),
               M("red", "red", 0, 0.3))
    parts = []
    for i, (z, s) in enumerate([(-0.72, 1.0), (0.16, 0.82), (0.86, 0.62)]):
        parts.append(ico("rind_%d" % i, 0.62 * s, 2, g, (0, 0, z)))
        parts.append(ico("pith_%d" % i, 0.52 * s, 1, w, (0, 0, z)))
        parts.append(ico("flesh_%d" % i, 0.42 * s, 1, r, (0, 0, z)))
    return _finish(parts, "watermelon_tower")


def orange_stack():
    reset_scene()
    o, y, g = (M("orange", "orange", 0, 0.34), M("gold", "gold", 0, 0.3),
               M("green", "green", 0, 0.32))
    parts = []
    for i, (x, z, s) in enumerate([(-0.52, -0.42, 1.0), (0.52, -0.42, 0.94), (0, 0.42, 1.06)]):
        parts.append(ico("peel_%d" % i, 0.50 * s, 2, o, (x, 0, z)))
        parts.append(ico("pulp_%d" % i, 0.36 * s, 1, y, (x, 0, z)))
    parts.append(cyl("stalk", 0.06, 0.3, 5, g, (0, 0, 1.02)))
    return _finish(parts, "orange_stack")


def pineapple_machine():
    reset_scene()
    y, g, md = (M("gold", "gold", 0, 0.32), M("green", "green", 0, 0.32),
                M("metal_dark", "metal_dark", 0.7, 0.46))
    parts = [
        cyl("body", 0.62, 1.5, 10, y, (0, 0, 0)),
        cyl("rib_a", 0.68, 0.14, 10, md, (0, 0, 0.42)),
        cyl("rib_b", 0.68, 0.14, 10, md, (0, 0, -0.42)),
    ]
    for i in range(5):
        a = 2 * math.pi * i / 5
        parts.append(cone("leaf_%d" % i, 0.12, 0.01, 0.72, 4, g,
                          (0.18 * math.cos(a), 0.18 * math.sin(a), 1.06),
                          (math.degrees(0.28) * math.sin(a), math.degrees(0.28) * math.cos(a), 0)))
    return _finish(parts, "pineapple_machine")


def dragonfruit_crystal():
    reset_scene()
    mg, w, g = (M("magenta", "magenta", 0, 0.28), M("white", "white", 0, 0.36),
                M("lime", "lime", 0, 0.3))
    parts = [
        ico("flesh", 0.56, 2, w),
        gem("skin", 0.78, 0.34, 0.72, 0.86, 8, mg),
    ]
    for i in range(6):
        a = 2 * math.pi * i / 6
        parts.append(cone("fin_%d" % i, 0.16, 0.02, 0.44, 4, g,
                          (0.66 * math.cos(a), 0.66 * math.sin(a), 0.12),
                          (0, 62, math.degrees(a))))
    return _finish(parts, "dragonfruit_crystal")


def fruit_ring():
    reset_scene()
    o, w, g = (M("orange", "orange", 0, 0.34), M("white", "white", 0, 0.4),
               M("green", "green", 0, 0.32))
    parts = [
        torus("rind", 0.82, 0.30, 14, 8, o),
        torus("pulp", 0.82, 0.18, 14, 6, w),
        ico("bud", 0.24, 1, g, (0, 0, 0.34)),
    ]
    return _finish(parts, "fruit_ring")


def layered_fruit_planet():
    reset_scene()
    g, w, r, y = (M("green_deep", "green_deep", 0, 0.34), M("white", "white", 0, 0.4),
                  M("red", "red", 0, 0.3), M("gold", "gold", 0, 0.3))
    parts = [
        ico("crust", 1.00, 2, g),
        ico("mantle", 0.76, 2, w),
        ico("pulp", 0.52, 1, r),
        ico("seed", 0.26, 1, y),
    ]
    return _finish(parts, "layered_fruit_planet")


# ===========================================================================
# WORLD 4 - TOY CITY
# ===========================================================================

def toy_house():
    reset_scene()
    c, r, y = (M("cyan", "cyan", 0, 0.36), M("red", "red", 0, 0.34), M("yellow", "yellow", 0, 0.32))
    parts = [
        slab("walls", 1.3, 1.1, 0.9, c, (0, 0, -0.3), bev=0.05),
        cone("roof", 1.0, 0.02, 0.72, 4, r, (0, 0, 0.52), (0, 0, 45)),
        slab("door", 0.34, 0.1, 0.46, y, (0, -0.56, -0.44), bev=0.02),
    ]
    return _finish(parts, "toy_house")


def toy_tower():
    reset_scene()
    cols = [M("orange", "orange", 0, 0.34), M("cyan", "cyan", 0, 0.34),
            M("yellow", "yellow", 0, 0.32), M("purple", "purple", 0, 0.32)]
    parts = []
    for i, c in enumerate(cols):
        parts.append(slab("blk_%d" % i, 1.15 - i * 0.14, 1.15 - i * 0.14, 0.46, c,
                          (0, 0, -0.9 + i * 0.5), bev=0.05))
    return _finish(parts, "toy_tower")


def toy_bridge():
    reset_scene()
    o, c, s = (M("orange", "orange", 0, 0.34), M("cyan", "cyan", 0, 0.34),
               M("steel", "steel", 0.5, 0.4))
    parts = [
        slab("deck", 3.2, 0.8, 0.22, s, (0, 0, 0)),
        slab("tower_l", 0.42, 0.42, 1.3, o, (-1.1, 0, 0.66), bev=0.04),
        slab("tower_r", 0.42, 0.42, 1.3, c, (1.1, 0, 0.66), bev=0.04),
        cyl("cable", 0.06, 2.3, 5, s, (0, 0, 1.16), (0, 90, 0)),
    ]
    return _finish(parts, "toy_bridge")


def toy_factory():
    reset_scene()
    s, o, y, md = (M("steel", "steel", 0.5, 0.4), M("orange", "orange", 0, 0.34),
                   M("yellow", "yellow", 0, 0.32), M("metal_dark", "metal_dark", 0.7, 0.46))
    parts = [
        slab("hall", 1.9, 1.2, 0.86, s, (0, 0, -0.42), bev=0.05),
        cyl("stack_a", 0.20, 1.0, 8, o, (-0.52, 0, 0.52)),
        cyl("stack_b", 0.20, 0.78, 8, o, (0.0, 0, 0.40)),
        cyl("stack_c", 0.20, 1.16, 8, y, (0.52, 0, 0.60)),
        slab("vent", 1.5, 0.5, 0.16, md, (0, 0, 0.08), bev=0.03),
    ]
    return _finish(parts, "toy_factory")


def toy_castle():
    reset_scene()
    s, p, y = (M("steel", "steel", 0.5, 0.4), M("purple", "purple", 0, 0.32),
               M("yellow", "yellow", 0, 0.32))
    parts = [slab("keep", 1.5, 1.2, 1.0, s, (0, 0, -0.3), bev=0.05)]
    for i, x in enumerate((-0.86, 0.86)):
        parts.append(cyl("tower_%d" % i, 0.32, 1.5, 8, s, (x, 0, 0.0)))
        parts.append(cone("cap_%d" % i, 0.42, 0.02, 0.56, 6, p, (x, 0, 1.02)))
    parts.append(slab("gate", 0.42, 0.12, 0.56, y, (0, -0.62, -0.5), bev=0.02))
    return _finish(parts, "toy_castle")


def block_city():
    reset_scene()
    cols = [M("cyan", "cyan", 0, 0.34), M("orange", "orange", 0, 0.34),
            M("yellow", "yellow", 0, 0.32), M("purple", "purple", 0, 0.32),
            M("green", "green", 0, 0.32)]
    layout = [(-1.30, 0.0, 0.9), (-0.55, 0.10, 1.35), (0.20, -0.08, 0.75),
              (0.92, 0.06, 1.15), (1.58, -0.04, 0.62)]
    parts = []
    for i, (x, y, h) in enumerate(layout):
        parts.append(slab("bldg_%d" % i, 0.56, 0.56, h, cols[i % len(cols)],
                          (x, y, -0.7 + h * 0.5), bev=0.04))
    parts.append(slab("ground", 3.6, 1.5, 0.18, M("steel_deep", "steel_deep", 0.5, 0.45),
                      (0.15, 0, -0.80), bev=0.03))
    return _finish(parts, "block_city")


def stacked_toy_buildings():
    reset_scene()
    o, c, y, p = (M("orange", "orange", 0, 0.34), M("cyan", "cyan", 0, 0.34),
                  M("yellow", "yellow", 0, 0.32), M("purple", "purple", 0, 0.32))
    parts = [
        slab("b1", 1.5, 1.2, 0.6, o, (0, 0, -0.9), bev=0.05),
        slab("b2", 1.2, 1.0, 0.55, c, (0.16, 0, -0.28), (0, 0, 12), bev=0.05),
        slab("b3", 0.95, 0.85, 0.5, y, (-0.14, 0, 0.28), (0, 0, -16), bev=0.04),
        cone("spire", 0.55, 0.02, 0.62, 4, p, (0, 0, 0.86), (0, 0, 45)),
    ]
    return _finish(parts, "stacked_toy_buildings")


# ===========================================================================
# WORLD 5 - MECHANICAL CORE
# ===========================================================================

def _gear(name, radius, thick, teeth, material, loc=(0, 0, 0), tooth_mat=None):
    parts = [cyl(name + "_hub", radius, thick, 12, material, loc)]
    tm = tooth_mat or material
    for i in range(teeth):
        a = 2 * math.pi * i / teeth
        parts.append(cube(name + "_t%d" % i, size=1.0, material=tm,
                          loc=(loc[0] + (radius + 0.09) * math.cos(a),
                               loc[1] + (radius + 0.09) * math.sin(a),
                               loc[2]),
                          rot=(0, 0, math.degrees(a)),
                          scale=(0.20, 0.13, thick)))
    return parts


def gear_machine():
    reset_scene()
    s, o, md = (M("metal", "metal", 0.85, 0.3), M("orange", "orange", 0.2, 0.36),
                M("metal_dark", "metal_dark", 0.75, 0.44))
    parts = []
    parts += _gear("g_main", 0.66, 0.26, 10, s, (0, 0, 0), md)
    parts += _gear("g_side", 0.40, 0.22, 8, o, (1.02, 0, 0.16), md)
    parts.append(cyl("axle", 0.12, 0.9, 8, md, (0, 0, 0), (0, 0, 0)))
    return _finish(parts, "gear_machine")


def layered_engine():
    reset_scene()
    md, o, c, s = (M("metal_dark", "metal_dark", 0.75, 0.44), M("orange", "orange", 0.2, 0.36),
                   M("cyan", "cyan", 0.1, 0.24, 0.5), M("metal", "metal", 0.85, 0.3))
    parts = [
        slab("block", 1.6, 1.1, 0.5, md, (0, 0, -0.5), bev=0.04),
        cyl("cyl_a", 0.28, 0.7, 8, s, (-0.44, 0, 0.10)),
        cyl("cyl_b", 0.28, 0.7, 8, s, (0.0, 0, 0.10)),
        cyl("cyl_c", 0.28, 0.7, 8, s, (0.44, 0, 0.10)),
        slab("head", 1.5, 0.9, 0.24, o, (0, 0, 0.56), bev=0.03),
        cyl("core", 0.22, 1.7, 8, c, (0, 0, -0.5), (0, 90, 0)),
    ]
    return _finish(parts, "layered_engine")


def turbine_stack():
    reset_scene()
    s, o, md = (M("metal", "metal", 0.85, 0.3), M("orange", "orange", 0.2, 0.36),
                M("metal_dark", "metal_dark", 0.75, 0.44))
    parts = [cyl("shaft", 0.16, 2.2, 8, md)]
    for i, z in enumerate((-0.72, 0.0, 0.72)):
        m = s if i % 2 == 0 else o
        parts.append(cyl("disc_%d" % i, 0.74 - i * 0.10, 0.16, 12, m, (0, 0, z)))
        for k in range(8):
            a = 2 * math.pi * k / 8
            r = 0.74 - i * 0.10
            parts.append(cube("blade_%d_%d" % (i, k), 1.0, md,
                              ((r + 0.14) * math.cos(a), (r + 0.14) * math.sin(a), z),
                              (0, 26, math.degrees(a)), (0.22, 0.08, 0.14)))
    return _finish(parts, "turbine_stack")


def reactor_machine():
    reset_scene()
    md, c, o = (M("metal_dark", "metal_dark", 0.75, 0.44), M("cyan", "cyan", 0.1, 0.22, 1.1),
                M("orange", "orange", 0.2, 0.36))
    parts = [
        cyl("vessel", 0.80, 1.4, 12, md),
        cyl("rim_t", 0.90, 0.18, 12, o, (0, 0, 0.70)),
        cyl("rim_b", 0.90, 0.18, 12, o, (0, 0, -0.70)),
        ico("core", 0.42, 1, c),
    ]
    for i in range(4):
        a = 2 * math.pi * i / 4
        parts.append(cyl("rod_%d" % i, 0.09, 1.2, 6, o,
                         (0.72 * math.cos(a), 0.72 * math.sin(a), 0)))
    return _finish(parts, "reactor_machine")


def mechanical_orb():
    reset_scene()
    s, md, c = (M("metal", "metal", 0.85, 0.3), M("metal_dark", "metal_dark", 0.75, 0.44),
                M("cyan", "cyan", 0.1, 0.22, 1.0))
    parts = [
        ico("shell", 0.88, 2, s),
        torus("band_a", 0.94, 0.09, 14, 5, md),
        torus("band_b", 0.94, 0.09, 14, 5, md, (0, 0, 0), (90, 0, 0)),
        ico("core", 0.36, 1, c),
    ]
    return _finish(parts, "mechanical_orb")


def rotating_cylinder_machine():
    reset_scene()
    md, o, s, c = (M("metal_dark", "metal_dark", 0.75, 0.44), M("orange", "orange", 0.2, 0.36),
                   M("metal", "metal", 0.85, 0.3), M("cyan", "cyan", 0.1, 0.22, 0.7))
    parts = [
        cyl("drum", 0.68, 1.8, 12, s, (0, 0, 0), (0, 90, 0)),
        cyl("ring_a", 0.76, 0.20, 12, o, (-0.62, 0, 0), (0, 90, 0)),
        cyl("ring_b", 0.76, 0.20, 12, o, (0.62, 0, 0), (0, 90, 0)),
        cyl("cap_l", 0.50, 0.22, 10, md, (-1.00, 0, 0), (0, 90, 0)),
        cyl("cap_r", 0.50, 0.22, 10, md, (1.00, 0, 0), (0, 90, 0)),
        cyl("vein", 0.14, 1.9, 6, c, (0, 0, 0.42), (0, 90, 0)),
    ]
    return _finish(parts, "rotating_cylinder_machine")


def magnet_machine():
    reset_scene()
    r, s, md = (M("red", "red", 0.3, 0.36), M("metal", "metal", 0.9, 0.26),
                M("metal_dark", "metal_dark", 0.75, 0.44))
    parts = [
        torus("horseshoe", 0.72, 0.26, 12, 6, r),
        slab("pole_l", 0.36, 0.5, 0.34, s, (-0.72, 0, 0.52), bev=0.03),
        slab("pole_r", 0.36, 0.5, 0.34, s, (0.72, 0, 0.52), bev=0.03),
        slab("base", 1.9, 0.7, 0.22, md, (0, 0, -0.86), bev=0.03),
    ]
    return _finish(parts, "magnet_machine")


def kanban_machine():
    reset_scene()
    md, o, y, c, p = (M("metal_dark", "metal_dark", 0.75, 0.44), M("orange", "orange", 0.2, 0.36),
                      M("yellow", "yellow", 0.1, 0.28), M("cyan", "cyan", 0.1, 0.22, 0.8),
                      M("purple", "purple", 0.1, 0.26))
    parts = [
        slab("frame", 2.0, 1.0, 0.36, md, (0, 0, -0.72), bev=0.04),
        cyl("barrel", 0.52, 1.5, 12, o, (-0.42, 0, 0.06), (0, 90, 0)),
        cyl("collar", 0.60, 0.22, 12, y, (0.18, 0, 0.06), (0, 90, 0)),
        gem("crystal", 0.50, 0.38, 0.42, 0.60, 8, y, (1.02, 0, 0.20)),
        gem("under", 0.36, 0.42, 0.24, 0.42, 6, p, (1.10, 0, -0.42), (180, 0, 0)),
        cyl("lamp", 0.16, 0.4, 8, c, (-1.16, 0, 0.34)),
    ]
    return _finish(parts, "kanban_machine")


# ===========================================================================
# WORLD 6 - PLANETS
# ===========================================================================

def _planet(name, layers):
    """layers: list of (radius, material, subdiv) from outside in.

    The caller must have already called ``reset_scene()``; materials created
    before the reset would be purged as orphans and left dangling.
    """
    parts = []
    for i, (r, m, sd) in enumerate(layers):
        parts.append(ico("layer_%d" % i, r, sd, m))
    return _finish(parts, name)


def layered_planet_basic():
    reset_scene()
    return _planet("layered_planet_basic", [
        (1.00, M("cyan", "cyan", 0.1, 0.3), 2),
        (0.74, M("purple", "purple", 0.1, 0.3), 2),
        (0.46, M("yellow", "yellow", 0.1, 0.28), 1),
    ])


def lava_planet():
    reset_scene()
    return _planet("lava_planet", [
        (1.00, M("metal_dark", "metal_dark", 0.5, 0.6), 2),
        (0.76, M("red", "red", 0.1, 0.34), 2),
        (0.48, M("orange", "orange", 0.1, 0.3, 1.2), 1),
    ])


def ice_planet():
    reset_scene()
    return _planet("ice_planet", [
        (1.00, M("ice", "ice", 0.1, 0.16), 2),
        (0.74, M("cyan", "cyan", 0.1, 0.22), 2),
        (0.44, M("white", "white", 0.0, 0.2, 0.8), 1),
    ])


def crystal_planet():
    reset_scene()
    c, p, w = (M("cyan", "cyan", 0.1, 0.2), M("purple", "purple", 0.1, 0.26),
               M("white", "white", 0, 0.18, 1.0))
    parts = [ico("crust", 0.86, 2, c), ico("core", 0.44, 1, w)]
    for i in range(6):
        a = 2 * math.pi * i / 6
        parts.append(gem("spike_%d" % i, 0.26, 0.36, 0.34, 0.40, 5, p,
                         (0.86 * math.cos(a), 0.86 * math.sin(a), 0.10),
                         (0, 70, math.degrees(a))))
    return _finish(parts, "crystal_planet")


def mechanical_planet():
    reset_scene()
    s, md, o, c = (M("metal", "metal", 0.85, 0.3), M("metal_dark", "metal_dark", 0.75, 0.44),
                   M("orange", "orange", 0.2, 0.36), M("cyan", "cyan", 0.1, 0.22, 1.0))
    parts = [
        ico("shell", 0.94, 2, s),
        ico("mantle", 0.66, 2, md),
        ico("core", 0.36, 1, c),
        torus("equator", 1.00, 0.10, 16, 5, o),
    ]
    return _finish(parts, "mechanical_planet")


def candy_planet():
    reset_scene()
    return _planet("candy_planet", [
        (1.00, M("pink", "pink", 0, 0.24), 2),
        (0.78, M("white", "white", 0, 0.3), 2),
        (0.56, M("lime", "lime", 0, 0.24), 1),
        (0.30, M("magenta", "magenta", 0, 0.24), 1),
    ])


def kanban_planet():
    reset_scene()
    md, o, y, p, c = (M("metal_dark", "metal_dark", 0.7, 0.46), M("orange", "orange", 0.2, 0.34),
                      M("yellow", "yellow", 0.1, 0.28), M("purple", "purple", 0.1, 0.26),
                      M("cyan", "cyan", 0.1, 0.22, 1.1))
    parts = [
        ico("crust", 0.96, 2, o),
        ico("mantle", 0.72, 2, p),
        ico("core", 0.42, 1, c),
        torus("ring", 1.24, 0.08, 18, 5, y, (0, 0, 0), (16, 0, 0)),
        torus("band", 1.02, 0.07, 16, 5, md, (0, 0, 0), (90, 0, 0)),
    ]
    return _finish(parts, "kanban_planet")


# ===========================================================================
# Batches
# ===========================================================================

def batch_crystals():
    crystal_cluster_small(); crystal_cluster_large(); layered_crystal(); crystal_orb()
    crystal_ring(); crystal_tower(); crystal_bridge(); crystal_core_machine()
    return LIB


def batch_jelly():
    jelly_cube(); jelly_tower(); jelly_ring(); jelly_capsule()
    layered_jelly(); jelly_bridge(); jelly_machine()
    return LIB


def batch_fruit():
    apple_structure(); watermelon_tower(); orange_stack(); pineapple_machine()
    dragonfruit_crystal(); fruit_ring(); layered_fruit_planet()
    return LIB


def batch_toys():
    toy_house(); toy_tower(); toy_bridge(); toy_factory()
    toy_castle(); block_city(); stacked_toy_buildings()
    return LIB


def batch_machines():
    gear_machine(); layered_engine(); turbine_stack(); reactor_machine()
    mechanical_orb(); rotating_cylinder_machine(); magnet_machine(); kanban_machine()
    return LIB


def batch_planets():
    layered_planet_basic(); lava_planet(); ice_planet(); crystal_planet()
    mechanical_planet(); candy_planet(); kanban_planet()
    return LIB
