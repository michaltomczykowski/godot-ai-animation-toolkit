# Broader setup matrix: Windows receipt recovery

Actual first attempt:233ad02, Godot4.7.2, released core4.2.1. Private evidence:
`E:/GodotAI-toolkit-release-2.0.0/20261014/setup/production-r004`.

Three complete public groups and three rig cases in the fourth are retained:
15 passing rows, including four explicitly reused from the earlier first group.
The next Z-up case stops after its read-only profile call when atomic replacement
of route.json raises Windows error5. Its staged complete temporary file and
all preceding snapshots/calls/logs remain. No product animation failure is
inferred from this receipt I/O failure. No native matrix run was started.
All owned Godot processes exited; no editor was left running at inspection.

## Repair and verification

Windows readers/scanners can temporarily deny delete sharing on a destination.
The exact reader responsible for the historical failure is not established.
`review_receipts.write_json` now retries only replacement of the same completed,
flushed temporary file, for Windows errors5/32, with eight bounded attempts
and at most1.275s of total pauses. It never repeats a Godot/MCP operation.
Other permission failures propagate immediately. Persistent locks retain the
old complete destination and new complete staged file, and still fail.

Four controls pass, including an actual Windows handle denying delete sharing,
released after75ms. Other controls require identical staged bytes across retries,
bounded persistent failure with both versions retained, and immediate propagation
of unrelated permission errors. CI runs them on Windows and Linux; the actual
Windows handle control explicitly skips on Linux. Three existing setup wrapper
controls also pass. No numeric animation threshold changed.

## Resume policy

Use a fresh output/APPDATA directory and fresh editor/backend. The existing
public matrix client reuses only completed rows whose exact production dependency
map, request and actual saved-scene SHA match. Its previous source/response path
remains linked. The prior613 production dependency hashes match; receipt/test
instrumentation changes do not alter production output. Partial rows are
regenerated as new cases with new scene paths; old data is never overwritten.

The next run first exercises the new graph and modifier history hooks and eight
inspection read predicates through the real public API. Native modifier playback
and the30group setup playback matrix run serially after public editor shutdown.
Fresh source/scene/call/native provenance remains required; prior successes are
not relabeled as new invocations or full candidate qualification.
