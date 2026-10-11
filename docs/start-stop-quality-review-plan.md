# R2 start/stop quality and continuous review

Prepared 2026-10-11 while idle videos record. Work alone through Godot AI's
public custom-tools API, Godot 4.7.2 and the isolated released core. Begin
execution only after idle video approval, versioned-fixture comparison and
green source regression close idle. Preserve every accepted walk/run/idle
source, saved scene, fixture and media hash.

## Contract to establish

`walk_start` must move from a credible standing pose into the actual saved
ordinary walk at the requested phase. `walk_stop` must continue that saved walk,
plant and transfer weight while travelling forward, then recover into the
accepted idle. One-shots retain their endpoints and terminal hold; they are
not loop-closed. Root translation has one owner, and explicit caller timing,
style, phase, sampling and root policy remain supported or truthfully refused.

The completed motion/sequence history phase already covers all motion variants,
scene layouts and FPS. Retain that gate and its evidence; this phase adds
ordinary humanoid quality, direct external history witnesses and real gait/idle
continuation rather than repeating the complete historical matrix after each
coefficient change.

## Code questions to measure before choosing fixes

- `MotionSpecs.transition_keys` calls `gait_keys(ctx, false)` and samples its
  target at `phase * ctx.length`. The context length is the transition duration.
  Verify that target against the saved walk's implicit, rig-relative period,
  especially when explicit transition duration differs from walk duration.
- Transition legs call `solve_leg`, but the returned transition metadata has
  only phase. Verify whether public replies aggregate those real solve clamps;
  missing transition evaluation must not mean zero clamps.
- Target-foot height uses `foot_lift_scaled`, while intermediate step lift
  reads config `foot_lift`. Verify consistent rig scaling and explicit meter
  overrides on short and tall Z-up rigs.
- Resting arms use `_solve_arm_chain`, while accepted gait/idle hands have
  incoming-parent evaluation, elbow/wrist follow-through and relaxed fingers.
  Inspect the full played standing and gait endpoints before changing them.
- Stop forces terminal leg rotations to rest. Measure the final interval,
  pelvis recovery and blend into the accepted idle's reachable stance; a last
  key matching rest does not prove a continuous recovery.

These are audit targets, not proven visual failures. Capture the existing
ordinary output first and retain numerical/visual evidence before modifying it.

## A — public baseline and playback

Use a new UUID and `release_r2_start_stop_<date>` recovery folder. For each
operation generate all five styles/four rigs/two requested root policies:
80 ordinary clips. Responsive omits style; omit duration, phase, speed,
sampling, overrides and loop mode. Preserve engine/core/addon source, fixture
and saved-scene hashes plus actual reported timing, phase and root ownership.

Through Godot AI: inspect, dry run, compare authored pose, write once, save,
force reopen and inspect tracks/types/resolution. Store partial receipts after
each stage. Add a plain external history witness so each final write receives
actual Undo/Redo without generating another clip inside its witness.

Play saved clips through one active AnimationPlayer or linked AnimationTree:
80 clips * three FPS * two mixer routes = 480 native runs. Observe world-space
feet against rig-up/rest geometry, without production IK or hand-applied poses.
Keep slide <= min(2% leg length, 3 cm), penetration <= 1% leg length, no default
clamps, knee flips or nonfinite output, and established root/seam tolerances.
Record expected versus observed support, flight/lift, reach and discontinuities.
Do not require looping repeat poses or invent contact evidence from labels.

For in-place clips an unanimated gameplay parent may supply the documented
translation outside the visual mixer; record its inputs and check its ownership.
For extracted clips compare actual accumulated root travel, including terminal
hold and stop/replay. Detect backward stop travel and doubled extraction.

## B — played endpoint and continuation repair

Use accepted saved walk/idle as independent engine references. Check start's
gait end and stop's gait start at the requested fractional phase, aligning only
the documented actor placement. Compare all bones, pelvis/feet and root motion;
also sample neighbouring frames to expose velocity jumps and endpoint snaps.
The checker may not use the generator's private gait/transition sampler.

Measure between-key phases, both support sides and transition durations shorter
and longer than the saved gait period. Add targeted cases for failures found
there; preserve established thresholds and refused/dry nonmutation checks.

If required, separate gait reference timing from transition duration, aggregate
actual reach metadata, coordinate pelvis/support transfer, use measured arm
geometry and retain useful caller controls. Prefer transition-local changes.
Any shared generator change requires exact saved regression of accepted walk,
run and idle plus unchanged fixture hashes; changed accepted output needs review.

Compose idle -> start -> walk -> stop -> idle through `animation_sequence` using
saved clips/poses, explicit cropped phase boundaries, blends and contact
annotations. One character-owned player drives the result. Verify reported
duration/tracks/markers against saved playback, extraction and actual effect;
no competing players may write the same bones. Keep composition's already
verified native interpolation, history and restoration contracts intact.

## C — gates, delivery and pause

Run focused transition/sequence tests on a fresh editor, complete final public
history/native/continuation evidence, ten-family/eight-promoted-tool discovery
and before/after core reload. Full headless/editor and Windows/Linux source CI
are phase gates, with exact source/core receipts and narrow private-rig skips.

Capture five clean/diagnostic pairs per operation plus representative composed
continuation. Fixed matched front/side 1080p60 videos show anticipation, action
and recovery twice on every rig; repeat by resetting between complete takes,
never by loop-closing a one-shot. Include elapsed time, actual clip duration,
phase, root policy and honest contact diagnostics. Baseline/candidate framing
matches; continuous videos are required, with contact sheets supplementary.

Independently decode/count/hash every complete MP4. Archive source, parameters,
scenes, local rigs, tooling and all receipts. Commit/push, verify remote SHA,
open PC Explorer and **pause for explicit start/stop and continuation feedback**.
Do not advance to turn/strafe/jump or promote expectations based on numbers
alone. After approved regression closes this phase, plan the turn set next.
