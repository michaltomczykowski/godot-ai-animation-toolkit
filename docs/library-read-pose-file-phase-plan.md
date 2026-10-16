# Bounded library read and rig pose-file evidence phase

Approved by root after the103-operation gap audit. Root owns the editor/native
slot. No handler/runtime changes or worker native/editor/MCP launches.

## Exact scope

1. Preserve the first existing16 library file/read outcomes and their validator.
   Add a separate raw observer only around existing malformed template_list and
   spec_import calls in test_library_contracts. Record exact malformed bytes,
   actual typed response and before/after fixture/history/error observations.
   Do not observe arbitrary unsafe/private paths or invent successful reads.
2. Observe pose_save / pose_blend file operations in the existing
   test_rig_pose_history.test_pose_file_and_shape_contracts. Keep raw source
   skeleton/fixture, exact request/response, file before/after bytes+SHA,
   scene/global history versions and Logger deltas. Add a nontrivial pair of
   authored inline poses with independently calculated halfway output, actual
   file readback and a successful dry overwrite that preserves existing bytes.
3. Separate source-specific validator identities for read refusals and pose files.
   Bind each emitted row to the existing actual public test_run span and exact
   passing non-skipped verbose test result. No external invocation inferred.
4. Pure validators recompute only each observed applicable result: typed read
   refusal/no mutation; pose-file semantics, successful dry-byte invariance,
   file effect, source/history/error invariance. Scene Undo/Redo/playback/visual
   checks stay N/A for file effects. Do not turn suite totals into per-op passes.

## Verification and release boundary

Use offline positive/negative fixtures for wrong bytes/hash/path/source/span,
wrong refusal code, changed scene/history, incorrect blended output, dry writes,
engine errors and skipped/aggregate-only test results. Keep signed nonzero
resource-ID logic untouched. Shared source edits are limited to explicit trace
emitters and collector dispatch; historical raw receipts are never rewritten.

Root must parse all touched GDScripts and execute the actual two suites after
its renderer queue. Pure tests cannot qualify the new rows. Any actual operation
failure must be preserved and localized before considering a handler fix.

## Increment 1 implemented

The malformed-file phase observes exactly eight existing template_list and three
existing spec_import dispatches. Unsafe paths, template_apply/delete, spec_apply
and inline malformed metadata remain outside this observer. Original sixteen
file rows retain their identity and validator. New library_read_refusal_v1 checks
exact authored malformed input bytes, INVALID_PARAMS (never generic Unknown),
scene/global history and file invariance, plus captured Logger deltas. The public
span verifier requires the exact verbose non-skipped passing inner test result.

Five focused offline controls, eight existing file controls and fifteen collector
controls pass. No Godot/native run occurred. Root must parse and execute this
increment. POSE_FILE implementation remains pending the next increment.
The shared preset emitter/dispatch is reserved for the coordinated preset worker;
it cannot produce any evidence until that worker supplies its validator and rows.
