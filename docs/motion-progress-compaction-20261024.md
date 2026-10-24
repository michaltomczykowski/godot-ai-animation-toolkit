# Compact repeated motion native progress

Windows/core4.2.1 CI40071944104 hit the existing420second parent timeout at
reconnect_start405.427seconds. All four before_reload direct cases had completed;
the actual273-case/819-state/2457-play native result passed its unchanged gate.
No after_reload case started, and no completed final gate receipt exists.

The raw progress file was211,582,290bytes; timeout metadata223,731,725bytes.
progress() retained the new full native_cases/plays payload and rewrote it on every
subsequent phase. Repeated~7.3second gaps align with this serialization; that timing
was inferred from actual phase events, not independently profiled.

The bounded fix writes the exact native result JSON payload once, exclusively, to
<attempt>.native-runtime.json after the existing native gate succeeds. Repeated
progress contains only scalar counts, evidence/manifest identity, empty validated
error lists, full artifact path/bytes/SHA and the actual raw native event ID. Native
stdout/stderr still enter the unchanged raw collector event, and runtime() still
returns the entire unchanged report for the final evidence artifact. Every native
case, play, source binding and diagnostic remains in that full evidence. Failed
native subprocesses/errors are recorded raw and refused before compaction; earlier
artifacts cannot be overwritten. No new per-operation pass is inferred.

420second aggregate,240second native, client/readiness limits and actual public
calls are unchanged. Fresh CI must determine whether removal of repeated overhead
is sufficient; this patch is not a timeout-pass waiver. Six focused controls pass,
including large payload bounds, full hash/readback/immutability, native failure
retention, actual driver command/240limit and unchanged420timeout preservation;
three existing gate diagnostics controls also pass. All subprocesses were mocked.

Separate residual:84headless editor ERROR: Parameter "t" is null messages came
from dummy texture_2d_get through core save_current_scene. The independent native
process's engine_errors=[] does not make the whole editor log clean. These errors
are not erased, repaired or relabeled by progress compaction.
