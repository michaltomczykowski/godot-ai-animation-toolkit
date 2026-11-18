# Seven graph writers: case-local evidence increment

Status: code/offline controls prepared only. Actual editor parsing, public
history dispatch, saved-clone playback and CI at this source remain pending.
No operation/media/release row is qualified by synthetic controls.

## Source scope

Only test_graph_route_history.gd adds raw hooks to the existing7writer by4mode
matrix (new, replace, instanced, instanced_new). It preserves prior requests,
Undo/Redo conditions, fixtures and numeric verifier thresholds. Shared outer
operation_history_trace is reused through a small graph_history_trace helper.
No product behavior, generator or accepted fixture changes.

Each row records exact request/dry/refusal/write, before/dry/error/generated/
undo/redo snapshots and scene/global versions; actual persisted undo/redo path,
SHA, pack/save status and reopened snapshot; case-local sticky assertion state,
assertion delta and errors; original clip/key/property inputs, companion graph
snapshot and packed-source/fixture before-after hashes. Independent adapter
checks those observed stages; suite totals and changed snapshots cannot replace
raw case proofs. Graph root class, player path and actual binding are recorded.
The source fixture is now explicitly required in the provenance dependency map.

## Native intention and honest applicability

On the disposable reopened REDO fixture only, a clone plays the saved graph
with every other mixer disabled and manual clocks. No graph, animation keys or
poses are replaced. Independent branch checks reuse the existing saved graph
verifier's bounds: idle abs(x)<=.01, walk x>=20 after30/60s, run gain>10 after
6/60s, jump y<=-20 after30/60s, lean>=.05 after30/60s and Player not playing.
They prove this fixed fixture/branch, not every possible graph/controller.

New/rootless wire creates a binding and has no native effect claim. Seeded
replace/instanced wire proves only its existing idle branch holds neutral with
no Player competition after binding/active change; it is not moving-wire proof.
Wire parameter variants remain separate existing tests, not inferred coverage.
Graph_get currently tests read-only behavior but lacks an exact read-accuracy
oracle, so this adapter emits no graph_get evidence.

The adapter binds driver, exact suite/test/mode/op/request, exact dependency
Git blobs/SHA256, run ID, timestamp inside a unique public test_run span and
that exact verbose per-test result/assertion count. It recomputes saved graph
resource/player-path/classes plus actual native values. Its track_paths_types
key explicitly describes GRAPH resource/player-path/type admission; it does
not claim generated animation track authoring. Native values drive valid_effect
and playback only where observed; graph connections unreadable from graph_dump
are never inferred from node lists alone. Outer collector still authenticates
context/source envelope and raw-file hashes before this adapter.

## Minimal collector integration

Apply docs/graph-history-collector-integration.patch against root3dcb7f8 after
its source freeze ends. It adds only fixture dependency collection and explicit
graph_history_v1 adapter dispatch. The worker does not overwrite the root
collector from its older branch. Root must review/apply/recommit the patch;
the patch file's presence alone does not enable integration.

After integration: parse test/helper/adapter; run existing graph_route_history
through a fresh exact public test_run with context/span tracing enabled, retain
all28 raw rows, collect through strict adapter, then inspect seven known writer
keys. Require original assertions plus new saved-native assertions and zero
engine errors. Keep native/media evidence separate. Actual Windows/Linux CI
and external direct graph cases remain pending; no claim is made from an
unexecuted source increment.

## Offline controls

Four unittest methods exercise all28 op/mode positive shapes, all6moving-writer
native counterexamples,23 targeted row corruptions (history, dry/refusal, saved
state, source/peer/hash, graph class/path/clip, competing player, wrong clock/
dt/frame count, missing native and forged expected-value echo/request), and12
public span/source/test corruptions. No fake result counts as actual evidence.
Python compilation passes. GDScript parsing/runtime are pending root scheduling.
No Godot, editor, native or GPU process was launched by this worker.
