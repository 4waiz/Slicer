# Testing Report

## Summary

| Check | Command | Result |
| --- | --- | --- |
| Formatting | `dart format lib test tool` | clean |
| Static analysis | `flutter analyze` | **No issues found** |
| Unit + integration tests | `flutter test` | **89 passed, 0 failed** |
| Debug APK | `flutter build apk --debug` | built |
| Release APK | `flutter build apk --release` | built, 47.0 MB |
| Release AAB | `flutter build appbundle --release` | built, 47.3 MB |
| On-device (release) | emulator API 36, 2400×1080 landscape | full loop verified, 60 FPS |

## Test suites

### `test/slicing_test.dart` — 15 tests

The heart of the game. Correctness is proved by **volume conservation**:
`MeshData.volume` is computed by the divergence theorem, which only returns the
right answer if the cut cap actually sealed each half. A missing or malformed
cap shows up immediately as a volume error.

Covered: signed distance and plane basis orthonormality; a plane that misses;
an exact mid cut (both halves 4.0 from a volume-8 cube, cut area exactly 4.0);
sides verified vertex-by-vertex; off-centre cuts; a 45° diagonal cut through
cube corners; interior `#cut` materials distinct from the surface; re-slicing a
piece without the material list growing; a 16×10 sphere with many straddling
triangles; a two-shell mesh producing exactly two cut loops; every cut-loop
point lying on the plane; collider welding; centroid recentring.

### `test/pipeline_test.dart` — 19 tests

**GLB loader against real Blender output.** The hero structure loads with all
8 material sections; colours come back saturated (proving the linear→sRGB
conversion), the mesh is a closed solid at sane scale, every shipped model
parses inside its triangle budget, a real asset survives a runtime slice with
volume conserved and one cut loop per shell, and pads carry emissive materials.

**Camera and swipe-to-plane.** Project/unproject round-trips to 0.5 px; points
reconstructed from anywhere along a swipe lie on the cut plane to 1e-6; a point
off the swipe line is off the plane; short swipes produce nothing; reversing
the swipe flips the plane normal exactly.

**Physics.** A dropped piece lands on the pad beneath it and settles; a piece
between pads rests on the floor; **the same drop twice matches to 1e-9**
(determinism, which retry and the Daily Slice depend on); magnets act only on
metal; pieces falling off the stage are removed; slicing rebuilds collider and
mass; a sliding piece is arrested by friction rather than carried off the
stage; low-friction ice slides measurably further than high-friction fruit.

### `test/render_test.dart` — 5 tests

Nodes in front of the camera submit triangles and behind it submit none;
back-face culling discards roughly half a closed mesh; the gameplay camera
framing keeps structure and both pads on screen; rendering to a real image
produces a meaningful number of lit pixels (this is what catches a renderer
that silently draws nothing); one node behind the eye does not cancel every
other node's shadow.

### `test/level_test.dart` — 18 tests

Campaign shape: exactly 60 levels, six worlds of ten, ids 1–60 with no gaps,
every level pointing at a model that exists on disk, difficulty rising across
worlds by cut budget and pad count, world 1 opening gently (one cut, two pads,
no fields, level 1 not rotating), and each world using its own material
identity.

Validator: **every shipped level passes**, plus negative tests proving the
validator catches an unreachable zone, more required zones than the cut budget
can create, overlapping pads, a material the model does not have, and
out-of-order star thresholds.

Procedural: the Daily Slice is identical for the same date and differs across
dates, the key formats correctly, **a full year of daily levels all validate**,
40 endless rounds all validate and grow harder, and generated levels never
exceed four pads or four cuts.

### `test/chain_test.dart` — 20 tests

Explosive cores: inert until armed; fires exactly once after its fuse and never
again; the blast shoves nearby pieces and spares those outside the radius; the
shove falls off with distance; heavy metal resists it more than light jelly; an
armed core keeps the attempt open so nothing is scored mid-explosion; and
cutting level 45 arms a real core, shows its warning ring, and detonates in
play.

Chain reactions: held props hang in place until a cut releases them and then
fall; held machinery spins while held; `spinMachine` adds spin to loose pieces;
`dropStructure` adds a body after a detonation; `autoSplit` produces more
pieces without spending one of the player's cuts; and restart re-holds the props
and clears queued events.

Cut purity: a cut on the material seam is measurably purer than one off it, a
lopsided cut contaminates a piece, and impurity costs accuracy.

Validator: the new prop and chain data is checked — a held prop nothing can
release, a detonation trigger with nothing explosive, and a `dropStructure`
naming a model that does not exist.

### `test/gameplay_test.dart` — 10 tests

End-to-end through the real `GameController`, headless.

- Level 1 loads, frames structure and both pads on screen, starts ready.
- **A swipe through the middle splits the structure and both halves land on
  their own pads, clearing the level.** This is the full loop: swipe → plane →
  slice → cap → collider → physics → zone match → score.
- A swipe that misses consumes no cut; a swipe too short is ignored.
- Cuts are limited to the level budget and a second attempt is refused.
- Restart returns to an identical starting state (no cuts, no result, one
  piece, three nodes).
- The same swipe twice produces the same accuracy and stars.
- Halves keep the parent volume to 3% and both carry real `#cut` faces.
- The two halves are assigned different required zones.
- **All 60 levels load and frame their stage on screen.**

## Bugs this suite caught

Every one of these was found by a test or by on-device instrumentation, not by
inspection:

1. **Spatial-hash collisions.** An integer hash mix for vertex welding silently
   fused two separate shells into one cut loop, and collapsed a box's eight
   corners to two collider points. Fixed by using exact record keys.
2. **Material list growth on re-slice.** Interior variants were appended again
   on every cut. Fixed by detecting and reusing existing `#cut` variants.
3. **Degenerate corner cuts.** A plane passing exactly through vertices — a
   swipe landing on a box corner — produced only one crossing per triangle, so
   no cut segment was recorded and the cap never closed. Fixed by recording
   on-plane vertices as cut points and adding on-plane edges of one-sided
   triangles, with duplicate edges deduplicated.
4. **Gauss-Seidel contact asymmetry.** Solving contacts one at a time let each
   corner of a flat landing react to a velocity the previous corner had already
   changed, injecting phantom spin and sideways drift so pieces never settled.
   Fixed by accumulating impulses Jacobi-style.
5. **Missing resting friction.** Once `vn ≈ 0` the normal impulse vanished, so
   the Coulomb bound derived from it collapsed and pieces slid across the stage
   forever. Fixed by including the weight the contact carries in the bound.
6. **`ui.Gradient.linear` with three colours and no stops.** dart:ui requires
   exactly two colours when stops are omitted; it threw on every frame right
   after the first rect, so the entire 3D scene silently never drew. Found by
   on-device instrumentation after the headless renderer tests passed.
7. **Orphaned parent node after a cut.** The uncut structure's render node was
   removed from the id map but not the render list, leaving it hanging in the
   air with nothing left to update its visibility.
8. **`drawShadows` aborting the pass.** A `return` where `continue` belonged
   meant one node behind the camera cost every other node its shadow.
9. **Material index overflow on a re-slice.** Cutting a piece through one of
   its own previous cut faces made an interior material dominant, and offsetting
   it again indexed past the end of the material list — a hard crash latent in
   every multi-cut level. Found by `autoSplit` cutting a second time.
10. **The blast read the wrong material profile.** A freed reactor core is a
   small insert in a large housing, so the piece's dominant material is the
   casing, which has no blast radius — cores armed and then did nothing. Blast
   parameters are now carried on the piece.
11. **Four level-data bugs** found by the validator: two levels with a pad no
   material could reach, and two with overlapping pads.

## Not covered

- No `integration_test/` driver test against a live device; the equivalent
  coverage is provided headlessly by `gameplay_test.dart`, which drives the
  real controller rather than a mock.
- Physical hardware has not been tested; verification was on an emulator.
- Audio playback and haptics are not asserted (both are wrapped so failure is
  silent by design).
