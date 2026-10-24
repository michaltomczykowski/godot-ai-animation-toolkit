# Repair grounded character setup playback

## Observed failure

The first ordinary Responsive group generated four bundles through released
Godot AI4.2.1 on Godot4.7.2. Dry run, external Undo/Redo, save and forced reopen
pass. The saved native Tree has one active mixer and correct translation
endpoints, with zero engine errors.60 native plays produce36 contact failures:
both intermediate speed blends and the jump OneShot, on all four rigs at all
three frame rates. The24 exact walk/run endpoint plays pass.

Dummy60FPS penetration reaches approximately11mm for half idle/walk,77mm for
half walk/run and25mm during jump handoff. Limits stay1% leg penetration and
min(2% leg,3cm) stance slide. Evidence is preserved under the local release
root's `setup/candidate-r001/responsive-extracted-stationary-no-turn`.
Generation source is `b6ea09fd9a4f0c15a9b1439b6da24246f2d3e26d`.

## Bounded implementation sequence

1. Reproduce the failure from the saved scenes. Record actual blend weights,
   native clip phases, contacts and resulting foot transforms. Distinguish phase
   mismatch from nonlinear FK rotation blending. Test any timing hypothesis in
   isolated scene copies without changing saved animation keys.
2. Prototype a setup-owned grounding correction only if native blending cannot
   preserve the floor. Use Godot's post-playback SkeletonModifier3D contract,
   measured leg geometry, stable knee poles and reachable world-space targets.
   Read actual Tree phases/contact annotations, retain stance anchors and keep
   swing feet above the level plane. Report unreachable targets; do not silently
   approve clamped feet. Preserve foot orientation and the existing upper body.
3. Keep standalone clips and accepted fixtures byte-identical. A runtime helper,
   if needed, belongs to the toolkit and must save/reopen as an owned node in
   the same setup Undo transaction. It operates only with its bound Tree and
   never adds another root translation consumer or AnimationPlayer bone writer.
   Validate roles, axes and paths before committing. Existing unrelated modifiers
   must have explicit ownership/order handling.
4. Extend the native checker to capture modified poses inside
   `modification_processed`; reading a later restored pose is invalid evidence.
   Keep the original failed baseline. Add controls for a missing/disabled or
   incorrectly bound correction, bad targets and competing ownership. Require
   the unchanged contact, reach, finite-pose, velocity and knee continuity gates.
5. After the isolated prototype passes, integrate and restart the real editor.
   Reuse completed public rows only when exact dependencies/requests match;
   otherwise preserve them and generate fresh. Complete Responsive24 bundles,
   then the five-style120-bundle matrix including both turn choices and the
   three supported translation/jump variants. Check actual intermediate blends,
   OneShot displacement and recovery,30/60/120FPS, transforms and the runnable
   controller example. Record continuous output and assess it independently.

If a concrete configuration cannot satisfy these contracts, return a narrow
typed unavailable reason before writes. Do not waive the failed contact checks
or describe correct translation endpoints as complete setup quality.

Godot4.7 references: [SkeletonModifier3D timing and signal](https://docs.godotengine.org/en/4.7/classes/class_skeletonmodifier3d.html),
[Skeleton3D pose space](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html),
[BlendSpace1D](https://docs.godotengine.org/en/4.7/classes/class_animationnodeblendspace1d.html).
