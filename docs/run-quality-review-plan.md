# R2 first operation: run quality and continuous review

2026-10-10. Follow the approved release wrap-up plan. Work alone on
`repair/toolkit-quality`, Godot 4.7.2, separate released Godot AI v4.2.1,
authenticated public MCP. R1's walk/style approval is scoped to the delivered
r005 files. Begin run generation changes only after R1's exact fixture candidate
passes required Windows/Linux source CI.

## Findings and scope

`MotionSpecs.run_config` has a run-specific stance, stride, lean and elbow bend,
but currently Responsive and Grounded resolve to that same legacy table. It does
not enable the reviewed rig-aware upper-body/hand path by default. The handler's
legacy arm-down fallback uses world-down; this needs particular attention on the
tall Z-up fixture. Walk's accepted coefficients must not be copied into run.

Existing protections include rig-relative cadence, foot clearance, requested
speed/duration preservation, reach refusal, deterministic output, contact
markers, typed anatomy errors and scene history. Preserve these. Repair the
procedural suite, not a standalone running demo or a kick performance.

The existing character checker checks exact loop boundaries only when a native
frame lands on them. Implicit run lengths need not divide six seconds; a new
run checker must cover actual crossed boundaries. Its exit status must include
every numeric failure, not just structural errors. Old walk receipts remain
immutable. This is a test/evidence change, not permission to alter walk output.

## A — preserve and measure ordinary run output

1. Use a new UUID scene directory and new recovery folder. Preserve exact source,
   official core commit, engine version, fixture/asset hashes and parameters.
2. Generate all five styles on dummy, local X Bot, short and tall Z-up rigs.
   Responsive baseline omits style, duration, sampling, speed and overrides;
   specify root extraction and linear looping only for the moving review.
   Preserve 20 rooted saved baseline scenes before tuning.
3. Through public MCP: inspect before/after dry run, write, save, force reopen and
   inspect paths/types/counts. Record failures immediately after each rig. Do not
   retry a mutation after an ambiguous transport response.
4. Check native 30/60/120 FPS playback and capture representative continuous
   front/side output to identify visible problems. Baselines are diagnostic;
   failing baselines remain preserved and do not block measurement of a fix.

## B — independent playback and contract evidence

Engine contracts: [AnimationTree playback ownership](https://docs.godotengine.org/en/4.7/classes/class_animationtree.html)
and [AnimationMixer extraction/deltas](https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html).
The linked player provides animations; the tree owns evaluation. Extracted
position is a delta to consume, rather than a looping accumulator difference.

Use saved clips and engine evaluation only; do not synthesize keys, apply bone
poses or import the generator's IK/axis helpers. Determine world axes from the
fixture's rest geometry. Preserve the ankle-plane/hip-projection limitations.

- Add strict markers, track paths/types/counts, finite poses and real motion
  checks. Require both feet's contacts and both flight windows over several loops.
  Compare declared contact with played ankle height; report observed contact and
  airborne timing separately from authored labels.
- At actual `1/fps` steps measure stance slide <= min(2% leg length, 3 cm),
  rest-ankle-plane penetration <= 1% leg length, zero knee flips and default reach
  clamps, and root travel error < 0.1 mm. Preserve the existing loop pose limits
  (position <= 0.1% leg length, rotation <= 0.0001 rad).
- Check exact repeat poses at matching fractional phases using a separate
  engine reference, plus samples before/after every crossed seam. Retain existing
  velocity/discontinuity gates; do not count a missing exact-boundary frame as
  loop coverage. Record cadence/period, sample counts and actual integration time.
- Exercise AnimationPlayer and a linked active AnimationTree. Tree playback
  disables the player's competing evaluation; one consumer applies extracted
  translation. Compare played bones/root output between both engine routes.
- Also generate in-place clips. With the actor held still, root travel must be
  zero; measure treadmill motion rather than falsely requiring world planting.
  A separate constant-velocity actor driver (one translation owner, no extraction)
  checks world contacts at the reported speed. Identify this gameplay driver in
  receipts and captions; do not attribute its movement to the clip.
- The candidate matrix is five styles x four rigs x two root modes x three FPS
  x two mixer routes = 240 native runs. Baseline diagnostics need the 60 rooted
  AnimationPlayer runs first; do not run unrelated old matrices repeatedly.
- Reuse completed history protections. Add only run-specific missing assertions:
  ordinary/explicit Responsive equivalence, distinct Grounded output, alias and
  setup reuse, optional anatomy/typed explicit refusal, explicit timing/speed,
  undo/redo and saved playback. Before/after core reload discover all ten families
  and compare dry-call inspection. Do not claim run history from a metadata check.

## C — tune the run table after measurement

Add separate run profiles to the shared resolver, retaining per-motion defaults
and precedence. Responsive/default keeps readable game timing; Grounded gives a
different restrained presentation. Retune relaxed/heavy/sneaky on Responsive
without changing the approved walk multiplier behavior.

Keep a bent running elbow, clear arm/leg counter-swing and flight rather than
walking elbow or stance coefficients. Use measured rig-up and child geometry,
coordinated parent transforms, distributed torso/pelvis motion, modest head
follow-through/stabilization, bounded wrist/forearm motion and relaxed fingers.
Variation stays periodic, seeded and baked into the clip. Validate optional roles
before adding features; explicit unsupported requests retain typed refusal.

Choose amplitudes from preserved baseline and candidate playback. Change reach,
pelvis or flight math only for an observed failing contract. Do not weaken slide,
penetration, reach, seam or interpolation tolerances to make output pass. Keep
explicit caller controls and root ownership intact. If a shared change affects
walk, require exact r005 playback parity; changed walk output needs a new review.

## D — review delivery and manual pause

Save/reopen every final candidate through Godot AI. Capture five pairs of clean/
diagnostic 1080p60 H.264 comparison MP4s from saved clips: baseline left, candidate
right, six continuous seconds front and six side for each of four rigs (48 s per
video). Show truthful speed/cadence/travel and separate contact/flight cues.
Each file must independently decode to 2,880 frames; retain render errors,
chapter metadata, hashes and supplemental contact sheets. Inspect representative
output before delivery. The footage reviews effects, not the screenshot quality.

Archive exact source, tooling, parameters, scenes, private rigs and test/media
receipts. Keep private media/X Bot local. Record failures, fixes, evidence and
remaining limitations in FIX_ROADMAP, a run validation note and review JSON.
Commit/push and verify remote SHA. Open PC Explorer with the Responsive clean
video selected, explain the new review set, and **stop for explicit feedback**.
The user approved walk, not run; silence, continue or a usage reset is not approval.

Do not overwrite `golden_run.json` or claim a green approved-default run before
this video review. An intended changed run fixture may remain an openly recorded
failure during candidate review. After approval, add a separate versioned run
fixture and require full Windows/Linux headless/editor/registration/live MCP CI.
Then advance to idle. No merge, tag or release before remaining R2-R5 gates and
final candidate approval.
