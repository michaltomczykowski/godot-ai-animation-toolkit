# Rig bake playback-state checkpoint

Unreleased branch: `repair/toolkit-quality`. Engine: Godot 4.7.2.

## Reproduction and repair

The public Godot AI dispatcher reproduced six failures in seven playback-state
cases. Baking and dry runs assigned a source to an unassigned player, lost paused
time, cleared queued animations, reset custom speed and changed reverse playback
to forward playback. A stopped player passed after correcting the fixture's
attempt to read a getter which requires live playback data.

`bake_pose_sequence` now samples with a temporary manually processed player.
It uses the original root, animation libraries, discrete/deterministic settings
and root-motion settings. The author-owned player is never played, sought,
paused or stopped. The sampler is freed before the clip commit, including the
missing-modifier-capture failure path. Overwrite refusal occurs before sampling.
Seeking uses `update_only` to sample properties without method/audio/playback
events. Source and retarget poses retain their existing restoration path.

Native Undo then reproduced an additional editor cache effect: removing the
baked position channel reset an unkeyed source bone position to rest after the
clip was removed. The source pose is now part of the same clip history action,
restored after the library mutation on Do/Undo/Redo. Visible Ctrl+Z and
Ctrl+Shift+Z both pass through the external MCP checks of clip data and pose.

This follows the playback contracts for
[AnimationPlayer](https://docs.godotengine.org/en/4.7/classes/class_animationplayer.html)
and the manual processing/root contracts for
[AnimationMixer](https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html).
Reconstructing private playback state from playing speed would lose information
when paused or at zero speed scale; the repair leaves that state in place.

## Checkpoint gates

- Eight public-route cases: unassigned, paused, stopped, playing, reverse,
  zero speed scale, a different current source, and a playback section.
  Dry/write/refused/Undo/Redo must preserve queue, current/assigned names,
  time, speed/direction, section and original source pose. The zero-scale case
  temporarily reveals the hidden custom multiplier in the fixture and restores
  the zero scale. Precise orphan IDs must remain unchanged after each tool call.
- Each case checks exactly one scene action, typed overwrite refusal, original
  named-library identity and generated clip identity on Redo. Authored sample
  values are checked independently against the known 0.6 radian source motion.
- Sixteen Undo/Redo scenes are checked by a standalone fresh Godot process.
  It resolves every generated track, verifies the original persisted source pose,
  and plays the baked motion at keys and intermediate times. It does not import
  the handler, clip-spec helpers or test suites.
- The final local editor suite passes **286/286**, with zero captured engine or
  tool-route errors. Five existing warnings are reported separately.
- The new external `rig_bake_state` gate requires all eight named cases with
  assertion minima (35 each, 40 for zero-scale) and all sixteen runtime states.
  The complete fresh-editor external route passes all **107 gates**, including
  core reload, the retained 96-state pose/chain gate and the 16-state bake gate.
  That complete route preceded the pose-history follow-up. The final follow-up
  passes the fresh editor suite (286/286, zero captured errors), the external
  eight-case/16-state bake gate, and native Undo/Redo. Hosted CI will repeat the
  complete route on the pushed source; its results are recorded after completion.

The original fixture read section/time getters on unassigned/stopped players.
The corrected fixture skips those getters. Getter diagnostics from the initial
fixture are preserved in raw logs rather than counted as handler errors.

## Remaining work

This covers playback-state preservation for one rig writer. All eight clip
writers still require the five-layout library/instance history matrix. Active
graph and complete modifier/retarget-stack bake restoration remain open,
including stateful modifier internals and animated properties outside the rig.
Full modifier history and motion/sequence histories remain later checkpoints.
This checkpoint does not approve visual quality or mark an operation verified.

Recovery: `F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/rig_bake_state_20261006`.
