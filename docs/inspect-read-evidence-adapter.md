# Inspect read evidence adapter (2026-10-17)

Bounded offline implementation at base 233ad02853e74cbd21327954fe4f2086c34faf1d.
No addon, fixture, golden, Godot process or public endpoint was changed/run.

`mcp_inspect_audit.py` now emits one raw `inspect_read_v1` snapshot assertion
for each describe/timeline/audit/compare/stats/motion_report/dry_run/help row.
The collector dispatches these to `operation_inspect_checks.py`, which
recomputes the planted response predicates and verifies exact actual public
operation/support request, response, scene, chronology and source dependencies.
Returned public_case_ids identify read/refusal/baseline/after/forced-open events.
The fixed fixture oracles are authored walk 0 -> 100, two walk keys, five clips,
12 keys, a >=99 seam, retime 1 -> 0.5 and the explicit 20 edit operation names.
Compare additionally requires exactly one changed Character:position track,
two keys per side, one changed key and max_delta=100; a generic change flag fails.
Existing operator assertions/thresholds are preserved or strengthened.

Exact negative request codes: describe/audit/stats NODE_NOT_FOUND;
timeline/compare/motion_report/dry_run INVALID_PARAMS; help VALUE_OUT_OF_RANGE.
Unrecognized uppercase strings do not qualify.

Scope: source_unchanged establishes equality of the successful raw walk timeline
before the valid call and after it, before the negative call. It does not prove
all clips/live poses, failed-call invariance, file or history invariance.
reported_errors remains pending without complete engine logs. No visual/playback
claim. Actual fresh public traces/CI at the integrated source remain pending.

Offline validation: 10 adapter tests pass (eight valid rows, inert responses,
wrong effects/refusals, changed walk, missing call/dependency, wrong request,
forged assertions and generic changed flag); existing 15 collector tests pass.
Python: G:/godot-ai-dev/godot-ai-v4-animation/.venv/Scripts/python.exe,
FastMCP 3.4.7. Tests synthesize public-shaped events and do not qualify runtime.
