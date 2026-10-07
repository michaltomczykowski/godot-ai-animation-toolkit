# Isolated graph and modifier baking

Godot 4.7.2, unreleased branch `repair/toolkit-quality`. Approved contract:
[rig-bake-restoration-plan.md](rig-bake-restoration-plan.md).

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
- Nine graph tests cover 24 native replay cases at 30/60/120 FPS: 1D/2D blends,
  filtered additive, one-shot, TimeScale, inactive/root/nested/grouped machines,
  crossfades and queued travel; eleven typed preflight refusals.
- Five root-motion tests cover 72 native replay cases across all movement modes,
  clip/tree sources, local extraction on/off, loops on/off and 30/60/120 FPS.
  Transformed/scaled characters and parents, turning/scaling travel and a
  fractional world-target look-at are included. Worst played position error
  is below one micrometre; rotation error is below 0.001 radians. Explicit
  destination/carrier reuse/overwrite and five atomic input refusals pass.

Full saved playback, modifier/continuation matrix, fixed-camera review and final
hosted Windows/Linux gates remain required for checkpoint 5. These local tests
do not approve broader character/action visual quality.

## CI infrastructure finding

The graph checkpoint's Linux pinned-core editor job passed 327 tests with no
engine errors but rejected a stale generated operation audit. Its Windows
external route lost the plugin-managed backend after reload when core process
identity discovery failed. The route harness now owns an external backend across
reload, using the supported authenticated adoption/attach path, and captures
both backend/editor logs. Hosted verification is required before claiming this
gate repaired.
