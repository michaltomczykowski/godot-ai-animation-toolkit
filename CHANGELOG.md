# Changelog

## 0.1.0 — unreleased

- Initial release: `animation_presets` custom tool with five one-call presets
  (`pulse`, `bounce`, `orbit`, `sweep`, `drift`).
- Each preset commits one scene-pinned undo action; Control `pivot_offset`
  recentering rides the same action for `bounce`/`sweep`.
- Self-contained implementation: depends only on the Godot AI custom-tools
  registration API.
- Tests: 19 editor-suite rows + 30 headless tier-1 checks.
