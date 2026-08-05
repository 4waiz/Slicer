"""Kanban Slicer - core asset build (vertical slice).

Builds the hero structure from the art bible plus the blade and target pads.
Run after ``kanban_lib.py`` has been exec'd in the same namespace.
"""

MANIFEST = []


def _log(entry):
    MANIFEST.append(entry)
    return entry


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

def core_materials():
    return {
        "orange":  mat("orange", "orange", 0.0, 0.38),
        "orange_d": mat("orange_deep", "orange_deep", 0.0, 0.44),
        "yellow":  mat("yellow", "yellow", 0.0, 0.30),
        "gold":    mat("gold", "gold", 0.25, 0.26),
        "purple":  mat("purple", "purple", 0.0, 0.28),
        "purple_d": mat("purple_deep", "purple_deep", 0.0, 0.34),
        "cyan":    mat("cyan", "cyan", 0.0, 0.24, emission=0.6),
        "green":   mat("green", "green", 0.0, 0.24, emission=0.6),
        "steel":   mat("steel", "steel", 0.55, 0.34),
        "steel_d": mat("steel_deep", "steel_deep", 0.6, 0.40),
        "silver":  mat("silver", "silver", 0.9, 0.14),
        "metal_d": mat("metal_dark", "metal_dark", 0.7, 0.46),
        "white":   mat("white", "white", 0.0, 0.18, emission=1.2),
    }


# ---------------------------------------------------------------------------
# Hero structure - the icon.png composition, re-arranged (not a copy)
# ---------------------------------------------------------------------------

def build_kanban_core_structure():
    """Multi-material hero: orange sphere, layered machine, yellow + purple gems."""
    reset_scene()
    M = core_materials()
    parts = []

    # Central layered machine barrel (orange rings + gold cap) - lies along X.
    parts.append(cyl("barrel_a", r=0.46, depth=0.34, verts=12, material=M["orange"],
                     loc=(-0.30, 0, 0.10), rot=(0, 90, 0)))
    parts.append(cyl("barrel_b", r=0.52, depth=0.30, verts=12, material=M["orange_d"],
                     loc=(0.02, 0, 0.10), rot=(0, 90, 0)))
    parts.append(cyl("barrel_c", r=0.58, depth=0.34, verts=12, material=M["gold"],
                     loc=(0.34, 0, 0.10), rot=(0, 90, 0)))
    parts.append(cyl("barrel_cap", r=0.40, depth=0.16, verts=12, material=M["yellow"],
                     loc=(0.58, 0, 0.10), rot=(0, 90, 0)))

    # Dark mechanical core cradle beneath the barrel.
    parts.append(slab("core_base", w=1.05, d=0.62, h=0.30, material=M["metal_d"],
                      loc=(0.05, 0, -0.42), bev=0.04))
    parts.append(cube("core_block", size=0.34, material=M["steel_d"], loc=(0.05, 0, -0.16)))

    # Orange faceted sphere, low-left.
    parts.append(ico("orange_orb", r=0.52, subdiv=1, material=M["orange"],
                     loc=(-0.86, 0.02, -0.30)))

    # Steel arm arcing round the left side.
    parts.append(cyl("arm_upper", r=0.10, depth=0.72, verts=6, material=M["steel"],
                     loc=(-1.02, 0, 0.34), rot=(0, 34, 0)))
    parts.append(cyl("arm_lower", r=0.10, depth=0.62, verts=6, material=M["steel"],
                     loc=(-1.16, 0, -0.22), rot=(0, -18, 0)))
    parts.append(cube("arm_joint", size=0.26, material=M["steel_d"], loc=(-1.14, 0, 0.06)))

    # Yellow hero gem, right - the signature crystal.
    parts.append(gem("yellow_gem", r=0.56, table=0.40, crown=0.34, pavilion=0.70,
                     sides=8, material=M["yellow"], loc=(1.06, 0, 0.20), rot=(0, 0, 22)))

    # Purple gem wedged under it.
    parts.append(gem("purple_gem", r=0.40, table=0.44, crown=0.22, pavilion=0.50,
                     sides=6, material=M["purple"], loc=(1.18, 0.04, -0.46), rot=(180, 0, 14)))

    obj = join(parts, "kanban_core_structure")
    finalize(obj, origin="BOUNDS")
    return _log(export_glb(obj, "kanban_core_structure.glb"))


# ---------------------------------------------------------------------------
# Blade
# ---------------------------------------------------------------------------

def build_blade():
    """Long silver cutting edge, dark centre spine, narrow sharp profile."""
    reset_scene()
    M = core_materials()
    parts = []
    # Edge: a very thin wedge (cone with 4 sides, squashed) reads as a blade.
    parts.append(cone("edge", r1=0.055, r2=0.004, depth=2.60, verts=4,
                      material=M["silver"], loc=(0, 0, 0.10), rot=(90, 0, 0),
                      scale=(1.0, 0.16, 1.0)))
    parts.append(cyl("spine", r=0.036, depth=2.20, verts=6, material=M["metal_d"],
                     loc=(0, 0.012, 0.10), rot=(90, 0, 0)))
    parts.append(cube("guard", size=0.16, material=M["steel_d"], loc=(0, 0, -1.24),
                      scale=(1.6, 0.5, 0.6)))
    parts.append(cyl("grip", r=0.062, depth=0.46, verts=8, material=M["metal_d"],
                     loc=(0, 0, -1.56), rot=(90, 0, 0)))
    obj = join(parts, "default_blade")
    finalize(obj, origin="BOUNDS")
    return _log(export_glb(obj, "default_blade.glb"))


def build_blade_trail():
    """Tapered ribbon swept behind the blade (rendered additively in-engine)."""
    reset_scene()
    M = core_materials()
    o = cone("blade_trail", r1=0.16, r2=0.005, depth=2.2, verts=4,
             material=M["white"], loc=(0, 0, 0), rot=(90, 0, 0), scale=(1.0, 0.10, 1.0))
    finalize(o, "blade_trail", origin="BOUNDS")
    return _log(export_glb(o, "blade_trail.glb"))


def build_blade_spark():
    """Tiny fragment used for spark / debris particle instancing."""
    reset_scene()
    M = core_materials()
    o = shard("blade_spark", r=0.09, h=0.26, sides=4, material=M["white"])
    finalize(o, "blade_spark", origin="BOUNDS")
    return _log(export_glb(o, "blade_spark.glb"))


def build_contact_flash():
    """Faceted burst placed at the blade contact point."""
    reset_scene()
    M = core_materials()
    parts = [ico("flash_core", r=0.26, subdiv=1, material=M["white"])]
    for i in range(6):
        import math as _m
        a = 2 * _m.pi * i / 6
        parts.append(cone("ray_%d" % i, r1=0.07, r2=0.0, depth=0.62, verts=4,
                          material=M["white"],
                          loc=(0.42 * _m.cos(a), 0.42 * _m.sin(a), 0),
                          rot=(0, 90, _m.degrees(a))))
    obj = join(parts, "blade_contact_flash")
    finalize(obj, origin="BOUNDS")
    return _log(export_glb(obj, "blade_contact_flash.glb"))


# ---------------------------------------------------------------------------
# Target pads
# ---------------------------------------------------------------------------

def build_target_pad(name, colour, icon):
    """Glowing technological landing pad with a geometric identity icon.

    ``icon`` in {diamond, square, circle, triangle}. The icon mesh is a
    separate material so the engine can pulse it independently.
    """
    reset_scene()
    glow = mat("pad_%s" % name, colour, 0.0, 0.22, emission=1.4)
    frame = mat("pad_frame_%s" % name, colour, 0.3, 0.30, emission=0.7)
    deck = mat("pad_deck", "teal_dark", 0.2, 0.55)
    parts = [slab("deck", w=1.9, d=1.9, h=0.10, material=deck, loc=(0, 0, 0), bev=0.03)]

    # Bright activated border: four bars framing the deck.
    for dx, dy, sx, sy in ((0, 0.92, 1.9, 0.12), (0, -0.92, 1.9, 0.12),
                           (0.92, 0, 0.12, 1.9), (-0.92, 0, 0.12, 1.9)):
        parts.append(slab("border_%s_%s" % (dx, dy), w=sx, d=sy, h=0.07,
                          material=frame, loc=(dx, dy, 0.06), bev=0.015))

    if icon == "diamond":
        parts.append(gem("icon", r=0.44, table=0.5, crown=0.12, pavilion=0.16, sides=4,
                         material=glow, loc=(0, 0, 0.10), rot=(0, 0, 45)))
    elif icon == "square":
        parts.append(slab("icon", w=0.72, d=0.72, h=0.09, material=glow, loc=(0, 0, 0.09), bev=0.02))
    elif icon == "circle":
        parts.append(cyl("icon", r=0.42, depth=0.09, verts=14, material=glow, loc=(0, 0, 0.09)))
    else:  # triangle
        parts.append(cyl("icon", r=0.48, depth=0.09, verts=3, material=glow, loc=(0, 0, 0.09)))

    obj = join(parts, "pad_%s" % name)
    finalize(obj, origin="BOUNDS")
    return _log(export_glb(obj, "pad_%s.glb" % name))


def build_all_core():
    build_kanban_core_structure()
    build_blade()
    build_blade_trail()
    build_blade_spark()
    build_contact_flash()
    build_target_pad("cyan", "cyan", "diamond")
    build_target_pad("green", "green", "square")
    build_target_pad("orange", "orange", "circle")
    build_target_pad("purple", "purple", "triangle")
    return MANIFEST
