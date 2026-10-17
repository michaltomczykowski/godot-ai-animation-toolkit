# Seven saved rig playback adapters

This closes only exact raw `playback` coverage. It does not promote intended
values, visuals, history or candidate qualification from suite totals.

Apply `rig-native-playback-integration.patch` from the repository root after
integrating this commit. It targets root5eef8d5 collector/CI state; use `git apply
--check` first. The patch records five already executed modifier subprocesses,
adds the two saved static structure probes to the existing rig gate, and routes
seven operation keys through the strict standalone adapter. Modifier checker
output gains actual scene identity; its original .001 response threshold stays.
Retarget retains its existing .1 threshold and six-frame processed witness.

The pose probe reads the actual saved pose and requires its requested0.6rad arm
rotation persist for six native frames; it never corrects the pose. The chain
probe verifies the requested appended bone/name/parent/rest offset, then rotates
only its scratch native parent to verify native hierarchy propagation for six
frames. It does not author an animation or replace the saved scene. The public
request and returned appended-bone names/count bind this scene to that operation.
Actual saved bone/parent indices are recorded; the public response does not
advertise indices, so no returned-index claim is made.

The collector still requires a prior successful non-dry public call for the exact
operation and scene, and checks exact audited request parameters. Source-bound
checker/helper dependencies, exact engine/command/scene/op, complete subprocess
logs, return code and operation-specific native results are required. Fresh
root-owned CI execution remains pending; no local Godot run was authorized.
