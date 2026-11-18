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

## Fresh public and unchanged-source gate: passed

Producerb5928a083b40dffa5e8d90969907a6bd8bd2464f has identical production addon
blobs to7e1db27. Official4.7.2, released Godot AI4.2.1, visible Windows editor.
spring-bake-public-r001 preserves the first failed public playback comparison.
All six public suites passed, but ordered look/Spring native reset retained old
Verlet state, with first-sample error.02999985rad. Restoring source poses did
not help: three-case before/restore controls both51failures and no changed warm
input poses. A separate native API control reapplies unchanged mutable-bone-axes
value, then calls reset: all three cases pass below7.90e-7rad. This independently
marks native simulation state dirty without the production cache helper.

The native references and unchanged-source observer use that explicit reset
contract; no numeric setting value, pose or clip is changed. The observer records
the contract. Fresh public r002 completes all six suites in67.03seconds,201cases,
603saved/402played states,10764key/10362intermediate samples, zero failures or
engine errors. Worst position1.014e-6m, rotation2.467e-6rad, scale3.372e-7.
All four direct calls before and four after actual core reload pass; sessions
validation@494680395455354e and validation@5e5ed71107ef2d56. Public quit and
strict collection complete, zero derived failures. Full native report/log now
survive failures; the21-case regression is added to Windows/Linux editor CI.

Private bake-eight-current-preflight-r004 copies only exact fresh public saved
scene bytes and bound production helpers. No Native.replace occurs in playback.
Eight cases/source+redo/two takes produce32runs,16parity pairs and16fresh-take
checks, all pass. Worst position5.365e-7m, rotation9.089e-7rad, scale2.385e-7.
Original.0001m/.001rad/.0001scale limits remain. Both Spring families now pass.

| Receipt | SHA256 |
| --- | --- |
|spring-cache-repair-r003/native.json|b8e474eef370270e1a33a49b054dcdcb7fd8278d869b2edd668183e6d8ad461f|
|spring-bake-public-r002/operation-case-results.json|71ec195bdacf2b6fce73f116d8fb540bbd84f0272caeb80251048166be4eca8a|
|bake-eight-current-preflight-r004/native-eight.json|9b564f0c47fe5d0007450e4fffb6e7990770c9c6e234f59d55432af10b421d88|
|bake-eight-current-preflight-r004/native-eight-comparison.json|9aa15040f95c2d1f02ffa4cfc301617b360cd44e18fe11bca790cefe83765154|

Phase1 local correctness gate complete. This does not approve workflow footage,
Linux stability, final four-cell qualification or publication. The official Linux
blocker remains; independent motion-intent phase3 is next.
