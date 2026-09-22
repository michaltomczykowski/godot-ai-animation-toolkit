# Changelog

## 0.1.0 — unreleased

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
