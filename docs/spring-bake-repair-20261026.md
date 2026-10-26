# Spring bake repair: native regression checkpoint

Phase1, official Godot4.7.2.stable.ed1daf0bf on Windows. Production repair
source7e1db276a06699b60661234d954b3da78e63e012. No release approval.

## Findings and changes

The original synchronous copy retained default native joint caches rather than
the authored global settings. Public joint setters now initialize four scalar
fields, damping curves, gravity direction and axis on private copies only.
Animated global scalar settings are propagated before each solve.

The first21-case oracle also advanced deferred skeleton updates during frame
waits, then explicitly solved again. An individual-settings case bypassing the
repair isolated this reference error: all tight one-solve schedules agree
exactly, while paced schedules differ. The regression now checks exactly one
raw Spring evaluation per sample. Animated expected joint caches come from a
separate native configuration rig, without the production helper or duplicated
curve arithmetic.

That correction left six failures, all unrestricted-axis cases. Exact engine
source shows reset queues marking simulation state dirty. Other axis setters
already mark it synchronously; unchanged ALL did not. The sampler now marks
initial state dirty through the public joint-axis setter once before reset.
It avoids repeating this during samples, retaining accumulated momentum.

## Actual results

| Immutable private run | Result |
| --- | --- |
|spring-cache-repair-r001|Original reference:21 trajectory failures; initial configuration assertions pass.|
|spring-cache-schedule-r001|Seven individual60 scheduling controls; tight private/native exact; paced double-solve mismatch.|
|spring-cache-repair-r002|Corrected oracle:15pass,6ALL-axis failures; exactly one solve per sample.|
|spring-cache-repair-r003|Repaired startup:21pass, zero measured position/rotation/scale difference, zero engine errors.|

All run directories are under E:/GodotAI-toolkit-release-2.0.0/20261014.
R003 covers five axes and damping curves, individual configuration, animated
stiffness/drag/gravity/radius, and30/60/120FPS. Unprimed negative controls
reproduce the defect; source-state preservation and typed single-joint-curve
refusal pass. Each copied project records exact source/archive/file hashes and
bounded engine PID/log receipts. Previous failures remain intact.

## Remaining gate

Run fresh public201-case bake/history/reload checks through Godot AI, then the
eight unchanged-source comparisons. This native regression does not approve
saved public bakes, workflow footage, Linux stability or publication.
