# R2 start/stop: execution evidence

## Baseline tooling (2026-10-11)

Idle is closed on fixture source `b935cff`, Actions `38157142049`. The user
authorized this next phase with “then do it.” Follow
[the phase plan](start-stop-quality-review-plan.md); work alone on Godot 4.7.2
through the separate released core and public custom-tools API.

The existing capture client now accepts `walk_start` and `walk_stop`. Every
transition baseline and candidate uses a plain scene marker and an external
history witness. That witness undoes/redoes the single public write already
made, without creating another clip. It compares the restored animation digest,
root extraction binding, marker names and times, and the ordinary one-shot mode.
Normal editor-suite runs exercise the same witness with an ordinary dummy fixture.

Capture receipts now also compare the authored pose immediately after dry run.
Timing, phase, speed, sampling, recipe and loop overrides remain absent from
ordinary calls. This checkpoint changes tooling/tests only; accepted motion
generators and golden fixtures are preserved. Baseline playback and continuation
measurements are pending, and no start/stop visual approval exists.

Recovery: `release_r2_start_stop_20261011` beneath the existing PC snapshot root.
Never overwrite a completed route, source archive or review receipt. Preserve
partial attempts after interruption; new generation attempts use new UUIDs.

## Preserved ordinary baseline

Generation source `96db7c4`: **80/80** actual public custom-tool writes across
start/stop, five styles, four rigs and both requested root policies. Each passes
dry clip/pose nonmutation, actual external Undo/Redo and forced save/reopen.
Fresh public motion suite: **66/66**, no skips; accepted walk/run/idle golden
drift zero. All eleven protected JSON fixture hashes are unchanged.

Checker `1f5d5eb`: **480** complete native Player/Tree runs at 30/60/120 FPS,
zero engine errors; **0/480** meet the new quality gate. Independent references
are forty approved saved walks and forty approved idle scenes. Gait endpoint
differences reach 0.935 mm / 0.00489 rad; idle endpoint differences reach
105.16 mm / 0.36892 rad. Every run has a played join velocity discontinuity.
Observed ankle-band slide reaches 197.23 mm, with 120 left and 120 right contact
failures. In-place translation currently uses the paired extracted saved track
as an explicitly recorded diagnostic assumption, not an accepted caller contract.
All eighty replies lack transition clamp metadata; it is unknown, not zero.

Twenty extracted runs fail terminal root travel; maximum error 0.576 mm.
The ordinary commit path already appends a 34.333 ms stationary tail. Godot
4.7.2's AnimationTree finishing step can evaluate a root interval longer than
one frame when crossing the end; a tail sized for AnimationPlayer alone is
insufficient. A separate public regression reproduces this at ordinary and
fractional durations, both controllers, all three frame rates and replay.
See [the 4.7.2 node implementation](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/animation/animation_blend_tree.cpp)
and [the extraction contract](https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html).

Two Responsive baseline MP4s contain **24 seconds / 1,440 decoded frames** each,
1080p60, both camera views and two complete reset-separated takes on every rig.
Canonical generation/checker source ZIPs and 160 saved scenes plus local rigs
are CRC checked. Exact hashes and failure counts are in `baseline-summary.json`.
The first checker attempt used the storage end after the extraction tail for
joins; it is retained but superseded by the action-boundary measurement.

## Next repair checkpoints

1. Increase the shared extracted one-shot hold enough for both engine routes;
   prove the failing extraction test becomes green at all tested durations/FPS.
   Keep action boundaries separate from storage length and update the reported
   tail documentation. Looping accepted walk/run/idle are outside this change.
2. Aggregate actual transition leg solves and gait-reference reach metadata;
   expose measured clamps, shortfall and evaluation counts before pose tuning.
3. Build transition references at independently specified gait timing, copy the
   accepted idle posture, and repair contact/velocity continuation from the
   saved playback measurements. Preserve accepted generators and fixtures.
4. Complete the targeted phase/duration diagnostics, final public/native matrix,
   one-player composition, regressions and continuous human review in the plan.

No start/stop output is approved, and release remains pending. An initial syntax
failure while adding the extraction regression is preserved separately from the
subsequent native failing test; it is not used as fault evidence.
