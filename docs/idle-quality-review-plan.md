# R2 next operation: idle quality and continuous review

2026-10-11. Run is closed on fixture source `7638f22` and Actions `38081008300`.
Work alone, Godot 4.7.2, separate released Godot AI v4.2.1, public authenticated
MCP. Preserve approved walk/run coefficients, fixtures, media and feedback.

## Observed code and scope

- `idle_config` does not select a distinct Responsive/Grounded table. Its ordinary
  duration is one second; `character_setup` explicitly uses three seconds for
  idle. Measure the resulting timing before choosing a new implicit period.
- Existing idle includes breathing, a look-around, distributed torso twist,
  seeded periodic micro-motion and planted-foot IK. Keep useful controls and
  explicit caller inputs, including the documented `planted: false` opt-out.
- Idle uses the legacy arm path: world-down fallback, no coordinated incoming
  parent evaluation and no wrist/finger follow-through. Verify imported and Z-up
  rigs in actual playback before changing coefficients.
- `_solve_idle_leg` currently discards solve/clamp metadata. Establish whether
  normal output reaches its target and expose real reach problems; absence of
  metadata must not be counted as zero clamps.

This repairs the suite's ordinary idle output. It does not author a separate
performance scene or silently retune previously approved motions.

## A — preserve the ordinary baseline

Use a new UUID under `repair_idle_quality` and recovery's
`release_r2_idle_20261011`. Record source/core/engine, fixture hashes and inputs.
Generate five styles on bundled dummy, local X Bot, short and tall Z-up rigs:
20 ordinary baseline clips. Responsive omits style; all omit duration, speed,
sampling and recipe overrides. Request in-place output explicitly for this first
stationary baseline. Preserve reported versus observed root/pose behavior.

Through Godot AI: inspect, dry run, compare edited pose, write once, save, force
reopen, and verify resolved paths/types and unchanged persisted inspection. Save
partial receipts after every step. Do not repeat an ambiguous mutation. Baseline
failures are evidence to repair, not a reason to discard the source or report.

Capture representative continuous front/side baseline playback before tuning.
Baseline diagnostics do not constitute final approval. Check the bundled rig and
Z-up fixture early to expose timing and arm-axis problems.

## B — standing-motion playback contract

Use saved scenes and real AnimationPlayer/linked AnimationTree evaluation, with
one active mixer. Reuse independent native loading/frame helpers; no generator
IK, hand-applied poses or fixed world-Y ground measurements in the checker.

Unlike run, idle has no required toe-off, passing or flight windows. Default
planted idle has bilateral support throughout. Measure observed contacts against
rest ankle targets; distinguish authored support annotations from measurement.
Never call missing gait markers a failed standing phase or claim measured
contacts solely from a label.

- Both feet: slide <= min(2% leg length, 3 cm), ankle-plane penetration <= 1%
  of leg length, no knee flips/nonfinite output/default reach clamps.
- Actor/extracted root travel must remain zero within the established 0.1 mm
  tolerance for stationary output. Test both requested root policies, including
  retained bindings from other clips. Report what the active clip actually owns.
- Measure exact fractional repeat poses with independent played references and
  every crossed loop seam. Preserve position <= 0.1% leg length/rotation <=
  0.0001 rad repeat limits and existing discontinuity/velocity gates.
- Require genuine motion for ordinary defaults and truthful counts/timing. An
  explicit caller disabling all motion is an authored static clip, not a reason
  to force movement or fabricate a quality pass.
- Candidate matrix: five styles/four rigs/two requested root policies/three FPS
  (30/60/120)/two mixer routes = 240 runs. Check Player/Tree parity and zero
  unwanted root drift. Baseline starts with 60 in-place Player runs.
- Diagnostics retain the rest ankle-plane and hip-projection limitations; they
  do not prove skinned sole collision or center of mass stability.

Add a negative measurement case so numerical failures affect the exit status.
Keep timeouts and preserve failed attempts. No tolerance changes to approve a
candidate, no removal of baseline tracks to hide deterministic mixer resets.

## C — measured idle profiles and public prototypes

First prototype through supported public parameters. If new wrist/hand controls
are needed, expose only controls actually evaluated by idle, validate them, and
keep ordinary baseline output unchanged at that extension checkpoint. Do not
claim success for accepted inert controls or inject handler overrides privately.

Then choose distinct idle-specific Responsive and Grounded profiles from played
prototypes: quiet breathing, believable pelvis/torso weight shift, modest head
follow-through, relaxed elbows/wrists/fingers and stable foot plants. Review the
one-second legacy cadence against slower explicit prototypes and setup's
three-second input; decide the new implicit period from that evidence. Preserve
explicit duration/sampling and the existing key budget.

Use rig-up and measured arm/child geometry, carrying incoming torso/clavicle
transforms into forearm/wrist evaluation. Variation is bounded, seeded, periodic
and baked, with no live per-frame randomness. Keep idle's existing look/breath/
twist controls meaningful. Retune relaxed/heavy/sneaky with idle-only overlays,
without mutating shared style dictionaries or walking/running output.

Validate optional head, hand and finger anatomy before enabling features.
Implicit unavailable features are omitted with a reason; explicit impossible
requests return a typed error before mutation. Resolve measured arm geometry
before omission so missing fingers cannot reactivate the legacy world-down path.

Expose idle reach clamps/shortfall and discontinuities truthfully. Repair default
failures before candidate review; preserve intentional unsupported/non-planted
caller modes with accurate limitations rather than pretending they are planted.

## D — focused history, aliases and regression

Add missing idle-specific coverage: ordinary/default/Responsive aliases, distinct
Grounded, matched-input setup parity, deterministic seeds, explicit precedence,
optional anatomy/refusal, and Undo/Redo of the actual external public write.
Use a plain fixture marker to observe editor history; do not manufacture another
clip inside the witness. Every final clip passes dry/pose preservation, history,
save/reopen and track inspection through public Godot AI.

Check walk/run config isolation and their approved golden digests. Any shared
generation change also needs exact saved walk/run playback parity; changed
approved output requires renewed review. Run full suites only for phase gates
or concrete failures, not repeatedly after every small coefficient change.

Discover all ten families/eight promoted tools and verify final dry-call
inspection before/after core reload in a new ready session. Record engine and
core source SHAs; leave the user's older editor/core checkout untouched.

## E — deliver continuous videos and pause

Final output must use ordinary public calls. Record five clean/diagnostic pairs,
1080p60 H.264, preserved legacy left/new candidate right. At least six continuous
seconds front and six side per rig, with at least two full idle periods per
view; increase chapter duration if the chosen period requires it. Match camera
framing and label actual period, elapsed time, support and root policy. Do not
use running flight captions or moving camera travel claims for stationary idle.

Independently decode every complete MP4; verify exact frame count, chapters,
source/scene/video hashes and errors. Contact sheets supplement motion footage.
Archive source, parameters, scenes, local/private rigs, tooling and receipts;
keep media/X Bot local. Update FIX_ROADMAP, idle validation and review JSON,
commit/push and verify remote SHA. Open PC Explorer with Responsive clean
selected, then **stop for explicit five-style/four-rig idle feedback**.

Preserve `golden_idle.json` until review. After approval, add a separate versioned
idle fixture with exact provenance, explicit local recording and a fresh normal
comparison; require complete green Windows/Linux source CI, headless/editor/
registration/live MCP gates. Then advance to start/stop. No final publication
before remaining R2-R5 and final candidate approval.
