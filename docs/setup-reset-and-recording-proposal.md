# Saved setup reset control and recording proposal

Status: proposal only. No runtime change, checker replay or media qualification.

## Observed reset failure and contract

The immutable production-r003 controls contain 12 failing 3.0s reset cells
(four rigs at 30/60/120 FPS). The first advance after reactivation returns zero
root delta: the endpoint loses one speed/FPS step. Cross-cut pose/contact
comparisons also treat an intentional restart as continuous motion. Grounding
remains healthy; this evidence does not justify a production solver change.

Godot sets `started = p_active` on Tree activation and marks its first blend
processing as seeked. See the [4.7 engine implementation](https://github.com/godotengine/godot/blob/4.7-stable/scene/animation/animation_tree.cpp#L637).
The bounded contract is NEW TAKE, not phase-preserving pause/resume.

## Proposed distinct control

Preserve all original 3.0s reports and manifests. Add a distinctly identified
six-second control with a declared cut at 2.6s. Actual original traces show
contact at this common 30/60/120 FPS boundary for all twelve rig/FPS cells;
at 3.0s some rigs have no warm stance anchor. The new run must still verify
actual warm state rather than trusting that observation.

At the declared cut, before the next physical time step:

1. Finish take-one metrics. Capture nonempty phase and stance-anchor caches,
   native phases, diagnostics, owner position and final signaled pose. Failure
   to encounter the required warm state fails the control.
2. Deactivate the Tree; call the public reset method with a unique reason.
   Assert reset count increases exactly once and caches become empty. Preserve
   cumulative evaluations, reach failures and residual/correction maxima.
3. Reactivate and advance exactly zero seconds. Process/capture the actual
   final modifier signal. Assert zero root delta and zero owner travel. Count
   this extra graph evaluation and final signal explicitly. Assert the explicit
   reason/count before priming; record any further engine-driven reset separately.
4. Begin take two from this primed final pose and current actor origin. Clear
   only checker previous-pose/contact-window/pole baselines at this declared
   cut. Record the cut position/rotation discontinuity separately, not as a
   smooth-resume claim. Never write bone poses or alter the graph/helper.
5. Apply every subsequent dt and consume native owner-parent root delta once.
   Keep original contact, penetration, slide, velocity, knee, reach and finite
   gates within each take. Require contact coverage in both takes. Check each
   take's speed integral/endpoint and their total against actual total owner
   travel, with the existing endpoint tolerance. Report take intervals/origins,
   samples, zero-time priming and cumulative signal/evaluation counts.

Validation after approval: twelve distinct reset cells plus a deliberately
unprimed negative control that must expose the one-step deficit. All other
original control reports remain immutable. No threshold relaxation. A fresh
native run is pending root scheduling and permission.

## Bounded continuous recording path (read-only plan)

Use the four actual saved Responsive bundles. Prioritize three conditions:
half idle/walk, midpoint walk/run, stationary jump OneShot. Freeze durations
from saved clip metadata so both locomotion takes cover complete relevant
cycles and OneShot includes authored landing, terminal hold, fade and recovery.
The provisional presentation is four rigs, two fresh three-second takes each,
fixed simultaneous front/side views, clean and diagnostic variants.

A new dedicated saved-setup loader must retain the saved Tree, helper, keys and
root consumer contract. Existing character render loader creates a private
replacement Tree and therefore cannot serve this purpose. Reuse presentation
geometry/cameras only. Each view has one saved Tree and one translation
consumer. Real skinned meshes remain original; synthetic rig proxy geometry
is explicitly labeled display-only and reads final signal snapshots. Never
apply manual bone poses or substitute a helper.

Start each take with a fresh saved-scene instance, explicit zero-time priming
and fresh helper state. Keep actor/world framing fixed throughout the take;
show the declared reset cut before the next take. Advance 180 actual dt steps
for three seconds, recording after final modifier processing; do not count
zero-time priming as a physical frame or lose the first dt. Confirm rendering
skin update timing from the final signal rather than reading later restored
skeleton poses. Record native phases/weights, OneShot active state, root deltas,
owner travel, grounding diagnostics and exact signal/evaluation counts.

Use immutable source/scene/renderer/schedule hashes and new output directories.
Reject engine errors, missing final signals, unexpected writers and incorrect
PNG dimensions. Configure viewport dimensions before process startup if using
MovieMaker; assert actual render/PNG sizes. Fixed cameras must include full
travel, feet, hands and jump height. Capture remains pending, followed by a
scoped temporal/visual assessment; numerical checks confer no image approval.

## Approved new-take implementation checkpoint

`check_setup_grounding_controls.py --new-take-only` prepares distinct primed and
unprimed manifests (one spec per rig, three FPS each). Original default dynamic
spec retains reset_at_s=3.0; immutable old failed reports are never rewritten.
The checker records two take endpoints/contact counts, actual warm reset state,
explicit clear/reason/count, zero-time final signal, cumulative evaluation/reset
counts and the cut pose discontinuity. It resets only cross-cut previous-pose,
stance-window and pole baselines; all accumulated maxima/gates remain intact.
The unprimed control must specifically fail an endpoint assertion.

Offline orchestration controls:16 pass. GDScript parsing and 12+12 native cells
are pending the root-owned process slot; no native validation is claimed.

Review follow-up: warm phases are required for every reset. A nonempty warm
anchor is required only by the explicit new2.6s control flag, so the existing
3.0s dynamic input remains testable with proper new-take priming. Witnesses
capture actual reset counts. Reset preserves cumulative evaluation/reach/max
counters; prime requires exactly one evaluation, a finite in-limit grounded
solve and nondecreasing maxima. Total final signals must equal physical frames
plus explicitly counted prime signals. Parsing/native remain pending.
