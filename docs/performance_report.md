# Performance Report

## Measured

Android emulator, API 36, x86_64, 2400×1080 landscape (914×411 logical, DPR
2.63), Impeller/OpenGLES backend. Figures read from the in-game debug HUD,
which reports smoothed frame rate and the exact triangle count submitted per
frame.

| Scene | Triangles submitted | Frame rate |
| --- | ---: | --- |
| Level 1, structure intact | 418 | 60 FPS |
| Level 1, mid-slice (2 pieces + FX) | 503 | 60 FPS |
| Level 1, pieces falling | 536 | 60 FPS |
| Home screen (rotating hero preview) | ~180 | 60 FPS |

The release build holds 60 FPS through the entire loop including the
slow-motion slice, the particle burst and the results overlay.

## Why it is cheap

The whole shipped model library is 11,324 triangles across 53 assets, and a
level only ever has one structure and two to four pads on stage. After
back-face culling roughly half of each closed mesh is discarded, so a typical
frame submits 400–600 triangles in **one batched `drawVertices` call**, plus a
second small additive call for emissive faces.

Faceted low-poly is both the art direction and the cheapest thing for a
flat-shaded software-transform renderer. The two requirements happened to
agree, which is the main reason the performance budget was never under
pressure.

## Budgets and headroom

| Budget | Target | Actual |
| --- | --- | --- |
| Frame rate | 60 FPS, 30 FPS fallback | 60 FPS sustained |
| Renderer cap | 24,000 triangles | ~500 typical, 40× headroom |
| Model library | — | 804 KB, 53 files |
| Audio bank | — | 250 KB, 19 WAVs |
| Rendered 2D art | — | 3.6 MB, 7 PNGs |
| Level load | fast | assets are cached; a level rebuild is a parse-free re-instantiation |
| Retry | under 2 s | immediate — `restart()` reuses cached meshes |

## What the engine does per frame

1. **Transform + shade** every triangle on the CPU: object→world, face normal,
   world-space back-face cull against the eye, hemisphere ambient + directional
   key + Blinn-Phong highlight + Fresnel rim, packed to ARGB.
2. **Depth sort** surviving triangles by camera-space centroid depth
   (painter's algorithm).
3. **Two draw calls**: opaque `drawVertices`, then a blurred additive pass for
   emissive faces.

Costs are linear in triangle count, and buffers are preallocated and reused
across frames.

## Physics cost

Fixed 1/120 s substep, capped at 12 substeps per frame so a stalled frame can
never spiral into a hundred catch-up steps. A level runs 1–5 rigid bodies.
Contacts use the mesh's welded vertex cloud (8–40 points per piece) against pad
tops and the floor; piece-vs-piece is bounding-sphere only.

Pieces sleep after 0.32 s below the velocity thresholds and are then skipped
entirely. A hard 6.5-second cap resolves the attempt even if a piece is
balanced on a pad edge and still rocking, so the player is never left waiting.

## Memory

`ModelCache` parses each GLB once and shares the immutable `MeshData` across
every instance — the slicer always produces new meshes rather than mutating,
so sharing is safe. `trim()` drops everything outside a keep-set when leaving a
world. Sliced pieces are the only per-attempt allocation and are released on
restart.

Particles are screen-space streaks, not rigid bodies: a burst of 60 sparks
costs a few hundred lines, not 60 simulated objects.

## Build sizes

| Artifact | Size |
| --- | --- |
| Release APK (universal) | 47.0 MB |
| Release AAB | 47.3 MB |

Almost all of this is the Flutter engine compiled for three ABIs. Game content
is under 5 MB. The AAB is what ships to Play, and Play generates per-device
splits from it, so the actual download will be roughly a third of the universal
APK. `flutter build apk --split-per-abi` produces the same effect for direct
distribution.

## Settings that affect performance

The settings screen exposes graphics quality (low/medium/high), reduced motion
and camera shake. These are persisted and available to the renderer; on the
hardware tested there was no need to reduce quality, so they are wired but
their effect is not yet measurable — noted in
[known limitations](known_limitations.md).

## Not measured

- Physical Android hardware (verification was on an emulator, which is not a
  reliable proxy for low-end GPU or thermal behaviour).
- Sustained sessions long enough to expose thermal throttling.
- Memory over a long multi-world session — `trim()` exists but has not been
  profiled against a leak detector.
