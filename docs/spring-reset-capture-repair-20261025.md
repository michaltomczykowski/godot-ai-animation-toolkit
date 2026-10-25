# Deferred spring reset and capture timing

The second five-modifier recording captured all2,400 frames, but its strict
preflight comparison failed.18 of20 runs matched exactly. Only the two active
spring runs differed, at124 intermediate ticks each; sampled inputs, clocks,
configuration hashes, signal counters and final poses matched. The mismatch
included actual bone poses, so relaxing framing or float comparison would hide
it. The complete failed capture and independent leaf-difference report remain.

The [exact Godot4.7.2 spring implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/scene/3d/spring_bone_simulator_3d.cpp)
queues joint-reset work from `reset()`. The render path yields between samples;
the tight headless loop can finish its samples before that queued work runs.

A separate copied-project diagnostic holds original scenes, solver, settings,
stimulus and1/60 step constant. It varies only one process-frame barrier before
sample0 and whether each sample yields.16 runs /256 samples pass with0errors.
Without the initial barrier, paced and tight trajectories differ at ticks1–15,
exactly reproducing both original failed trajectories for the first16 samples.
With the barrier, paced/tight trajectories match every recorded semantic field
exactly; both fresh takes match. No per-sample reset is added.

The shared capture evaluator now settles the deferred reset once before the
sampled clock. Its report explicitly counts that excluded reset frame (one for
spring, zero otherwise), separately from the two loading frames. Strict native
and media admission requires that count.13 offline capture/preparation controls
pass. Full new four-second native and GPU qualification is still required.

Private evidence: `spring-reset-schedule-control-r001/control.json`, SHA256
`0f83828104fc8f0a8d9a07efce8b33cc35cdcf1a419fe689172f9013ddf11761`, plus
`independent-comparison.json`. This is a capture scheduling correction, not a
production modifier/scene change or admission of either old recording.

The new preparation explicitly allows only the previously documented exact
three-line pose_list guard blob pair. It records original/capture Git identities
and refuses that bridge if the changed handler is loaded by any copied scene.
Every other changed production blob is still rejected.

## CI cumulative time budget

An independent log audit of six actual Windows jobs found three cancellations
at the outer25-minute limit while the active180-second gate had used only24–87
seconds. The earlier passing4.2.1 job already took24m16. The unchanged inner
gate limits and observed remaining work require about33minutes in the slow
case. The outer job cap is now35minutes; every individual gate and assertion
remains unchanged. This addresses premature cancellation, not the separate Linux
scene-save SIGABRT. That crash remains open and the native diagnostic mode is
still temporary. Exact timelines and hashes remain private under
`ci-8319413-r001/live-budget-diagnosis-r001`.
