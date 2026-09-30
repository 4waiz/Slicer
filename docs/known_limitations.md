# Known Limitations

An honest list of what is not finished, not verified, or deliberately traded
away. Nothing here is hidden behind a passing test.

## Verification gaps

- **No physical Android device was used.** Everything was verified on an
  emulator (API 36, x86_64, 2400×1080 landscape), including the release APK.
  An emulator is not a reliable proxy for low-end GPU behaviour, thermal
  throttling or real touch latency. Testing on hardware is the single most
  important outstanding item.
- **No `integration_test/` driver test.** The equivalent coverage is provided
  headlessly by `test/gameplay_test.dart`, which drives the real
  `GameController` through complete cuts rather than a mock — but it does not
  exercise the widget tree, gesture recogniser or platform channels.
- **Audio and haptics are not asserted by tests.** Both are wrapped so that
  failure is silent by design, which also means a regression that silences them
  would not fail the suite. Audio was confirmed to initialise on device.
- **Only levels 1 and the campaign-wide load/framing path are exercised
  end-to-end.** All 60 levels are validated statically and confirmed to load
  and frame correctly, but only level 1 has an automated full-cut playthrough.

## Renderer trade-offs

- **Painter's algorithm, not a depth buffer.** Triangles are sorted by centroid
  depth. This is correct for the convex, well-separated low-poly shapes the
  game uses, but long interpenetrating triangles could sort wrongly. Not
  observed with the shipped assets.
- **No shadow mapping.** Contact shadows are soft blobs projected onto the
  stage plane, fading with height. They anchor falling pieces convincingly but
  are not real shadows and do not respond to shape.
- **Bloom is a blurred additive re-draw** of emissive faces, not a threshold
  and downsample chain. Cheap and controlled, but it cannot bloom bright
  non-emissive highlights.

## Slicing limitations

- **Purity scoring is opt-in per level.** A piece is scored on how cleanly it
  was separated only where `enforcePurity` is set — that is, where the
  structure's sections are genuinely separable by a plane (side by side, or
  stacked). Concentric structures (orbs, planets, the reactor) cannot be split
  into pure pieces by *any* cut, so scoring them that way would make them
  unwinnable; those levels are about revealing the core instead. Deciding
  separability is a hand judgement per level, not something the validator can
  currently check.
- **Cut caps do not bridge nested holes.** Concentric cut loops — slicing a
  ring or torus in its own plane — are filled rather than left open. Disjoint
  loops, which is the common case and includes every multi-shell asset, are
  handled correctly and each shell caps independently.
- **Fully coplanar triangles are skipped** when building the cut outline. A
  plane exactly containing a face is a tangent grazing cut, which resolves to
  "no cut" rather than producing a degenerate sliver.
- **A cut always produces exactly two pieces per body.** Concave geometry that
  a plane would genuinely separate into three or more disconnected islands
  yields two meshes, one of which may contain disconnected shells. They fall
  together as one rigid body.

## Physics simplifications

- **Sphere-approximated inertia** rather than a real inertia tensor. Chunky
  low-poly pieces tumble convincingly and the solver stays cheap and stable,
  but a long thin piece rotates less realistically than it should.
- **Piece-vs-piece collision is bounding-sphere only.** Enough to stop stacks
  interpenetrating; two pieces resting against each other will not interlock
  the way their real shapes would.
- **Contact damping is an arcade cheat.** Friction acting at contact points
  produces a real tipping torque that leaves a Jacobi solver teetering
  indefinitely, so angular velocity is bled off while in contact. It settles
  crisply and feels right, but it is not physically exact.
- **A 6.5-second settle cap** scores the attempt even if a piece is still
  rocking on a pad edge. Necessary so the player is never left waiting, but it
  means an unlucky balanced piece can be scored mid-motion.

## Content and feature gaps

- **Suspended structures** are visual rather than simulated — there are no rope
  or joint constraints, so "suspension" levels rely on shape and balance. Held
  props (see chain reactions) are pinned rather than hung from anything.
- **Chain reactions fire from a fixed schedule, not from contact.** A cut
  queues its consequence after a delay; a falling piece physically knocking a
  support loose is not simulated.
- **`autoSplit` cuts along a plane fixed in the level data**, through whichever
  piece is currently largest. It is a scripted second cut, not a simulated
  fracture.
- **Precision slots** are approximated by narrow pads rather than by geometry
  a piece must physically pass through.
- **Jelly wobble is a render-time scale pulse**, not a deformation. Soft-body
  simulation was deliberately avoided for Android performance, as the brief
  allows.
- **Graphics quality settings are wired but inert.** Low/medium/high, reduced
  motion and camera shake are persisted and available to the renderer, but the
  frame budget never came under pressure on the hardware tested, so no quality
  reduction path was implemented.
- **No music.** Nineteen original sound effects ship; there is no background
  music track, though the music toggle exists and is persisted.
- **Weekly challenges and leaderboards** are architecturally supported by the
  seeded generator but have no UI or backend.

## Build and release

- **The release build is signed with the debug key.** It installs and runs, but
  Play will reject it. See [play_store_release.md](play_store_release.md) for
  the keystore setup.
- **APK is 47 MB** because it is universal. Almost all of that is the Flutter
  engine for three ABIs; game content is under 5 MB. The AAB splits per device
  on Play, and `--split-per-abi` does the same for direct distribution.
- **No custom font ships.** Typography relies on the platform sans with heavy
  weight and wide tracking, which reads correctly on Android but will differ
  slightly on other platforms.
- **The package name is a placeholder** (`ae.kanbanstudios.kanban_slicer`) and
  must be confirmed before first publish.

## Tooling notes

- **The Gemini CLI in this environment has no image-generation tool.** Its
  available tools are file, shell and web only (verified by asking it to
  enumerate them). The game's 2D art is therefore rendered from the shipped
  GLB assets by `art/blender/render_art.py` instead — which has the advantage
  that menu art and gameplay can never drift apart.
