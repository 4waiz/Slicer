# Renderer & Slicing Architecture Decision

**Decision:** a purpose-built Dart 3D engine rendering through `dart:ui`
`Canvas.drawVertices`, with runtime mesh slicing, a custom impulse physics
solver, and Blender-authored GLB assets loaded by a hand-written glTF reader.

**Status:** implemented and verified (32 engine tests green, see
`docs/testing_report.md`).

---

## The constraint that drove the decision

The brief's non-negotiable feature is *real runtime mesh slicing*: an arbitrary
player-drawn plane must split a mesh, generate genuinely new interior surfaces,
regenerate colliders, and hand both halves to a rigid-body solver — and a piece
must be sliceable again. That requirement dominates everything else, because it
means the engine needs **CPU-side ownership of mesh data at runtime**.

That single constraint eliminates most of the field.

## Options evaluated

### 1. `flutter_scene` (Flutter team, Impeller-based)
Renders glTF with real PBR and would look great out of the box.

**Rejected.** It uploads geometry into GPU buffers at load time and exposes no
API to read back, mutate, or re-upload vertex data per frame. Slicing would
have to happen in a shadow copy of the mesh that the renderer knows nothing
about, and there is no physics layer at all. It also wants assets pre-baked
into its own `.model` container rather than runtime GLB. The one thing that
must work would be fighting the framework.

### 2. `three_js` / `three_dart` (Dart port of three.js)
Full scene graph, would technically allow mesh mutation.

**Rejected.** It pulls in native GL bindings via `flutter_angle`, which adds
platform surface area and release-build risk on Android for a game whose
required deliverables include a working release APK *and* AAB. The port also
lags upstream, and slicing plus physics would still be entirely my code — so
the dependency buys rendering convenience at the cost of build reliability.

### 3. Embedded Unity or Godot behind a platform view
The "obvious" answer for a 3D physics game.

**Rejected.** Neither engine is installed in this environment, both add a heavy
native toolchain and a large APK, and the Flutter↔engine bridge becomes the
riskiest part of the build. The brief explicitly asks for a *technical smoke
test first* rather than a blind choice — and a dependency this heavy cannot be
smoke-tested cheaply.

### 4. Custom Dart engine on `Canvas.drawVertices` — **chosen**

`drawVertices` takes raw `Float32List` positions and `Int32List` per-vertex
colours and rasterises them on the GPU in one batched call. Everything upstream
of that call is mine.

This is not a fallback; it is the best fit on the merits:

- **Slicing is guaranteed to work**, because the mesh is a plain Dart triangle
  soup that I clip, cap and re-emit. No framework can refuse.
- **The art direction matches the technique exactly.** The art bible is flat-
  shaded faceted low-poly. Flat shading needs one colour per face, which means
  unindexed vertices — precisely what `drawVertices` wants. A PBR renderer
  would be doing work the style throws away.
- **Zero native dependencies**, so debug/release APK and AAB builds cannot be
  broken by a third-party plugin.
- **Determinism is free**, which the seeded Daily Slice and instant retry both
  depend on.
- The assets are tiny (the hero structure is 356 triangles), so the software
  transform cost is negligible.

---

## Architecture as built

```
Blender (procedural Python)  ->  GLB  ->  GlbLoader  ->  MeshData (triangle soup)
                                                            |
                              swipe --> Camera3D.planeFromSwipe --> CutPlane
                                                            |
                                                       MeshSlicer
                                                       /         \
                                                  front           back
                                                       \         /
                                                     RigidPiece (collider
                                                     rebuilt from mesh)
                                                            |
                                                      PhysicsWorld
                                                            |
                                                     SceneRenderer -> drawVertices
```

### Mesh representation
`MeshData` is a triangle soup: 9 floats per triangle plus a material index per
face. Deliberately unindexed — flat shading needs unique vertices anyway, and
plane clipping on a soup is dramatically simpler and more robust than on an
indexed mesh with shared vertices.

### Swipe → cutting plane
The set of world points that project onto a screen line is exactly the plane
containing the eye and the two edge rays. So the cut plane is
`normalize(ray(start) × ray(end))` through the camera position — **exact, not an
approximation**. `pipeline_test.dart` asserts that points reconstructed from
anywhere along the swipe lie on the plane to within 1e-6.

### Slicing
Per triangle: classify the three vertices, pass through or clip into a front and
back polygon, and record the shared edge as a cut segment. Segments are welded
on a grid, chained into closed loops, flattened into the plane's 2D basis, and
ear-clipped into a cap that is emitted into both halves with opposite winding.

Cap faces get an auto-derived `#cut` interior material — brighter and more
saturated than the surface — which is what sells the slice visually.

Two degenerate cases are handled explicitly, both found by tests rather than
assumed:
- **A cut passing exactly through vertices** (a swipe landing on a box corner)
  produces only one crossing per triangle. On-plane vertices are recorded as cut
  points, and edges of one-sided triangles that rest on the plane are added to
  the outline, with duplicate edges deduplicated so the loop walk stays valid.
- **Vertex welding must use exact record keys.** An early mixed-integer spatial
  hash silently collided and fused two separate shells into a single cut loop.

Correctness is verified by volume conservation: `MeshData.volume` uses the
divergence theorem, which only yields the right answer if the cap actually
sealed the halves. Tests assert `front.volume + back.volume == original.volume`
for axis-aligned, off-centre, diagonal, sphere and multi-shell cuts, and on a
real Blender export.

### Physics
Fixed-substep (1/120 s) impulse solver. The collider is the mesh's own welded
vertex cloud, so it regenerates for free after every slice — cut-face corners
included. Contacts are gathered first and impulses accumulated **Jacobi-style**
and applied together; solving them sequentially let each corner of a flat
landing react to a velocity the previous corner had already changed, which
destroyed symmetry and injected phantom spin and sideways drift. Restitution is
suppressed below 1.2 m/s so pieces settle instead of buzzing.

No wall-clock or randomness enters the solver, so retry and the seeded Daily
Slice reproduce exactly — asserted by a test that runs the same drop twice and
compares to 1e-9.

### Rendering
World-space back-face cull, painter's-algorithm depth sort on triangle centroid
depth, flat shading (hemisphere ambient + directional key + Blinn-Phong
highlight + Fresnel rim), then one batched `drawVertices` for opaque faces and a
second additive, blurred pass for emissive faces to produce controlled bloom.

## Known trade-offs

- **Painter's algorithm, not a depth buffer.** Correct for the convex, well-
  separated low-poly shapes this game uses; long interpenetrating triangles
  could sort wrongly. Not observed with the shipped assets.
- **Sphere-approximated inertia** rather than a full inertia tensor. Chunky
  low-poly pieces tumble convincingly and the solver stays cheap and stable.
- **Piece-vs-piece collision is bounding-sphere only.** Enough to stop stacks
  interpenetrating without paying for convex-hull collision.
- **Cut caps do not bridge nested holes.** Concentric loops (slicing a ring in
  its own plane) fill rather than leaving the hole open. Disjoint loops — the
  common case, including every multi-shell asset — are handled correctly.
