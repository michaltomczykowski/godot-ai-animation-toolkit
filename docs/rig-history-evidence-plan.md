# Rig history observations for release evidence

Scope: the existing rig_pose_history, rig_chain_history and rig_clip_history
matrices, covering pose_apply, rig_chain and eight clip writers. Preserve every
authored request, fixture, expected transform, native checker and threshold.

Record each actual dry run, deliberate refusal, write, Undo, Redo and saved
reload as a raw case inside its real public test_run span. Include scene/global
history versions, observed permissions, complete existing fixture snapshots,
paused Player state when relevant, case logger errors and instanced peer/source
hashes. Saving records actual pack/save return codes, SHA256 and reloaded state.

An independent Python adapter will derive only the checks these witnesses
support: dry run, exact typed refusal, Undo/Redo, save/reopen, synchronous errors
and explicitly observed non-target invariants. Merely different output does not
establish the requested effect. Playback, full requested motion and visual review
remain with their independent native/temporal gates.

Require exact suite/test/mode/kind/operation, request and public span identities;
reject missing stages, wrong versions, corrupt snapshots and wrong error codes.
Use meaningful deliberately corrupted records as offline controls. Parse in actual
Godot 4.7.2 and run the actual public matrix only after the root r007 job releases
the single Godot slot. Offline records are never execution qualification.

## Prepared increment

The three existing matrices now emit 93 raw cases:30 pose,18 chain and45 clip
cases. Four offline test methods pass, including all93 identities and deliberate
stage/version/request/permission/engine-error/source/reload/public-span corruption.
Independent source review caught expected default-library creation in the nine
missing-library cases. Only that exact `source` to default-plus-`source` library
transition is normalized; missing/extra libraries still fail. Permissions must
match the declared mode before and after writing, besides exact Undo/Redo state.

Source invariance is intentionally limited to observed authored rest/hierarchy,
non-target clips and Player state, and instanced peer/pristine/file hashes. Case
logger coverage starts after fixture setup and includes cleanup. Source resource
object identity/allocation history remains the existing suite's responsibility.
No new valid_effect, track_paths_types, playback or visual checks are claimed.
Actual Godot parse and public matrix execution remain pending integration.
