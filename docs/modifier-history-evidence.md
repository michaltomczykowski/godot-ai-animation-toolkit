# Modifier history evidence adapter

Scope: five existing modifier operations, exact per-case public inner dispatch.
No production handler, fixture, matrix axis, asserted threshold, or native
reference construction changes. Existing92-case/828saved-state/276native-state
runtime gate remains intact, including ordered stacks and live restart tests.

## Raw collection

`test_rig_modifier_history.gd` emits each existing `_case` stage: exact request,
before/dry/write/Undo/Redo snapshots, scene/global history versions, original
node IDs and restored IDs, selected modifier class/identity, each packed and
reopened state/hash, peer/pristine snapshots, unchanged outer/inner source file
hashes, shared resource identity, orphan sets, case-local errors and assertion
identity. Predictable refusals emit each actual dry/write request and response,
scene/history/orphan invariance and case-local error slice.

`check_rig_modifier_history.gd` retains its exact native code and adds raw
per-case failure/error slices, saved scene hashes, operation/request identity,
actual saved/native requested-property dictionaries and per-ID/FPS native-vs-Do
and Redo-vs-Do differences. The existing .001 limits remain unchanged. The
existing wrapper records the completed real subprocess under each of the five
operation keys; no caller-supplied pass status is accepted.

## Derivation

The standalone adapter requires the exact public `test_run` begin/end span,
suite/test/layout/variant/request/case binding and individual verbose test result.
It derives dry_run, undo_redo, save_reopen, source_unchanged and reported_errors
only from their raw stages. Existing predictable refusals supply typed_errors.
A missing native batch leaves playback and valid_effect absent/pending.

Native evidence requires exact command/engine/source,12unique case rows across
30/60/120FPS × Do/Undo/Redo/independent-native-Do, each saved-scene hash matching
its editor persist receipt, actual per-case clean checks, correct requested
native class, influence predicates and saved-vs-independent property comparison.
Three exact native/Redo comparison rows below .001 support intended valid_effect;
a changed snapshot or nonzero moving/effect field cannot supply that check.
Generated joint caches retain the same exclusions as the existing native checker.
Vector3 textual JSON values use the same approximate-comparison contract rather
than string rounding equality.

## Limits and integration

Apply `docs/modifier-history-integration.patch` using
`git apply --check --ignore-space-change` then `git apply --ignore-space-change`.
It only adds the shared trace emitter and explicit collector dispatch/native
batch joining. Graph worker's independent collector patch can be merged beside it.
The fresh native batch must be executed after these source changes are committed.

Ordered stacks, live spring redo restart, existing-native-retarget refusal,
visual assessment and individual external invocation remain separate channels;
this adapter does not relabel them. No track_paths_types check is invented for
scene_structure operations. Non-target evidence covers the actual peer/source
file/shared-resource and Undo identity predicates, not every possible caller
property. Native initial/property assertions remain source-specific, not artistic
approval. Offline control reports are synthetic schema controls, not actual
Godot execution or qualification. Native parse/fresh public replay are pending.
