# Isolated graph and modifier baking

Godot 4.7.2, unreleased branch `repair/toolkit-quality`. Approved contract:
[rig-bake-restoration-plan.md](rig-bake-restoration-plan.md).

**Status: complete 2026-10-08.** Implemented and validated source `e3a9e93` on
the review branch. Broader character/action quality and the remaining repair
roadmap are still open.

## Implemented checkpoints

The public `animation_rig.bake_pose_sequence` route evaluates an unsaved scene
copy, isolates animation and graph resources, remaps dependencies, disables
automatic processing, and captures the final weighted modifier stack. Live
players, trees and spring solver state are never reset or advanced. Custom
processors, expressions and unsupported native configurations receive a typed
`OPERATION_UNAVAILABLE` response. Method/audio/animation-playback tracks are
suppressed and reported. Dry runs and failures free the private hierarchy.

Tree replay starts at zero. `tree_parameters` seeds writable public parameters;
transient requests are cleared. `tree_starts` starts state machines and ordered
`tree_events` applies set/start/travel commands. Event times become sample keys.
Positive event times also receive a sample 40 microseconds before the event,
so an abrupt control change cannot blend backward over a whole frame. Native
key lookup has a relative time tolerance: the gap scales with event times over
one second. The bridge holds the preceding pose instead of interpolating the
jump; this also prevents backward extrapolation near the pre-event key. Sample
spacing at or below 20 microseconds (scaled for times over one second) is refused
with `OPERATION_UNAVAILABLE`; adjust duration, event timing or sampling FPS.
Nested machines use their own playback paths; grouped machines use parent
travel. Native grouped AUTO boundary transitions are refused because they
produce condition evaluation errors in Godot 4.7.2.

Graph sources and sources requiring extraction settings receive a separate,
inactive, manual output player. `output_player_path` can select an existing
inactive, stopped player unlinked from a tree. Creation, libraries, clips,
extraction settings and any carrier belong to one scene Undo action. A compatible
carrier can be reused on overwrite. Changing extraction settings is refused
when it would invalidate another destination clip.

## Movement ownership

| `root_motion_mode` | Result | Playback requirement |
| --- | --- | --- |
| `preserve` (default) | Final bone poses and a separate Skeleton3D motion carrier | One controller consumes output root deltas on the reported movement owner |
| `pose_only` | In-place bone poses | Travel is deliberately omitted and reported |
| `apply` | Final bone poses and movement-owner position/rotation/scale tracks | Output extraction is disabled; the clip owns movement |

For extracted sources, preserve/apply requires `root_motion_target_path`, an
explicit Node3D ancestor owning the selected skeleton. Native deltas move that
owner in the private scene before world-dependent modifiers. Canonical local
extraction keeps the carrier independent from captured root-bone poses.
Mirrored/sheared transforms and competing movement writers are refused.

Preserved nonlooping clips have a **1 ms stationary terminal hold**. Godot clears
root getters when an AnimationPlayer finishes; this hold makes the last moving
interval readable before the finishing tick. `capture_duration` describes the
requested interval, `length` describes the actual clip, and
`root_motion_terminal_hold` reports the extension. Captured key times do not move.

During playback the source graph/modifiers and the baked player must have one
owner for each property/bone. Creating the output does not deactivate the source.

## Local evidence, 2026-10-08

- Four restoration tests reproduce/fix fractional final influence, verify live
  spring continuation at 30/60/120 FPS, evaluate animated external targets using
  actual final delta, and inject a late failure with atomic cleanup.
- Ten graph tests cover 24 native replay cases at 30/60/120 FPS: 1D/2D blends,
  filtered additive, one-shot, TimeScale, inactive/root/nested/grouped machines,
  crossfades and queued travel; twelve typed preflight refusals and played
  regressions for premature parameter blending at 0.07 and 10.07 seconds.
- Five root-motion tests cover 72 native replay cases across all movement modes,
  clip/tree sources, local extraction on/off, loops on/off and 30/60/120 FPS.
  Transformed/scaled characters and parents, turning/scaling travel and a
  fractional world-target look-at are included. Worst played position error
  is below one micrometre; rotation error is below 0.001 radians. Explicit
  destination/carrier reuse/overwrite and five atomic input refusals pass.
  Loop cases cover source clips wrapping during a finite capture; they do not
  guarantee infinitely repeated, world-dependent baked output stays faithful.

- Native modifier coverage includes all eight supported classes at 0/0.5/1
  influence and 30/60/120 FPS (72 cases), both look-at/spring orders (18 cases),
  and a retargeted child with its own fractional look-at stack. Each public bake
  checks dry/write/Undo/Redo, exact source state and one scene history action.
- Fifteen storage cases cover locked instances, editable instances, missing
  libraries, existing local libraries and overwrites. Source files, shared peer
  instances, authored library identity and permissions survive the operation.
- Twenty-seven source configurations compare continued spring/graph traces
  against untouched native controls after dry/write/refusal/Undo/Redo at all
  three rates. External direct calls also compare source poses after a separate
  RPC, covering deferred editor refresh.
- Semantic invalid/empty/nonfinite tracks, animated activation of unsupported
  scripted modifiers, and scripted Animation resources return typed errors.
  Scripted resources are refused before duplication can execute constructors.
  Inspection covers the copied hierarchy and its libraries, so an unsupported
  dependency elsewhere in that hierarchy may also prevent baking.

## Independent saved playback

`check_rig_bake_restoration.gd` imports only a native-engine reference helper.
It requires all **201 case IDs / 603 Do, Undo and Redo states** and plays the
402 generated Do/Redo states in a fresh process. It checks resolved track paths,
native track types, every key time/count, overwritten Undo contents, weighted
bone poses, movement ownership and engine interpolation between reference keys.
Missing cases, captures, reports and engine errors fail the gate.

The current matrix checks **10,764 key samples and 10,362 intermediate samples**.
Worst played reference errors are 0.000001014 m position, 0.000001610 rad rotation
and 0.000000338 scale, inside the required 0.1 mm / 0.001 rad / 0.0001 limits.

Finite sampling remains an approximation of continuous native graph evaluation.
The checker separately reports native motion evaluated with additional midpoint
steps: the worst rotation difference is **0.281967 rad**, a fast one-shot at
30 FPS over 0.100–0.133333 s. This is not a key-fidelity tolerance. It records
native timing/blend changes across different evaluation intervals; increase
sampling FPS for fast actions and review the played output. Instantaneous event
bridges are excluded from this continuous-motion statistic, but their keys and
engine interpolation are still required and checked.

## Visual review

`render_bake_restoration.gd` captures native source and saved public-route bake
side by side, using a fixed camera and native playback with one writer per bone.
The overlay reads final played bone transforms; it does not assign authored poses.
Eight cases cover a state machine, one-shot, fractional spring, reordered stack,
retargeted child, and all three movement modes. The renderer requires **488
frames**, and `compose_bake_restoration.py` creates a video and contact sheets.

Paired contact sheets and representative played frames show matching weighted
orientation, spring curvature and retargeted child stacks. Preserve/apply travel
matches the native source without doubled displacement; pose_only stays in place.
These technical rigs test bake fidelity and travel ownership. They do not approve
the broader humanoid locomotion, action sequencing or flykick visual quality.
Media stays under `bake_restoration_20261007/media` in the persistent recovery
snapshot. No release, tag, merge or media upload is created.

## Closing verification

- Fresh local Godot 4.7.2 editor: **343/343 tests**, zero skips, zero captured
  engine/discovery/route errors, all ten families and 103 dry invocation routes.
- All fourteen headless suites pass. `tier1_proportions` also prints an exit
  warning for ten ObjectDB instances; its assertions pass. This bake matrix and
  fresh saved checker report no engine errors or exit resource errors.
- Fresh visible editor and external MCP client: **24/24 named bake tests**,
  complete 201-case native checker and four direct operations before/after core
  reload. Source poses survive separate RPC refresh; saved outputs reopen with
  all expected resolved tracks/keys. Sessions change from
  `test-project@269b9992a09c60c8` to `test-project@d1fe3262f78bee93`.
- Fixed-camera final-source render: **488/488 frames**, zero render engine errors,
  eight comparison contact sheets and a local video. All eight pairs reviewed.
- Hosted source `e3a9e93`: **all 34 validation jobs pass** in
  [Actions run 37702850985](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37702850985).
  This includes fourteen headless suites on each platform, all four editor/core
  combinations (342 passes, one optional X Bot skip, zero captured engine errors),
  and both complete external MCP routes. Each route passes the 201-case/603-state
  bake gate, retained clip/modifier history, allocation and reload checks, deferred
  source-pose restoration, later-action guard and deferred script-error check.
  The two current-core editor jobs are informational; both also pass.

## Reproduction

1. Run `tools/test_tier1.ps1 -Godot <Godot 4.7.2 console>`.
2. Run a fresh editor with `ANIMATION_TOOLKIT_CI=1` and
   `GODOT_AI_ALLOW_HEADLESS=1`; require `CI_SUITE_PASS` and no engine/route errors.
3. Run `tools/mcp_rig_bake_restoration.py` against a fresh visible editor, supplying
   `--core-root`, `--project-root`, `--session-hint`, `--port`, `--ws-port`,
   `--godot`, and optionally `--record`. It runs six public-route suites, invokes
   the independent saved checker, and calls graph/preserve/pose_only/apply directly
   before and after `editor_reload_plugin`, with dry/write/refused/save/reopen.
4. Run Godot with `--script res://tools/render_bake_restoration.gd -- <frame-dir>`;
   compose with `tools/compose_bake_restoration.py --frames <frame-dir>
   --output <media-dir> --ffmpeg <ffmpeg>` and review the paired captures.

The complete CI route harness expects a headless editor for its 3D-preview
contract. An extra local run against the visible editor stopped at that expected
headless-preview refusal. The dedicated bake/clip gates passed in that editor;
the graphical inspection rerun passed with four PNGs and a valid contact audit.
The complete headless routes passed on both hosted platforms.

## CI infrastructure finding

The graph checkpoint's Linux pinned-core editor job passed 327 tests with no
engine errors but rejected a stale generated operation audit. Its Windows
external route lost the plugin-managed backend after reload when core process
identity discovery failed. The route harness now owns an external backend across
reload, using the supported authenticated adoption/attach path, and captures
both backend/editor logs. Root checkpoint `e7c6fb8` passed all 34 validation jobs in
[Actions run 37695353226](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37695353226),
including complete external routes on Windows and Linux. The expanded closing
matrix subsequently passed on `e3a9e93` in run 37702850985.

Closing source `3126e2d` passed all headless/editor combinations and its new bake
gate on both platforms in Actions run 37701427641. The following retained
clip-history gate failed on both platforms because it required exact orphan IDs
after committing a new action. That commit legitimately frees the previous Redo
branch's detached bake outputs. The same sequence reproduced in the visible local
editor. The assertion now permits freed prior IDs, rejects every new orphan ID,
and requires the resulting exact set for dry/refused calls, matching the retained
bake-state check. Follow-up `e3a9e93` changes only this test expectation and its
evidence; the production addon is unchanged from `3126e2d`. Both complete external
routes pass in run 37702850985, including the sequential bake and clip-history
gates. No new orphan IDs are permitted, and dry/refusal sets remain exact.

Hosted headless `scene_save` also logs a native dummy-renderer thumbnail error
(`texture_2d_get`, null texture) through Godot AI's scene handler. Saved animation
data is checked independently; this renderer/core limitation does not occur in
the visible local capture. It is outside the toolkit's bake sampler.
