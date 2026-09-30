# Level Design

## Data model

Levels are pure data (`LevelDef` in `lib/game/levels/level_def.dart`) — no
level has any code of its own. A level declares:

| Field | Meaning |
| --- | --- |
| `model`, `modelScale` | which GLB structure to slice |
| `spawnX`, `spawnY` | where it hangs |
| `rotationSpeed`, `rotationAxis*` | how it turns before the cut |
| `allowedCuts` | cut budget (1–3 in the shipped campaign) |
| `zones` | the pads: id, colour, glyph, position, size, motion |
| `materials` | Blender material name → (material kind, required zone) |
| `minSuccess`, `twoStar`, `threeStar` | star thresholds |
| `bonus`, `bonusThreshold` | optional bonus objective |
| `gravity`, `fields` | physics environment: wind and magnets |
| `defaultKind`, `hint` | fallback material, optional coaching line |

The `materials` map is the design surface that matters: it decides which part
of a structure belongs in which pad, and therefore where the correct cut is.

## The validator

`LevelValidator` runs over all 60 levels (and a year of daily levels, and 40
endless rounds) as part of the test suite. It rejects:

- a model that is not on disk, or a material rule naming a material the model
  does not actually have
- fewer than two zones, duplicate zone ids, non-positive size, a pad at or
  below the floor, unknown glyph or colour, a moving pad with zero range
- **pads that overlap at any point in their travel** — travel widens only the
  axis it moves along, so a `slideZ` pad is not penalised on X
- pads that do not all use distinct glyphs (zones must never be distinguished
  by colour alone)
- a required zone no material maps to — an unwinnable level
- **more required zones than the cut budget can create**: N cuts produce at
  most N+1 pieces from one body
- star thresholds out of order, cut budgets outside 1–4, non-negative gravity,
  a degenerate rotation axis, a spawn too low to fall from
- bonus goals that cannot be achieved: `collectBonus` with no bonus material,
  `underCutBudget` on a one-cut level

Four real bugs were caught this way during development, listed in the
[testing report](testing_report.md).

## Landing geometry

Separation is split: 40% along the cut normal (physically what pushes the
halves apart) and 62% along the horizontal direction from the structure's
centre to the piece's centroid. The horizontal term is what makes a cut at
*any* angle send each half toward the side it came from, instead of dropping
both on the same spot.

A freshly separated half therefore travels roughly 1.3–3.2 units out before it
lands. Two-pad layouts span that whole band (pads at ±2.4, 2.9 wide, catching
0.95–3.85) so a clean cut cannot miss on a technicality. Three- and four-pad
layouts leave deliberate gaps between pads — that is where accuracy is lost,
and it is the intended source of difficulty.

## Difficulty curve

| Levels | Introduces |
| --- | --- |
| 1–5 | the swipe, two pads, one cut, a static then slowly rotating structure |
| 6–15 | angled cuts, a third pad, two-cut levels, bonus goals, first jelly |
| 16–30 | moving pads, four-pad sorting, layer stacks, wind, slippery ice, bonus pads |
| 31–45 | structural composition, suspension, tight budgets, magnets, exposed cores |
| 46–60 | combined mechanics, layered planets, narrow pads, wind + magnets together |

Averaged across each world, cut budget and pad count both rise from world 1 to
world 6 — asserted by a test. Rotation speed is the least-used lever on
purpose: it makes a level twitchier, not deeper.

## Worlds

**1 — Crystal Workshop** (1–10). Onboarding. Level 1 does not rotate at all.
Crystal only: clean cuts, low bounce, predictable. Ends on a machine with a
bonus purple core.

**2 — Jelly Laboratory** (11–20). Jelly wobbles, bounces and lands softly.
Introduces four-layer stacks, three-cut levels and pads that slide.

**3 — Fruit Foundry** (21–30). Weight differences between rind, pith and flesh.
Introduces ice sections that slide, a wind field, and a dedicated bonus pad.

**4 — Toy City** (31–40). Buildings and blocks — composition rather than
layers. Four-pad sorting, a one-cut precision level, tight budgets.

**5 — Mechanical Core** (41–50). Heavy metal falls fast and straight.
Magnets that act only on metal, exposed energy cores, moving targets,
crosswind, then two magnets pulling opposite ways.

**6 — Kanban Complex** (51–60). Layered planets whose cores are only reachable
with two cuts, every material kind, narrow pads, and a finale combining wind,
four pads, three cuts and a tilted rotation axis.

## Procedural levels

`generators.dart` builds a level from a seed. Given a seed it picks a material
family, a model from that family, a pad count that never exceeds the model's
material count, a pad layout whose travel is *derived from the spacing* so pads
can never overlap, a round-robin material→zone assignment so every pad is
reachable, and difficulty-scaled rotation, thresholds and fields.

- **Daily Slice** seeds from the UTC date, so everyone gets the same puzzle
  with no server and it works offline. Difficulty cycles over a week.
- **Endless** seeds from the round number, with difficulty climbing linearly.

Both feed the same validator as the handcrafted campaign, and a year of dailies
plus 40 endless rounds are validated in CI.
