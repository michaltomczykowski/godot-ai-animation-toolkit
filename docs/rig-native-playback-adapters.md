# Seven saved rig playback adapters

This closes only exact raw `playback` coverage. It does not promote intended
values, visuals, history or candidate qualification from suite totals.

Root integrated `rig-native-playback-integration.patch` against5eef8d5. The
preserved patch records five already executed modifier subprocesses,
adds the two saved static structure probes to the existing rig gate, and routes
seven operation keys through the strict standalone adapter. Modifier checker
output gains actual scene identity; its original .001 response threshold stays.
Retarget retains its existing .1 threshold and six-frame processed witness.

The pose probe reads the actual saved pose and requires its requested0.6rad
rest-relative arm rotation persist for six native frames; it never corrects the pose. The chain
probe verifies the requested appended bone/name/parent/rest offset, then rotates
only its scratch native parent to verify native hierarchy propagation for six
frames. It does not author an animation or replace the saved scene. The public
request and returned appended-bone names/count bind this scene to that operation.
Godot4 global propagation uses parent global pose times child local pose; the
local pose already contains its rest offset. Actual saved bone/parent indices are recorded; the public response does not
advertise indices, so no returned-index claim is made.

The collector still requires a prior successful non-dry public call for the exact
operation and scene, and checks exact audited request parameters. Source-bound
checker/helper dependencies, exact engine/command/scene/op, complete subprocess
logs, return code and operation-specific native results are required. Fresh
root-owned CI execution remains pending. Root actual Godot4.7.2 replay exposed
two initial oracle errors: doubled chain rest offset (0.05m error) and comparing
a rest-relative request against an absolute0.6rad quaternion (1.5926rad error).
Original logs remain private. Corrected probes pass both original saved public
fixtures with zero error; chain parent response is0.3999993rad. Ten actual native
controls pass: two originals and eight deliberately corrupted scene copies
(rest/local position/parent/rotation/scale/enabled changes). Saved source fixtures
are untouched. This checks the probes, not fresh candidate public qualification.
Private receipt: `rig-native-controls-r003/summary.json` under the release root.

Reference: [Skeleton3D pose API](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html).
