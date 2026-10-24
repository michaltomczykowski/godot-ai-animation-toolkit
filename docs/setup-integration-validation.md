# Setup integration repair, 2026-10-14

Implementation is isolated from approved standalone generation. Setup forwards only supplied numeric controls into the shared resolver. Omitted run speed/cadence and jump geometry remain rig-relative. The intentional setup jump duration is1.2s. Explicit timing/speed/geometry remain exact or receive typed refusal. Solved walk/run speeds must satisfy0<walk<run before the scene transaction.

Setup selects internal90-degree pivot stages from the requested angle (180 means two); the existing1..8 step bound and reach/timing refusals apply. There is no setup steps parameter. Optional turn is a generated, unwired skeletal clip; actor-yaw extraction is false. This does not provide an actor-yaw handoff controller.

Forward setup jumps now use the graph translation track, with the same terminal endpoint hold as dedicated extraction. Results identify capture duration, actual length, hold, root owner path, jump/turn wiring and per-clip stages. The generated snippet and examples/setup_translation_consumer.gd manually advance one Tree and apply one translation delta in the owner's parent coordinates. Forward jumps in that example start from idle. Scene movement, collisions, intermediate-speed contact and OneShot displacement require public native qualification; source parity is not a substitute.

## Isolated validation

Godot4.7.2, released core4.2.1. `tier1_setup_provenance.gd` checks omission/provenance, explicit mappings, numeric/nonfinite refusals, internal stages and compilation of both returned snippets and the runnable example.

The opt-in `test_project/addons/setup_integration_ci` plugin runs the focused editor suite when SETUP_INTEGRATION_CI=1 and enabled in the isolated project's plugin list. Ordinary full-suite discovery also includes test_setup_integration.gd. Final r004 raw log remains local at G:/godot-ai-dev/toolkit-release-setup-20261014/setup-integration-r004.log: three passed fixture tests,1365 assertions, zero failed; five styles each on dummy, short, tall Z-up. Dedicated idle/walk/run/jump/two-step180 authored clip/marker parity, explicit forward-jump controls/terminal hold parity, explicit run/turn/jump durations and five nonmutating refusal cases per style pass. Private X Bot and external public witness are two explicit skips. Root must run those on its public fixture set.

The public witness expects a scene child PublicSetupIntegration with player_path and clip_pairs metadata. It only inspects actual clips previously written by the external public client. It does not call handlers or establish history/save/reopen by itself.

## Retained failures and limits

Initial focused test refused180 degrees because setup did not select internal steps; fixed without altering standalone turn. An initial combined-fixture test used skip inside a matrix, which marked the entire test skipped when X Bot was absent; split into distinct fixture tests. The initial --editor --script SceneTree harness emitted editor shutdown RID/ObjectDB leak errors despite source assertions passing. Replaced by opt-in EditorPlugin harness; r004 exits0 with no engine errors/warnings. r003 log remains local. The temporary project plugin enablement was restored to its original bytes; protected fixture files are unchanged.

Pending: X Bot, public Godot AI histories/save/reopen, live reload, actual30/60/120 FPS extracted Tree jump displacement and OneShot blending, intermediate blend contacts, transform/refusal matrix, continuous independent visuals and exact-candidate full gates. No public/playback/release completeness is claimed by these focused checks.

## Transform follow-up

MotionSpace.geometry checks effective skeleton geometry without assuming world Y. Rotations/translations and positive uniform scale are supported; nonuniform, reflected, singular or sheared effective geometry receives typed refusal before history/scene writes. Root extraction also refuses a top_level descendant that breaks owner-to-skeleton spatial inheritance. The translation delta uses the skeleton-to-owner-parent basis; the consumer applies it directly to owner.position. Adding owner.quaternion again is wrong for a translated-only root track. [Godot's AnimationMixer implementation](https://github.com/godotengine/godot/blob/4.7-stable/scene/animation/animation_mixer.cpp#L1192) only inverse-rotates root displacement when a rotation track exists on the extraction path. Toolkit root tracks are translation-only; the native probe independently confirms the behavior.

Explicit consumed metre/m/s controls divide the effective uniform world scale before solving; returned speed, distances and metric diagnostics multiply that scale. Defaults retain their rig-relative recipe and provenance. Internal prepared references keep local metrics to avoid double conversion in start/stop composition; conversion happens at public results. Exact scale1 and identity delta mappings avoid changing approved authored values. Results report world_scale and root_motion_space.

`tests/tier1_motion_space.gd`:26 checks pass, including nine native translation plays at30/60/120FPS through rotated/translated nested parents at scales0.5/1/2. Explicit control mapping, default/angular preservation and typed geometry checks pass. `tests/test_motion_transform.gd` validates production walk0.18m/s and forward jump0.2m on rotated/nested shortY-up and tallZ-up fixtures at scales0.5/2, plus scene/history/binding/pose refusal atomicity. The final follow-up log is motion-space-editor-r004.log. Accepted walk/run/idle golden regression has drift0; motion-space-golden-r001.log includes four passing tests/19 assertions. Repeated setup authored parity stays1365 assertions with private/public witnesses pending.

Retained follow-up failures: tier1r001 had a test-label formatting error (`%g` unsupported), fixed and guarded by engine-error capture in r002. Editorr001 had a test type-inference parse error and its isolated process was stopped; r002 tried writing jump while its test player was running and correctly received OPERATION_UNAVAILABLE. The test now stops playback before authoring. No production guard was weakened. All logs remain local in the isolated worktree. Protected fixtures and original project plugin configuration remain intact.

Public saved-scene/Tree playback and complete compatibility/visual gates remain pending root integration; these direct-handler source tests do not establish public-route coverage.
