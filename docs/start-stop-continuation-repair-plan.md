# Start/stop: continuation repair checkpoints

Baseline and root/reach instrumentation are complete. Generation remains via
Godot AI's public custom-tools API in a visible Godot 4.7.2 editor, then saved
engine playback. Keep the approved walk, run and idle generators/fixtures exact.
No start/stop visual approval exists. Recovery is `release_r2_start_stop_20261011`.

## 1. Independent references and complete endpoints

Prepare walk at its own period/sample rate (ordinary defaults 1 s / 60 Hz) and
idle at its approved defaults (3 s / 60 Hz), with the same rig and style. These
are preparation-only calls: no extra scene write or mixer. Transition duration
and its 120 Hz authoring density must not alter reference cadence or endpoint.
Add explicit `gait_duration` / `gait_samples` controls so a caller can join a
nondefault saved gait. Validate and report both, alongside idle reference timing.
Use actual engine interpolation for fractional phases and every local channel,
including hands/fingers and hips. Start begins at accepted idle phase zero and
ends at the requested walk phase; stop starts at that phase and ends at idle
zero. Preserve root ownership and one-shot mode.

First checkpoint retains the measured old step scheduling while replacing its
reference/endpoint contract. Verify all bones against separately saved approved
clips, including short/long transitions and between-key phases. Record remaining
contact/velocity failures openly; endpoint agreement alone cannot approve output.

## 2. Moving references, root speed and support transfer

Blend moving reference poses rather than a single frozen gait frame. Start's
last window continues the reference gait toward the requested phase; stop's
first window continues away from that phase. Idle continues into/out of phase
zero. Cover at least the 30 FPS join neighbourhood with exact reference samples.
Keep the legs on reachable world-space targets during the interior transfer.

Plan monotonic root travel with zero standing speed and reference walking speed
at the gait boundary. Publish the sampled external actor translation schedule
for in-place clips as numeric arrays; consume that exact schedule in native
playback. A paired extracted clip remains only the preserved baseline diagnostic.
No two mixers may own root translation or character bones.

Sample reference foot positions/orientations by FK over engine-interpolated
local channels, including intermediate parents. This generation FK is never
used by the independent checker. Choose support by remaining stance time. Start
plants a preparatory step, then moves the other foot into gait; stop plants its
lead foot, then recovers the old support into idle. Lift before horizontal swing
and finish horizontal travel before lowering. Match swing endpoint velocities
where the gait window begins/ends. Both support sides must work.

Compute a bounded pelvis reach envelope from every authored target and actual
leg geometry, with stable rest-derived knee poles. It must join reference hips
smoothly without replacing endpoint poses. Record actual post-plan solve clamps.
An unsupported explicit duration/speed/rig request returns a typed reach error
before mutation; ordinary outputs on all four rigs must have zero clamps.

## 3. Contact and continuation acceptance

Emit timed intended contacts for each step and reference window. The native
checker reports intended and observed ankle-band contacts separately, including
height, drift, penetration and lift. Do not define contact from low velocity to
hide slide. Retain slide <= min(2% leg length, 3 cm), penetration <= 1% leg length,
no flips/clamps/nonfinite output and strict saved reference/velocity thresholds.

Exercise both supports, fractional between-key phases, independently short/long
transition and gait periods, and both root requests. Compose saved
idle -> start -> walk -> stop -> idle through `animation_sequence`, cropping
at reported action boundaries rather than stationary storage tails. Verify one
character-owned result, blends, markers, extraction and actual saved playback.

## 4. Final gates and human pause

Complete the 80 ordinary public clips / 480 native runs, focused public tests,
core reload/discovery, full local suites and Windows/Linux source CI. Record
continuous matched before/after videos, five clean/diagnostic pairs per operation
plus composition, front/side and two reset-separated complete takes on every rig.
Decode/count/hash and archive exact source/scenes/rigs/tooling/receipts. Commit,
push and verify remote SHA; open PC Explorer, then pause for explicit feedback.
Do not promote fixtures, advance the next motion set or release before approval.
