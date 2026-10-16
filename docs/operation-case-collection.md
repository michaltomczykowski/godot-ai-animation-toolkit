# Actual operation-case collection

The collector emits exact successful public invocation cases and a narrow
linked FX native-playback adapter, **not** complete release qualification. Static driver
candidates for all103 operations are in `operation-route-coverage-plan.json`.
That map contains no executed IDs and confers no passes.

## CI entry point

After committing/integrating the collector and its shared-call hook:

```bash
python tools/ci_mcp_route.py --core-root .ci/godot-ai --case-output-dir operation-evidence
```

Preserve `operation-evidence/**` as a CI artifact, including on failure. Run in
all four existing released-core/platform cells; core main stays advisory. The
output directory must be new. Default CI behavior is unchanged unless this flag
is supplied. `--require-all-public-operations` additionally blocks a run missing
any successful actual operation call. Do not enable that final strict switch
until the known preview limitation has an explicitly qualified solution.
`--existing` cannot use this collector because the engine identity must belong
to the editor launched by this runner.

The context executes the actual configured engine's `--version`, requires4.7.2,
reads the exact toolkit/core commits, rejects dirty tracked core/source code,
and binds committed addon/tool/test dependencies to Git blob + raw SHA256.
Each shared `mcp_presets_audit.call` records its actual completed request/result,
normalized advertised operation, raw public tool/envelope, unique call ID,
driver and context SHA. Promoted calls and `custom_manage.invoke` are both
covered. Non-tool/session/test-run calls and unknown/cross-family ops confer no
operation proof. The caller's returned dictionaries are not modified.

The runner collects even when an existing gate fails, preserving partial actual
coverage. A partial report is diagnostic; it does not make the failed job green.
Source/dependency changes, foreign contexts, request/operation mismatch and
duplicate/out-of-order events reject collection. Raw JSONL and the context are
referenced by portable paths and exact hashes within the receipt directory.

Standalone equivalent, for a root-controlled run that exports both variables:

```bash
python tools/operation_case_collector.py prepare --root . --core-root .ci/godot-ai --godot /absolute/path/to/godot --output operation-evidence/operation-context.json
# Export TOOLKIT_OPERATION_CONTEXT to that JSON and
# TOOLKIT_OPERATION_TRACE_DIR to operation-evidence/public-calls before audits.
python tools/operation_case_collector.py collect --root . --context operation-evidence/operation-context.json --trace-dir operation-evidence/public-calls --output operation-evidence/operation-case-results.json --allow-partial
```

## Gate-compatible case format and limits

The result has source, actual engine/platform/core identity, dependency hashes,
raw-artifact references and `cases`:

```json
{"id":"unique-actual-call-id","operation":"animation_fx.shake","checks":{"mcp_invocation":"pass"},"route":"public_godot_ai","scope":"candidate"}
```

Only a nonempty successful result from an actual non-dry public call gets this
pass. A failure/refusal is retained as failed invocation; dry calls are retained
without an inferred unchanged-source/dry-run pass. Explicit `animation_inspect`
`dry_run` remains its advertised read operation (the op name is not the writer's
`dry_run:true` flag). No semantic validity follows merely from successful return.

Read operations still require explicit result semantics and source invariance.
File writers still require observed exact file creation/content/deletion and
nonmutating dry runs. Their inapplicable native playback/Undo checks remain N/A
under the existing applicability schema; the collector does not invent them.
A private-rig skip, generic green test-run total, typed headless preview refusal,
or advisory core cannot satisfy a missing released-cell operation.

## Remaining instrumentation

Each semantic/history/native validator must emit operation-specific checks tied
to the exact raw case IDs/scenes it actually validates. Existing broad matrices
already exercise many operations but currently print aggregate test totals; do
not map those totals wholesale onto every advertised operation. First collect
four actual public traces and inspect `missing_successful_public_operations`.
Then add narrow calls only for real missing coverage. Preview currently expects
a headless rendering refusal, so PNG output and successful rendered effect stay
pending. Public GPU preview/native graph baseline and independent media review
remain separate actual-proof tasks.

This increment deliberately does not emit `valid_effect`, `undo_redo`, `playback`,
`typed_errors`, `source_unchanged`, `file_effect`, or visual passes from a green
suite or manually completed ledger. Those need subsequent validator-specific
instrumentation. `operation-case-results.json` can supply `mcp_invocation` case
bindings to the existing release gate; it is not a fabricated qualification
manifest or release approval.

## Pure controls

```bash
python -m unittest discover -s tools -p test_operation_case_collector.py
```

Eleven tests cover successful exact operations, dry/refused/empty results,
normalized nested routing, unknown/wrong-family/suite-total non-inference,
changed dependencies, wrong operation/context/duplicate events, and advisory
core identity. Additional native controls reject missing public origins, wrong operation/scene
or engine bindings, ambiguous result markers and engine errors. No editor, MCP
session or engine launch is needed by these tests.

## Actual native FX adapter

`ci_mcp_route.fx_playback_gate` now records each real completed native subprocess
(command, return code, stdout and stderr), without accepting a caller-supplied
pass flag. The collector whitelists the exact source-bound
`check_fx_runtime.gd`, requires the actual engine command used by the version
probe, binds command and parsed result to the exact operation/scene, checks its
explicit failure/check arrays and rejects engine errors or ambiguous JSON output.
It links the result to a prior successful, non-dry public call for the same
operation and active saved scene using the recorded process performance clock.
A whole green suite or an unrelated public call cannot supply this origin.

These actual native cases expose only `playback` and `track_paths_types` checks;
SpriteFrames omits the inapplicable Animation track-path check. Semantic shape,
source invariance, saved history/Undo and visual gates are not inferred. Native
audio `playing` is an event observation, never proof of audible captured output.
Other family runtime adapters remain pending; their existing raw checks still
run in CI but are not mislabeled as operation-bound receipts.

## Other source-specific native adapters

The same actual-subprocess capture now covers existing edit, preset, graph,
motion/setup/secondary, rig recipe/pose-clip/bake, sequence and library-apply
runtime gates. Each adapter has an explicit source-path/marker contract and
checks its actual output metrics, return code and engine errors. It binds the
command's scene and operation, required output identity fields, actual native
engine and named generated clip to an earlier successful public case. Graph
variants map only to their actual canonical public operation; `graph_get` stays
a read observation with no invented producer playback check. The showcase
requires all seven distinct named players with actual nonzero changes. The two
library apply operations select their own independently checked clip/value.

These emit only narrow actual playback checks, not whole-family semantic or
history qualification. Thirteen pure tests include all native contract shapes,
wrong scenes, engine failures, exact named output/public-origin binding and
read-operation applicability. No earlier artifact is relabeled with these new
checks: a new source/context and actual CI execution are required.

## PR source identity and targeted preview integration

`tested_source` always comes from actual `git rev-parse HEAD`. The context now
also retains CI event SHA, actual checkout SHA, PR head/merge SHAs and a clear
classification. A synthetic PR merge checkout is never relabeled as branch-head
execution; event metadata is informational and confers no checks. Final main/tag
receipts must bind the real final source. If CI intentionally checks out PR head,
its context will say so while keeping the original GitHub event SHA separately.

`record_public_call` now returns its exact emitted case ID (orNone when disabled
or unadvertised), without changing public result dictionaries. A targeted
rendered-preview runner can bind its actual PNG/source-invariance report to that
single successful public invocation. Preview semantic/file/visual checks are
not yet inferred by this API; the strict output adapter remains separate work.

## Strict rendered-preview adapter

After an actual targeted preview run, collect it with:

```bash
python tools/operation_case_collector.py collect --root . --context rendered-preview-artifacts/context.json --trace-dir rendered-preview-artifacts/traces --preview-report rendered-preview-artifacts/rendered-preview.json --output rendered-preview-artifacts/operation-case-results.json --allow-partial
```

The pure downloaded-artifact API is
`operation_preview_adapter.verify_preview_bundle(directory: Path)`, returning
`{'context': context, 'proof': {public_case_id, checks, artifacts, limits}}`.
The matrix caller must separately require the expected exact tested source,
platform, released core/version and committed dependency Git blobs. Raw source
file SHA256s can differ across operating-system line endings; do not compare a
Windows raw checkout hash with Linux bytes as a canonical-source test.

The adapter rebinds raw trace IDs/requests/context and reopens all four PNGs,
requiring320x240 opaque, nonblank, pairwise different decoded pixels and exact
reported pixel metrics/hashes. It rejects headless commands, missing renderer
identity and any complete editor-log engine/script errors, including ANSI.
All five immediate source checkpoints must bind actual timeline call IDs and
unchanged serialized scene bytes/timelines around the successful preview and
actual typed dry/missing/overwrite refusals. Portable paths remain confined to
the receipt root. It augments that exact existing successful preview case with
`valid_effect`, `file_effect`, `source_unchanged`, `typed_errors` and
`reported_errors`. Independent visual assessment remains pending. Seven pure
adapter controls pass; no real preview is claimed without actual runner output.

## Bounded FX/edit snapshot assertions

The first live edit72 trace exposed signed RefCounted resource IDs: an actual
library ID was `-9223369453582862363`, exactly preserved through dry run and
Undo. The adapter's positivity assumption incorrectly rejected all72 dry/history
rows. Identity checks now require a nonzero integer and exact equality; zero
still fails. Raw failed derivation is preserved. The live editor assertions and
native playback were passing; this fixes the evidence adapter, without changing
editing behavior or equality tolerances.

The existing public FX and edit drivers now emit raw per-operation rows directly
after their actual comparison checks. They include the exact request, before,
after-dry, after-write and persisted inspections and real public responses.
A pure source-specific adapter recomputes only `dry_run` and `save_reopen`;
explicit offset/overlap wrap refusals expose only their actual `typed_errors`.
There is no whole-audit green-to-every-operation mapping.

The collector binds the exact write/dry public IDs and target inspections in
execution order. Successful save and forced-reopen support calls must occur
between the correct after-write and persisted probes. SpriteFrames binds its
actual node-property responses and preserves only durable assignment/animation
identity across reopen; running frame equality is intentionally inapplicable.
Support events (`scene_open`, `scene_save`, `node_get_properties`, `test_run`)
carry exact actual IDs but never count as advertised operation invocations.
The preview bundle loader accepts those support events without manufacturing
operation coverage. Existing public tool result dictionaries are unchanged.

Scope: 16 FX and 20 edit operation keys through existing calls, no new live calls.
Six focused controls reject changed dry state, absent persisted clips, missing
actual reopen, wrong requests/operations/declared checks and generic refusal
errors. The checks stay pending until this instrumented source actually runs.

Remaining assertion gaps are explicit: Undo/Redo and saved per-history-state
restoration require inner-case history instrumentation; semantic expectations,
full non-target/source invariants and general typed refusals are not inferred
from these snapshot rows. Preset/graph/rig/modifier/motion/sequence/read/file
validators still need their own applicable exact assertions. Actual previews
supply their narrow file/source/error checks; independent continuous visual
assessment and audible output remain separate. Existing historical matrices
remain reusable narratives/raw evidence, not newly fabricated candidate passes.

## FX16 inner-history raw cases

The existing64 FX history cases (16 operations, four modes) now record their
actual inner dispatcher request/responses, unchanged dry/error snapshots,
scene/global history versions, generated/Undo/Redo snapshots and both saved
state reopen snapshots with serialized file hashes. They use the same snapshots
at the existing assertions, preserving thresholds and avoiding duplicate probes.

The shared public wrapper creates one strict in-flight `test_run` span. Editor
records carry that exact span ID; the completed actual public response must
contain the exact passing, non-skipped verbose test. Concurrent requests are
refused to avoid ambiguous attribution. No span means no history evidence.
The optional helper never changes assertions or invokes operations itself.

`operation_history_checks.py` independently recomputes only `dry_run`,
`typed_errors` (actual typed missing-node refusal), `undo_redo` and `save_reopen`.
Sticky prior assertion failure remains failure. Wrong operation, test, span,
saved filename, mutated snapshots or aggregate-only suite totals cannot pass.
The route is `public_test_run_inner_dispatch`, not a separate external public
invocation; the direct public-operation trace remains necessary for invocation.
There is no semantic, full-source, visual or audible-output inference.

No new command is needed: the existing opt-in `ci_mcp_route.py --case-output-dir`
run propagates context to the editor and existing FX history driver. Collection
includes only rows actually emitted. Six focused pure controls pass; these64
cases remain pending execution from the instrumented source. No native/editor
process was run by the worker for this increment; integration must parse the
two GDScript files and CI must exercise the actual public suite.

Remaining inner-history families, read/file semantics and full applicable
per-operation source/error/semantic checks are still pending. Preserved earlier
matrices do not automatically become candidate receipts.

## Edit20 inner-history raw cases

The existing72 edit cases now use the same public span:20 base operations,
split/merge overwrite variants, and merge/layer cross-player variants, each in
local/instanced/editable mode. The helper's explicit `edit_history_v1` identity
binds the actual edit case source, the shared FX equality source and the actual
graph Logger class source; it cannot qualify another family or invented variant.

Raw records retain real requests/responses, existing snapshot comparison points,
scene/global versions, original and restored library/clip instance IDs, and both
saved state load snapshots with serialized file hashes. No extra operations,
scene saves, native processes, assertion resets or threshold changes were added.

In addition to the four narrow dry/error/history/save checks, the adapter can
derive `reported_errors` from the actual operation-case Logger counts/slice and
`source_unchanged` for the specifically observed non-target inputs: unchanged
other clips in the target player, OtherPlayer, plus the peer and the packed
source file for instanced/editable cases. It recomputes both pristine snapshot
equality and source-file hash equality. This does not claim general semantic
correctness, visual approval, audible output or preservation of unobserved data.

Twelve focused history controls cover both families. Edit controls reject
other-player/clip changes, missing peer/pristine snapshots, changed file identity,
replacement library/clip identities, engine errors, another suite or an invented
variant. Existing FX controls and public preview/snapshot collectors still pass.
All72 edit results remain pending actual execution from this source. Root owns
GDScript parsing and public editor tests; the worker ran only pure Python checks.

The remaining uninstrumented inner-history families are presets, graph, rig,
modifiers, motion/setup and sequence. Read/file effects need their own exact
applicable result contracts. Existing native playback adapters and historical
matrices remain separate evidence; no aggregate pass fills these gaps.
