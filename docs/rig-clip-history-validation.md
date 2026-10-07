# Rig clip history checkpoint

Engine: Godot 4.7.2. Unreleased branch: `repair/toolkit-quality`.

## Matrix and playback contracts

All eight advertised clip writers use Godot AI's public dispatcher:
pose_to_clip, walk_cycle, idle_breathing, blink, jumping_jack, squat, punch and
bake_pose_sequence. A separate 2D pose_to_clip case brings the matrix to
45 writes across local, overwrite, missing-library, locked-instance and
editable-instance layouts, and 90 saved Undo/Redo states.

Each fixture has a custom player root, named source library, unrelated clip
and another player. Authored metadata, rest/pose values, ownership, instance
permissions, source/peer isolation, exact resource identities and paused
playback state are checked. Dry/refused calls cannot allocate orphan nodes,
change properties or history. Successful writes require exactly one scene
action and zero global actions. The operation registry must match the inventory.

Standalone fresh engines import no handlers/spec builders or test suites.
They resolve every track and play keys and intermediate values against authored
expectations: pose rotation, walk stride/bob, breathing/head counter motion,
blink scale, raised arms/lift, held-squat depth and ankle contacts, alternating
punch extension, and baked source transforms. The overwrite Undo state plays
the original clip. These are reliability checks on controlled rigs; they do
not approve arbitrary rig compatibility, level-surface motion or visual quality.

## Reproduction and repair

The matrix initially passes after correcting its locked-instance fixture:
source pose and speed must be authored before packing; transient seeks and
settings on a locked instance cannot be assumed to persist as overrides.

Native Godot Ctrl+Z then reproduces an additional defect: removing a blink
scale clip resets an unkeyed source bone's authored scale to rest. Synchronous
Undo checks missed the later editor cache invalidation. The bone pose is now
restored after the library mutation in the same history action. The shared
procedural writer and both 2D/3D pose clip writers use this path; bake reuses it.
2D snapshots preserve the complete Bone2D transform, including scale/skew.

A stricter Do check then exposed another deferred refresh: adding the blink
clip reset scale even though Undo/Redo passed. Bone pose entries now opt into
one restoration queued after the earlier editor refresh. It requires the same
edited scene and history version, and a latest-request ticket prevents an
older Do/Undo from winning after multiple actions in one frame. Later scene
actions, freed/detached nodes and script-swap quiescence cancel the restoration.
An initial freed-node assignment error was caught in the post-test editor log;
validity is checked before converting that Variant to an Object.

The visible 4.7.2 editor now passes strict source-pose preservation on Do,
native Undo and native Redo for blink, 2D pose-clip overwrite and bake.
An actual public batch (aggregate undo disabled; both writers still own their
scene actions) adds blink then applies a different pose: both calls succeed
and the later position survives the queued restoration. The first batch probe
was refused because the mixed family does not advertise aggregate batch undo;
that refusal is retained, and is not a pose-restoration failure.

CI requires all three post-refresh source-pose checks and the later-action
guard. It also fails on script errors in the complete external editor log,
including deferred errors outside the synchronous suite's logger lifetime.

After the freed-target guard repair, a fresh editor regression passes 292/292
with zero captured engine/tool-route/discovery errors and no script errors in
the editor log. All fourteen headless suites pass on this source.

## Evidence and remaining gates

Initial external route passes six exact named tests and 90 fresh-engine states.
Baseline native blink failure is retained in `rig_ui_blink_undo_20261006.log`.
Final source passes the external matrix before and after core-plugin reload:
six exact named tests, assertion minima 441/450/414/495/495 plus the registry
check, and all 90 independently played states. Visible native blink and 2D
pose-clip overwrite Undo/Redo preserve clip data and source pose. The fresh
editor regression suite passes **292/292**, zero captured engine/tool-route or
discovery errors, with five existing warnings recorded separately. All
fourteen headless suites pass. The complete route passed 108 gates before the
deferred follow-up. The fresh complete route on the guarded source passes
**113 gates**, including core reload, the six-case/90-state matrix, retained
bake-state checks, all four post-refresh pose checks and zero deferred script
errors. Hosted Windows/Linux results for the new commit are pending.
No operation is marked fully verified.

Recovery: `F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/rig_clip_history_20261007`
contains source, baseline/proof logs, 90 saved states, 18 instance-source scenes
and native UI records. Its `next_phase_plan.md` details modifier allocation,
history/evaluation and bake-stack restoration before implementation.

Active AnimationTree/stateful modifier bake restoration, modifier history and
evaluation, motion/sequence history and fixed-camera visual review remain open.
