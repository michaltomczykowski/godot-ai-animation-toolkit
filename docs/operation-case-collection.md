# Actual operation-case collection

This is the first, conservative collector increment. It emits exact successful
public invocation cases, **not** complete release qualification. Static driver
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

Seven tests cover successful exact operations, dry/refused/empty results,
normalized nested routing, unknown/wrong-family/suite-total non-inference,
changed dependencies, wrong operation/context/duplicate events, and advisory
core identity. No editor, MCP session or engine launch is needed by these tests.
