# Setup blend phase and FK causality

One bounded Godot4.7.2 headless SceneTree process replayed the four saved public Responsive stationary/extracted setup scenes at60FPS. It tested five original/generated quality specs under the original clock and all four available BlendSpace sync modes:100 plays, zero engine errors. No public writes, source key changes or saved-scene edits occurred. Private raw report SHA256: `442c72ae3b350cb94a6c80d3c6114b6f11f975dd0f7560de7a68758eccc65216`, retained under `private-setup-causality-r001/native.json` in the isolated worktree. The executable measurement helper is `test_project/tools/check_setup_phase_causality.gd`; arguments are the saved setup route and a new report path.

## Observed native behavior

| Rig | Original walk/run penetration | Cyclic mutable penetration | Original normalized phase gap | Cyclic mutable gap |
|---|---:|---:|---:|---:|
| Dummy |77.24mm|18.22mm|0.1878|approximately0|
| X Bot |23.54mm|19.97mm|0.1331|approximately0|
| Short |66.37mm|7.69mm|0.4987|approximately0|
| Tall Z-up |111.63mm|29.21mm|0.4987|approximately0|

Synchronization removes the relative gait phase drift but does not restore contact. Half idle/walk penetration with cyclic mutable remains10.63/10.83/12.62/12.43mm. Jump OneShot penetration is unchanged at24.82/30.82/11.13/54.71mm. The exact walk/run endpoint clips remain contact-valid. NONE and INDEPENDENT reproduce the original measured intermediate failures. CYCLIC_CONSTANT remains at phase0 under this graph's current controls and fails progression/root-distance checks; it is not a valid drop-in clock setting.

Nonlinear FK blending is independently demonstrated. At the dummy synchronized walk/run worst sample, original saved walk phase0.316996623 and run phase0.307376819 have the same normalized cycle phase. Their independently played left ankle heights are approximately-0.013mm and-0.200mm. The mixed rotational FK ankle penetrates18.22mm. The endpoint position of a quaternion-blended chain therefore differs materially from the weighted source endpoints. The helper seeks each original saved clip in a separate native instance at the actual contributed phase; it does not synthesize a pose or use generation math.

## Why not change sync alone

Cyclic mutable also changes extracted speed. Dummy half idle/walk has1.23096m endpoint error over6s; walk/run midpoint has0.051404m error. Exact single-clip endpoint errors remain around5e-6m. The3s idle and1s walk timing mixture changes cycle rate, even though the requested speed parameter is unchanged. A sync-only production patch would break the direct speed/root-consumer contract. Adding a TimeScale/phase-speed controller would broaden runtime coupling and is deferred.

The dummy OneShot's worst contact penetration occurs at checker time1.1s, actual Shot phase1.083333s, during fade-out: both feet are declared planted but penetrate approximately24mm. Changing base gait synchronization does not repair the idle/jump quaternion mixture.

## Bounded next prototype

Keep the original independent clock and single root consumer. Prototype a setup-only post-Tree SkeletonModifier3D using current FK ankle targets clamped to the measured world plane, world stance anchors from actual weighted contact declarations, measured two-bone geometry and stable knee planes. Change only thigh/shin/foot rotations; preserve foot world orientation, hips, upper body, bone positions, rest and keys. Report unreachable targets and residuals explicitly. Capture every measured modified pose inside `modification_processed`; later restored pose reads are invalid. Run all60 saved plays plus a bypass control reproducing the36 original contact failures with unchanged contact, velocity and reach bounds. Production wiring and independent visual assessment remain separate decisions after prototype evidence.
