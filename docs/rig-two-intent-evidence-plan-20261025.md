# Bounded pose_apply / rig_chain intent evidence

Plan saved before implementation. No engine, primary edits, new calls, runtime
changes, response oracle, visual claim or broader family work.

## Inspected actual evidence

Read immutable Linux 4.2.1 history rows under private ci-596e278-r001 /
mcp-editor-ubuntu-latest-4.2.1 / operation-evidence/public-calls. There are 30
pose_apply and 18 rig_chain raw history cases, each with actual request, native
write/redo/saved-reload snapshots and exact public test_run span IDs. The pose
rows retain numeric Transform3D rest/pose, all other bones, metadata and hierarchy.
The chain rows retain the exact added bone parent and full numeric rest matrix.
Existing adapter currently only derives history/source/error/refusal checks.

## Smallest independent increment

Reuse only 3D pose `apply` cases (local/locked/editable: 3 rows) and 3D chain
`create`/`append` cases (6 rows). Fixed source cases already bind exact requests.
For pose, independently construct expected full local transform from the fixed
seed rest angle .2 plus requested .6-radian delta, additive position (.4,-.3,0)
and absolute scale (1.6,.6,1.3). Require nontrivial change, unchanged rest,
metadata, enabled state, hierarchy and every other bone, at write/redo/reload.
For chain, independently construct the requested Z30-degree / scale(1.4,.8,1.2)
rest matrix and position(.5,1,0), exact parent/name and single added bone;
preserve all existing bones. Use Godot Basis.scaled global row scaling for rest.
Saved chain pose basis is native decomposed rest (not identical under nonuniform
scaling); this increment proves authored rest/hierarchy, not a separate pose
rotation or deformation claim. Existing native playback evidence stays separate.

Do not copy the existing playback status to valid_effect. Do not use producer
response keys/counts. Remaining 2D/blend/reset/mirror/subtree variants stay pending
for this new intent channel. Original six channels and raw outputs remain.
Derive the new channel only after existing exact case/public/source/history gates
pass. New adapter dependency must be present in context for future qualification;
historical rows may test predicates offline but cannot qualify a changed source.

No new driver/native observer is necessary: current raw shape is sufficient.
Deliver a minimal integration patch for the shared history adapter, pure math
checker and corruption controls. Existing original tests must still check their
six channels without treating unsupported intent cases as successes.


## Prepared result

Seven new pure controls and four existing rig-history controls pass. Python
compilation and diff checks pass. Historical offline inventory: 9 supported
numeric cases pass, 39 unsupported variants pending, zero predicate failures.
The separate JSON inventory retains exact raw hashes and IDs/context identity;
it is exploratory historical evidence, not qualification of this new checker.

Root integration: cherry-pick the new checker, tests and docs, then apply
`git apply docs/patches/rig-two-intent-history-adapter.patch`. No shared source
file, driver, runtime or collector was edited here. Existing collector already
uses this history adapter. New source dependency is added by the minimal patch.
The raw write/redo/reload transforms support intent directly; no new observation
or engine run is needed to develop these predicates. Future candidate collector
execution must use its actual same-source context and raw public span bindings.

Pure command: `python -m unittest discover -s tools -p test_operation_rig_intent_checks.py`.
The checker makes no external public invocation claim for inner cases. External
invocation proof and native saved playback remain distinct existing receipts.
