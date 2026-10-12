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

## Support candidate checkpoint (2026-10-11)

Animation source `4137cc5`: all **80 ordinary public clips** pass dry run, actual
external Undo/Redo, pose preservation, save and forced reopen. All **480 native
checks** pass (two operations, five styles, four rigs, two root policies, three
FPS and Player/Tree). Default solves report zero reach clamps; root travel,
strict complete reference endpoints/continuation, intended support, penetration,
poles and one active mixer pass. Public motion **71/71**, headless **14/14**;
accepted walk/run/idle golden drift remains zero. Two root policies' audit
controls pass 288 reference continuations and detect 288 shifted endpoints.
All 48 deliberate external-actor drift cases fail the intended support limit.

Receipt: `candidate-r001/native-344517a33c844f88bfb8060314323180/matrix.json`.
The previous prototype failures are preserved. No human start/stop approval.
Next: targeted phase/duration, saved public composition, reload/full regression,
Windows/Linux source CI, continuous comparisons/archive and manual feedback.

Earlier CI `38168034564` completed its editor cases (393/395 with only the two
private-X-Bot skips) but failed stale generated operation descriptions. Its
Linux live route timed out in the unrelated graph-history subprocess after
120 seconds. Fresh local graph history passes 8/8 and all 28 saved playback
cases; regenerate the audit and inspect the next source CI before closure.


## Timing and composition follow-up

The first timing attempt preserves 16 public clips /96 native passes for a
0.35 s transfer at phase 0.137. A 1.4 s transfer at the same phase exposes a
typed reach refusal on the short rig; the old capture harness incorrectly
attempted history on a nonexistent refused output. Preserve `timing-r001`;
the revised harness records supported clips and typed, nonmutating refusals
separately, rather than claiming every explicit timing is reachable.

Independent native composition control reproduces three simultaneous cues
becoming one overwritten cue (`sequence-cues-red.json`). The sequence repair
groups simultaneous cue names with `+` after assigning repeated-name suffixes,
so source cues and contact annotations survive native storage. The green
control preserves all three. Public composition/history and fresh native
playback are pending; this is not quality approval. Continuous review source
clips remain exactly `4137cc5`.

The first 2,880-frame recording completed with no engine errors, but Windows
PowerShell exposed a null process exit code after waiting. That failure receipt
is retained as `recording-first-null-exit.json`. The recorder now caches the
process handle and only recovers an existing capture after validating its
complete native report, all frames, source scenes, and encoded/decoded MP4.

Current in-place audit consumes the numeric actor schedule on the identity
fixture actor parents; rest-axis variants are included. Arbitrary rotated or
scaled actor wrappers need the explicit actor-node/local-to-world contract and
additional R3 coverage. Do not claim that broader transform coverage here.

### Timing checkpoint and pending delivery

Source `bb7395c` passes all 96 explicit four-rig timing requests: 91 saved
clips /546 native Player/Tree/FPS checks pass; five unsupported long/fast
requests return matching typed reach errors on dry/write and preserve clip,
pose and extraction binding. Both between-key phases 0.137/0.537, 0.35/1.4 s
ordinary-reference transfers and 0.9 s transfers with separately saved 0.7 s
/40 Hz walks are covered. Receipt: `timing-r002/timing-matrix.json`.
Public motion was 71/71; current headless remains 14/14, zero accepted golden
drift. Sequence cues' red/green native controls and the revised timing harness
are committed. Active visible editor PID 1756 is source `bb7395c`.

Continuous transition recorder is running in `candidate-r001`; inspect
`recording-progress.json` and its actual PID before resuming. Do not duplicate
active recordings or overwrite historical attempts. Animation source is exactly
`4137cc5`; composition has a separate cue repair. Next: public four-rig
composition/history, 24 saved sequence runs, 160 reload dry calls, fresh full
local/source CI, then all 22 movies/archive/Explorer and explicit human pause.
No start/stop approval, merge, tag or release.

### Automated start/stop gates complete; recording remains active

Motion source `4137cc5`, sequence/tooling checkpoint `80cfb59`: fresh public
motion 71/71 and sequence 3/3 pass. Full local Godot 4.7.2 editor **397/397**
in 32 suites, zero skips/engine/discovery/tool-route errors; both 10-family
/103-operation probes pass. Headless **14/14**. All 11 historical/accepted
fixture hashes are unchanged; walk/run/idle golden drift is zero.
The full blocking suite delayed the released core's WebSocket heartbeat during
shutdown; the transport timeout/reprobe is preserved in the raw log. External
public routes and both registration probes passed. No test error is suppressed.

Four public saved idle/start/two-walks/stop/idle sequences pass actual external
Undo/Redo, dry/pose/save/reopen and all 24 independent Player/Tree/FPS playback
checks. Cropped action durations, timed standing blends and native contact cues
are retained; one mixer owns each character. Both core-reload phases pass
80/80 dry calls with complete saved-file hashes and poses unchanged; all ten
families/103 operations stay enabled. Final stricter ordinary matrix passes
480/480 again: `candidate-r001/native-050702ce7b69420489825fb125bb4c46/matrix.json`.
Receipts: `gates.json`, `sequence-r001/native-check.json`, `reload-r001/core-reload.json`.
Visible editor quit normally through the public API before the full runner,
which also completed. No public generation/editor test remains active.

The only ongoing work is continuous media capture (20 transition movies then
two sequence movies), source CI collection, strict archive/Explorer delivery.
Inspect both recording-progress files and actual PIDs before resuming. The
sequence recorder is queued behind transitions; do not run another GPU capture.
Human approval remains null. Do not release or advance the next motion set.

A concurrent read observed a truncated in-progress receipt. New Python/PowerShell
receipt writers replace complete files atomically. Python interruption/recovery
and Windows PowerShell replacement controls pass; active older recorders retain
their original loaded scripts. Their status files must still be read with retry.

### Recording integrity checkpoint

All ten start movies are complete; stop capture is active and sequence capture
is queued behind it. Each video contains complete reset-separated played takes,
not isolated frames. Completed movies are independently decoded and hashed.
Nine completed captures additionally pass CRC checks on all 25,920 original
PNG frames (`completed-frame-crc-checkpoint.json`). Both compositors now verify
every PNG checksum before encoding; a deliberately corrupt IDAT chunk is
rejected while its valid control passes (`png-crc-control.json`). This changes
artifact validation only; the recorded motion and sequence sources are intact.

Exact-source CI `38172191292` on `80cfb59` is green and archived with all six
job receipts, 28 headless suites, four Windows/Linux editors (395/397 with only
the two named private-rig skips), both live MCP jobs (118 pass each), zero
engine/route/discovery errors and zero approved gait fixture drift. A newer
checkpoint CI is running. Final archive and PC video delivery still require
all 22 movies. Keep approval null and pause for human feedback after delivery.

### Final source CI archived

Source `037dae4`, Actions `38174953452`: 28 headless jobs, four editor jobs
(395/397 with only the two named private-X-Bot skips), and both live MCP jobs
(118 pass/zero fail each) pass on Windows/Linux. All required and advisory jobs
pass, the tested merge tree matches source, and all approved gait digest drift
is zero. Exact core checkouts, six raw job logs and hashes are archived in
`source-ci-037dae4/ci-receipt.json`. Prearchive integrity verifies all 575 saved
scenes and all eleven protected fixtures. Animation source remains `4137cc5`;
sequence source is `80cfb59`; subsequent code only hardens recording receipts
and PNG validation. Transition recording continues, with sequence capture
queued behind it. Remaining gates: all 22 movies/archive/Explorer and explicit
human feedback. No visual approval or release.

### Final delivery provenance guard

Sequence delivery now explicitly requires the captured source SHA, original
scene names and route-manifest hash, both camera views, four-rig order, exact
chapters, 60 FPS and one root consumer. Seven controls with false source, scene,
mode, ownership, camera, chapter and rig order are rejected. These are metadata
controls, not visual approval (`sequence-provenance-guard-control.json`).
The sequence encoder also replaces its complete receipt atomically.

The first prearchive native-helper path comparison used nonexistent root-level
paths, making that source-only comparison ineffective. The 575 saved-scene
hashes and eleven protected-fixture checks were valid. Corrected comparisons
require all four real `test_project/tools` files to exist and match the gated
source. The strict final archive repeats these checks. No animation, renderer
or native checker changes. Continuous recordings remain active; human approval
is still pending.

## PC reset checkpoint (2026-10-12)

User asked to save work for a PC reset. Code source `4ad221e` is pushed;
Actions `38178266487` completed successfully (collect its raw receipt on resume).
All 20 transition MP4s plus the clean sequence MP4 are verified and preserved.
Clean sequence: 5,280 decoded frames /88s, exact source/scene/manifest checks
pass. Diagnostic sequence has 3,528 preserved PNGs and no final native report.
Its task processes are gone; old renderer PID 21740 is now an unrelated
conhost.exe. Never stop a reused PID. Original recording status is retained;
current status is `interrupted_for_pc_reset`. Last partial frame CRC passes.

Recovery: `release_r2_start_stop_20261011/reset-checkpoint-20261012.json`.
Keep completed media and immutable scenes. Resume only diagnostic capture into
a new attempt folder; do not overwrite partial frames or regenerate the 80
public clips. Then collect source CI, run the strict 22-video archive, open
Explorer and explicitly pause for feedback. No human start/stop approval yet.
Work is paused for the user's reset.

## Resumed diagnostic capture (2026-10-12)

The user resumed work. All 21 completed movie hashes, four saved sequence scenes
and eleven protected fixtures still pass. Source CI `4ad221e` is now archived
in `source-ci-4ad221e/ci-receipt.json`. Only diagnostic recording is resumed.

The first fresh attempt exposed an existing renderer initialization error:
base setup calls the overridden contact callback before derived setup attaches
`review_row`. Its frames/logs/status remain in `sequence-diagnostic-recovery-r001`;
the earlier interrupted 3,528 frames also remain untouched. Base rendering
setup now attaches the saved row before its first visual update. No animation
or playback logic changes. Eight actual native setup controls pass: four rigs
and two cameras, both initial idle contacts correct, zero engine errors, and
exactly identical clean/diagnostic bone poses, root and camera transforms.
The first control-only script parse failure is preserved separately.

Receipt: `renderer-initialization-green.json`; recipe/progress:
`sequence-diagnostic-recovery-r002`. Capture just diagnostic into this new
folder. Keep the old clean movie. After source CI and full decode pass, merge
only the verified diagnostic media entry into `sequence-r001/media.json`, then
run the strict 22-video archive, Explorer delivery and explicit human pause.
No start/stop visual approval; do not advance the next motion set or release.
