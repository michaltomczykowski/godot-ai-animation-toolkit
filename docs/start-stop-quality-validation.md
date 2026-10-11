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

## Root hold and truthful reach checkpoint

Source `d3057b0` extends the extracted one-shot stationary tail to 67.667 ms.
The fresh public root regression passes all 48 controller/FPS/duration/replay
cases. Source `524415e` reports the actual transition solves and reference
timing without changing any authored pose value. Sixteen ordinary Responsive
public clips pass external history/dry/save/reopen. The checkpoint's 96 native
runs have complete reach metadata and pass root travel/hold; they still fail
character quality, as expected before pose repair. Five of sixteen clips report
real clamps, maximum shortfall 0.355 mm, including the X Bot on both operations.

All sixteen scenes preserve authored track paths/types, values, transitions and
action-key times exactly against baseline. Moving only the duplicate terminal
hold key produces a bounded played difference of 0.495 micrometres / 0.649
microradians on extracted clips; root differences are zero. In-place playback
is exactly unchanged. This explicitly measured rounding bound applies only to
the hold checkpoint; accepted looping walk/run/idle exact-parity gates remain.
The first verifier required exact held playback and failed; preserve its receipt
alongside the corrected authored-exact/played-bounded attempt. Neither is a
candidate character-quality approval.

Fresh public motion **68/68**, headless **14/14**, full local editor **393/393**
in 32 suites, zero skips/engine/discovery/route errors. Approved walk/run/idle
golden drift remains zero. Detailed receipts: `terminal-hold-green.json`,
`reach-report-motion-suite.json`, `editor-checkpoint-full.log` and
`reach-check-7090c7663d40477b866a42aa987eff07/summary.json` in recovery.
Next: [the measured continuation repair plan](start-stop-continuation-repair-plan.md).

## Independent full-body references

Animation source `999b615`, capture tooling/source `fd59394`: transition timing
is independent of the walk reference (ordinary 1 s / 60 Hz). Explicit
`gait_duration` / `gait_samples` can join a differently timed saved walk. Idle
references use the approved ordinary 3 s / 60 Hz style, with the same rig,
roles, arm placement and torso chain. Reference preparation adds no scene clip
or mixer. Complete local channels now include the accepted idle hips, arms,
wrists and fingers; stop no longer forces raw-rest leg rotations at its end.

The public regression plays 32 cases / 64 full-body endpoints with separate
saved walk/idle animations: both root policies, between-key phases 0.137/0.537,
0.35/1.4 s transfers and 1.0/0.7 s walk references with independent sample rates.
Fresh public motion **70/70**, zero skips or accepted walk/run/idle golden drift;
headless **14/14**. Sixteen ordinary public Responsive scenes pass external
history/dry/save/reopen, then **96 native runs / 192 endpoints** all match the
separately preserved approved reference scenes. Maximum error is 0.275
micrometres / 0.954 microradians, below unchanged endpoint limits.

All 96 runs still fail velocity continuation. In-place contact and some real
reach clamps remain; no quality approval or video delivery is implied. Detailed
receipts: `reference-motion-suite.json`, `reference-endpoints` and
`reference-native-90c49c66795747ea8cef4d2d8ce2b31c/summary.json`. The visible editor
quit through the public route after this capture. Next is checkpoint 2 in the
continuation plan: moving references, root speed and actual support transfer.

## Support prototype and audit controls

Prototype `bbeb75d` retains moving walk/idle reference windows, monotonic root
acceleration/deceleration, explicit two-step support and the exact external
in-place actor schedule. Generation FK samples real Animation interpolation;
the checker only plays saved scenes. Sixteen ordinary Responsive public writes
pass history/dry/save/reopen. Their 96 native runs retain exact reference
endpoints and root travel/hold, no default clamps or knee flips. Intended stance
slide is <=0.097 mm and ankle-plane height error <=0.542 mm. This prototype
still fails marker and audit checks and is not approved. Its immutable receipt
is `support-native-341ac296b867419684bb7cb431fdbdcb/summary.json`.

The test for a 1.4 s transfer into a 0.7 s faster walk exposes real reach
refusals. Ordinary four-rig dry requests are reachable; several explicit
long/fast requests exceed the bounded pelvis envelope. Supported reference
endpoint tests now use 0.35/0.9 s for the faster gait, retaining 0.35/1.4 s for
ordinary gait. A separate refusal test requires typed errors and unchanged
clips/scene/pose/history for the measured long/fast request and sub-0.2 s timing.

Two audit issues are measured before candidate promotion:

- Godot has one marker at a given timestamp. Simultaneous foot cues overwrite
  each other or `settled` if inserted independently. Merge simultaneous cue
  names and omit a terminal toe-off when support continues. Require reported
  marker count to match the saved resource. Reference: [4.7.2 Animation marker
  implementation](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/resources/animation.cpp).
- A curved reference has different incoming/outgoing finite steps naturally.
  Preserve raw boundary step change, and gate the transition step against the
  independently played reference step over that same interval. Keep the 5 mm
  and existing angular limits. The checker self-control passes **144/144**
  exact-reference cases and detects all 144 deliberately shifted endpoints,
  across four rigs, three phases/FPS and both continuation directions.

Declared stance uses the existing 2% leg/3 cm slide and 1% leg height limits;
all penetration, pole and finite checks remain. The observed 1% ankle-height
band is reported separately: it includes low swing and is not sole collision
or a stance classifier. Do not hide its measured motion or infer contact from
velocity. Candidate checks require complete declared support and negative
actor-drift controls before approval. Visual review remains mandatory.
