# Active AnimationTree and modifier bake restoration

Approved 2026-10-07. Unreleased branch: `repair/toolkit-quality`. Godot 4.7.2.
Work alone and verify through Godot AI's public custom-tools API.

## Contract

Extend `animation_rig.bake_pose_sequence` rather than adding another operation.
Capture one selected Skeleton3D; selecting a retargeted child captures that
child's evaluated pose. Existing clip parameters remain supported.

Add `source_tree_path` (mutually exclusive with `source_animation`),
`tree_parameters` (writable `parameters/...` overrides), `tree_starts`
(`{playback_path,state}`), and ordered `tree_events`
(`{time,action,path,value/state}`, actions `set/start/travel`). The graph's
linked player must match `player_path`. Replay fresh state from time zero;
never reconstruct the live graph's private crossfade or solver state. Copy
ordinary public writable parameter values at invocation, clearing transient
requests unless explicitly overridden. Address grouped states via their parent.

Add optional `output_player_path`, `root_motion_mode`
(`preserve` default, `pose_only`, `apply`), and `root_motion_target_path`.
Preserve/apply extraction requires an explicit character movement owner.
When source-library changes would disturb a graph or mixer settings differ,
create a scene-owned inactive output player beside the source. Return its real
path and predict the same path during dry run. Explicit destinations must be
inactive and unlinked from an AnimationTree. One scene Undo action owns output
creation, any motion carrier, library changes and the clip.

Validate types, finite inputs, names, states, paths, event order and overwrite
before sampling. Count event evaluations against the existing 1,200-evaluation
limit; preserve approximately 400 bytes of headroom under the server's
8,192-byte custom-tool schema cap.

## Isolated evaluation

Extract a reusable sandbox from the inspection-copy approach: copy unsaved
hierarchy without scripts/signals, isolate mutable libraries/graph resources/
profiles/curves, remap absolute paths, and reject external dependencies. All
animation and modifier targets must resolve inside the sandbox. Run one manual
AnimationPlayer or AnimationTree, with automatic processing disabled. Keep
modifier child order, activation and influence; evaluate retarget dependencies
before target stacks, rejecting cycles or competing retarget ownership.

Never seek/reset/stop/reconfigure live players, trees or modifiers. Initialize
only private stateful solvers. Suppress method/audio/animation-playback tracks
and report exclusions. Refuse custom processing scripts and graph expressions
that cannot be reproduced. Existing native-engine refusals remain enforced.

Append an inert witness after each private stack to capture the final weighted
pose. Compare with skeleton_updated when the pose changes. Real modifier
signals occur before their own influence blend. Capture t=0 after zero-time
initialization, then use actual elapsed intervals, including the shorter final
interval. Remove the old extra modifier step at t=0. Include event times;
advance to each event with preceding controls, apply commands in caller order,
refresh the graph with zero delta, and evaluate modifiers once for the interval.
Missing/nonfinite final capture returns OPERATION_UNAVAILABLE with stage, rig
and sample time. Every failure frees temporary nodes and leaves history intact.

## Root motion

- `preserve`: bone poses plus a separate extraction carrier, required mixer
  settings and movement owner. Encode the trajectory using canonical local
  extraction so captured root-bone poses remain independent of extraction.
- `pose_only`: in-place bone poses; deliberately omitted travel is reported.
- `apply`: bone poses plus character transform tracks, with output extraction
  disabled.

For preserve/apply, consume native position/rotation/scale deltas on the private
movement owner before world-dependent modifiers. Use level-surface movement
without controller scripts/collision response. Reject competing transform
writers and unrepresentable transforms. Return playback ownership requirements;
do not deactivate the source scene to make the output work.

## Required verification

Retain bake-state, clip-history and modifier-history gates. Add named cases for
inactive/playing/crossfading/queued-travel trees; root/nested/grouped state
machines; 1D/2D blends; one-shot/additive/filter/TimeScale; animated targets;
all supported existing native modifier fixtures; 0/.5/1 influence; reordered
stacks and fractional final influence; retarget child stacks.

Check exact public state/resource identity/outside-rig properties immediately
and after deferred refresh. Compare continued graph and spring traces against
untouched native references at 30/60/120 FPS after dry/write/refusal/Undo/Redo.
Cover local/missing-library/overwrite/locked-instance/editable-instance layouts,
automatic storage, saved Do/Undo/Redo states and immutable source/peer scenes.
Test all movement modes, transformed characters, loops, turning and blends.
Late-failure injection must leave zero leaks/errors/history changes.

Fresh-process checkers use independent native playback. At keys require
position <=0.1 mm, rotation <=0.001 rad and scale <=0.0001. Check intermediate
engine interpolation against independently interpolated reference samples;
report approximation against native motion. Required missing IDs/samples/
reports fail validation. Review fixed-camera source/bake comparisons for snaps,
timing shifts, unstable springs and doubled travel. Run Windows/Linux headless,
editor and external-route CI, including direct calls before/after core reload.

## Checkpoints

1. Preserve this plan; reproduce spring momentum loss and fractional capture.
2. Implement isolation, final capture and atomic history.
3. Implement graph replay and automatic output storage.
4. Implement and independently verify all three movement modes.
5. Complete the matrix, previews, docs and operation evidence.

After each verified checkpoint update FIX_ROADMAP, evidence and the persistent
recovery snapshot; commit/push the review branch. No release/tag/merge/media
upload. Broader motion/sequence history and full action quality remain later
roadmap gates.

## Reference contracts

- [AnimationTree ownership](https://docs.godotengine.org/en/4.7/classes/class_animationtree.html)
- [Final modifier timing](https://docs.godotengine.org/en/4.7/classes/class_skeletonmodifier3d.html)
- [Root-motion extraction](https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html)
