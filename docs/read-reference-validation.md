# Read reference implementation and handoff

Base: `54744b138f0767da317f0f4eeac90e58cf478768`. Isolated worktree: `E:/godot-ai-dev/toolkit-read-reference-20261024`.

## Implemented

The original eleven inspect read requests and their refusal requests execute once each. When operation tracing is enabled, selected public `test_run` begin/end calls capture an editor logger and a complete stored scene/resource graph around each original call. The strict adapter joins actual helper and operator spans, request, scene, source hashes, context, token and exact refusal code. Both valid and refusal observations are required for source/error checks.

The sample and motion_audit references use a fresh committed public fixture in the same editor and native manual AnimationPlayer clocks. Independent Python reconstructs sample coordinates/contact windows and audit metrics/budgets from raw native bone positions. No production sampling/grading helper or generated response keys supplies expected numbers. No fixture, production addon, request, or existing threshold changes.

## Offline validation

- 10 witness/adapter controls passed, including missing/duplicate calls, wrong source/span/token, typed errors, state/history/file/resource mutation, missing references, inert/wrong-value clocks and wrapper no-retry behavior.
- 6 numeric reference controls passed, including hand-calculated expected values, each report metric group, nonfinite/inert references and unchanged physical thresholds.
- Existing bounded/library read controls: 18 passed; existing inspect controls: 14 passed.
- Changed Python modules compile; `git diff --check` passes.

## Integration

Apply the source commit on base54744b1 (or cherry-pick after resolving only the nine-line collector dispatch addition). `docs/read-reference-collector.patch` contains that minimal collector dispatch against the base. Do not apply the patch twice. No CI YAML change is required: existing inspect driver invocations receive the trace environment and discover the helper suite. Existing test timeouts are unchanged and their runtime adequacy remains unmeasured.

Root must parse the three new GDScripts with Godot4.7.2, then run the actual public drivers and operation collection on fresh evidence. Ordinary editor test discovery skips the two instrumentation tests without their exact active marker. These skips are not operation proofs. No second engine, live public invocation, native execution, rendered verification, or CI qualification was performed by this worker.

## Conservative limits

`source_unchanged` covers the observed stored node/resource graph, skeleton rest/pose, readable Player state, history versions and captured relevant files across both calls. Unsupported/unreadable state remains pending; engine internal caches and unrelated editor/session state are outside the claim. A paused/stopped Player position that cannot be read leaves the proof pending.

`reported_errors` concerns only the actual logger interval and separate native reference logger. Exact observed typed refusals remain independently bound; empty suite totals cannot pass this check.

Numeric comparisons remain pending when reference eligibility or raw observations are missing. Fresh-engine rounding/root-extraction compatibility and helper runtime cost are unexecuted risks; preserve actual failures instead of relaxing budgets. The fixtures are historical synthetic public test scenes, and this evidence makes no physical, audible, rendered, or visual qualification claim.
