# Game Design

## The loop

> Study → swipe once → slow-motion slice → structure separates → pieces fall →
> target zones fill → accuracy meter rises → reward or instant retry

An attempt lasts 20–60 seconds. The only control is a swipe.

## The core decision

Every level is one question: **where do I draw the line so each half is made
of the right material?**

Pieces are matched to pads by their *dominant material by surface area*, not
by where they land. So the player is not aiming a projectile — they are
deciding a composition. A cut two degrees off can leave a slice of purple
attached to the yellow half, and that half now contaminates the wrong pad.
Physics then carries each half outward toward the side it came from, so a
correct cut is a correct landing.

This is what keeps the game about spatial reasoning rather than reflexes, and
it is why difficulty scales through geometry, layering and cut budgets rather
than just spinning things faster.

## Controls

**Before the cut** the structure rotates slowly above the pads. The player can
watch it; the HUD shows the cut budget and each pad's identity glyph.

**The swipe** defines everything: entry point, exit point, angle and therefore
the cutting plane. A swipe shorter than 24 px is ignored. A swipe that misses
the geometry does not consume a cut — an important fairness rule, since a
mis-aimed swipe would otherwise be an instant loss.

Once a piece exists, the cut launches it on a ballistic arc onto the pad its
material requires, leading a moving pad to where it will actually be. The skill
being tested is *what ends up in each piece*, not throwing it, and pieces
scattering into the gaps between pads was noise rather than difficulty. Force
fields are deliberately not compensated for — wind and magnets perturb the arc,
which is what makes those levels levels.

**After the cut** time drops to 18% and eases back over 0.42 s while the blade
sweeps the cut line, then physics takes over.

No joysticks, no buttons, no camera control.

## Feedback

| Moment | Visual | Audio | Haptic |
| --- | --- | --- | --- |
| Swipe start | thin cyan guide, full-screen plane preview | `swipe_start` | selection click |
| Blade contact | white cut outline, sparks along the loop, cyan flash | material-specific cut sound + `separation` | medium impact |
| Correct landing | pad-coloured burst, meter rises | `land_correct` | light impact |
| Wrong landing | red burst and flash | `land_wrong` | vibrate |
| Perfect cut | white flash, confetti | `perfect_cut` | heavy impact |

The cut sound is chosen by the material of the piece being cut, so crystal
pings, jelly squelches, metal clangs and ice crackles.

## Materials

Seven kinds, each with genuinely different physics rather than just a palette:

| Kind | Restitution | Friction | Density | Character |
| --- | ---: | ---: | ---: | --- |
| Crystal | 0.16 | 0.62 | 1.5 | clean rigid cut, sharp shards |
| Jelly | 0.52 | 0.48 | 0.75 | wobbles, bounces, soft landing |
| Fruit | 0.22 | 0.74 | 0.95 | grips hard, splashy cut |
| Plastic toy | 0.34 | 0.55 | 1.0 | stable, moderate bounce |
| Metal | 0.12 | 0.50 | 2.6 | heavy, falls hard, sparks |
| Ice | 0.20 | **0.07** | 1.1 | slides — must land dead centre |
| Explosive core | 0.30 | 0.45 | 1.2 | telegraphed, shoves neighbours |

Ice and metal are the two that most change how a level plays: ice slides off
pads it lands on the edge of, and metal is the only kind magnets act on.

## Explosive cores

A section made of `explosiveCore` arms the instant a cut frees it — and it arms
if the piece contains *any* core material, not just if the core is the piece's
dominant material, since a reactor core is a small insert inside a large
housing.

While armed it telegraphs loudly: the piece pulses hotter, brighter and faster
as the fuse runs down, and a ring is drawn at its true blast radius with a
second ring closing in on it. Both are rebuilt every frame from the live fuse,
so what the player sees is exactly the real timing.

After 1.15 s it goes off. Everything inside 3.4 units is shoved away with a
quadratic falloff, biased upward so the shove reads as a pop rather than a
shunt along the floor. The impulse is applied through inverse mass, so a dense
metal slab barely moves while a light jelly wedge is thrown clear — the blast
is a tool for repositioning pieces, not an instant kill. Scoring waits for
every armed core, so an attempt is never graded mid-explosion.

## Chain reactions

A cut can set off a consequence. Levels declare `props` — extra bodies held
above the stage, optionally spinning so machinery reads as running — and
`chain` events that fire on the first cut, on any cut, or on a detonation,
after a short delay so the player can read the first cut landing first.

| Action | What happens |
| --- | --- |
| `collapseSupports` | Every held prop is released and topples |
| `dropStructure` | A fresh structure falls into the scene |
| `spinMachine` | Everything loose is kicked tangentially outward |
| `autoSplit` | The largest remaining piece is cut again along a fixed plane |

The player's blade passes straight through held props: slicing a support would
bypass the chain reaction it exists to cause.

In the shipped campaign: level 47 drops a spinning gear onto the stage when the
drum is cut, 49's gearbox kicks over as it is cut, 45's reactor core detonates
in play, 50's detonation drops a second machine, and 53's molten core blows the
crust apart a second time.

## Target zones

Two to four pads per level. A zone is **never identified by colour alone** —
every pad also carries a geometric glyph (diamond, square, circle, triangle),
and the level validator rejects any level whose pads do not all use distinct
shapes.

Zones track correct mass, wrong mass and required mass. Contaminating a pad
costs half the offending mass off the final accuracy, so flooding every pad is
not a winning strategy.

## Scoring

```
accuracy = (correct mass − 0.5 × contaminating mass) / required mass
```

A piece is not simply "right" or "wrong". Each carries a **purity** — the
fraction of it, by surface area, that genuinely belongs to the pad it is headed
for. A clean cut yields 1.0; a cut that leaves a wedge of the neighbouring
section attached delivers that wedge into a pad it does not belong in, and the
remainder is scored as contamination. This is what makes cutting *accurately*
matter rather than just cutting somewhere.

Purity is only applied where the geometry allows a pure cut — see
[known limitations](known_limitations.md).

| Stars | Condition |
| --- | --- |
| 1 | accuracy ≥ level minimum (0.52–0.66 depending on level) |
| 2 | accuracy ≥ two-star threshold (0.74–0.86) |
| 3 | accuracy ≥ three-star threshold (0.88–0.96) **and** the bonus goal, if the level sets one |

Coins reward accuracy, star count, unused cuts, the bonus goal and a perfect
result, scaled slightly by world.

Bonus goals: all zones perfect, finish under the cut budget, collect the bonus
piece, or keep wasted mass under a threshold.

## Progression

Six worlds of ten. Stars only ever increase; clearing a level unlocks the next.

- **1 Crystal Workshop** — the swipe, two pads, reading a rotating shape.
- **2 Jelly Laboratory** — wobble, bounce, layer stacks, moving pads.
- **3 Fruit Foundry** — weight differences, slippery sections, wind, bonus pads.
- **4 Toy City** — structural composition, four-pad sorting, tight cut budgets.
- **5 Mechanical Core** — heavy metal, magnets, exposed cores, moving targets.
- **6 Kanban Complex** — layered planets and everything combined.

Difficulty rises through pad count, cut budget, layer count and force fields —
rotation speed is the smallest lever, deliberately.

## Modes beyond the campaign

**Daily Slice** — one deterministic puzzle per UTC day, seeded from the date,
so it needs no server and works offline. Streak tracked; best percentage kept.

**Endless Slicing Lab** — procedurally generated rounds of rising difficulty,
score multiplier up to ×9, one failed round ends the run, high score persisted.

**Missions** — ten long-running goals (perfect cuts, materials sliced, pieces
landed, one-cut wins, accuracy) with coin rewards, claimable once each.

**Blade shop** — ten cosmetic skins sharing one mesh; they change tint, trail
and cut-flash colour and can never affect physics or scoring.

## Interface

Dark teal environment, angular cut-corner panels, cyan guidance, green
success, orange/yellow warmth, purple for advanced mechanics, red for failure,
white for the blade and a perfect cut. No Material widgets are used anywhere —
the entire UI is built from the game's own design system on `WidgetsApp`.

The gameplay HUD carries only what is needed mid-swipe: level, cut pips,
accuracy meter, pause, and the pad identity chips.
