# Changelog

## 0.2.0 — unreleased

- New `float` preset: 3D bob through the target's transform (rise + scale +
  optional turn); refuses `loop_mode="linear"` like `drift` (the clip ends at a
  net offset).
- New `stagger` op: reveal an ordered list of targets in **one clip** (one
  track per target, key times offset by `stagger`, one undo action) with
  `fade_in` / `slide_in` / `pop_in` effects, from `target_paths` or the editor
  selection (`use_selection`).
- The `showcase` op now also builds a small 3D island (camera, light, cube) so
  the `float` preset is demoed; `test_project/showcase.tscn` regenerated and the
  README GIF re-recorded.
- Tests: 27 editor rows (6 new) + 40 tier-1 checks (10 new).

## 0.1.0

- Initial release: `animation_presets` custom tool with seven ops —
  `pulse`, `bounce`, `orbit`, `sweep`, `drift`, `spin` (3D quaternion turn),
  and `showcase` (builds a runnable demo of every preset).
- Each preset commits one scene-pinned undo action; Control `pivot_offset`
  recentering rides the same action for `bounce`/`sweep`.
- Self-contained implementation: depends only on the Godot AI custom-tools
  registration API.
- Tests: 21 editor-suite rows + 30 headless tier-1 checks; CI runs the tier-1
  checks on Linux and Windows and the editor suite headless against a pinned
  Godot AI release (plus informational `main` drift detection).
- Docs: tool reference, recipes → preset mapping, and two demo GIFs
  (`docs/images/`); `test_project/showcase.tscn` is the committed demo output.
