# Clip edit history and clean engine errors

Godot 4.7.2; unreleased `repair/toolkit-quality` branch.

## Repairs

- `split_at` records an existing overwritten head for Undo, along with the
  original tail. Both split specs and merged output are validated before commit.
- Merge and layer refuse compressed sources with `INVALID_PARAMS`, matching
  ordinary edits; unsupported tracks return `WRONG_TYPE` without mutation.
- Value tracks retain interpolation loop wrap through the shared spec reader
  and builder. The metadata regression reads engine properties directly.
- The complete editor harness captures engine errors around suite execution
  and fails even when every assertion passes. Warnings are reported separately.
  Typed tool errors from negative requests are valid results, not engine errors.
- Absent-clip assertions use `has_animation`. Spring tests distinguish automatic
  child collisions from explicit lists before querying a collision index.
- Explicit spring collisions are reparented before Godot validates their paths.
  Modifier setup, collision moves and wiring now share one scene action;
  Undo restores parents, names and local transforms. Repeated collider names get
  distinct child names; unique engine-generated names are preserved without
  reassignment, and duplicate generated names are refused before mutation. Invalid or instanced colliders are refused before commit.

Reference contracts: [Animation track metadata and compression](https://docs.godotengine.org/en/4.7/classes/class_animation.html),
[SpringBoneSimulator3D collision modes](https://docs.godotengine.org/en/4.7/classes/class_springbonesimulator3d.html).

## Coverage

`test_edit_route_history.gd` invokes all 20 advertised edits through Godot AI's
public dispatcher in three layouts: scene-owned, non-editable instance and
already-editable instance. Each layout also exercises split head overwrite,
merge output overwrite, cross-player merge and cross-player layer: **72 writes**.

Each case checks dry/rejected state and history, exactly one scene action and
no global action, unchanged unrelated clips and cross-player inputs, exact
Undo/Redo contents, original resource identities on Undo, saved undone/redone
states, and zero engine errors. Instance cases verify source/peer isolation and
Editable Children restoration. Source files are unique per operation/layout/
variant; fixtures use separate resources and actual redundant/dense keys.

`test_edit_contracts.gd` checks retiming of position, rotation, scale and value
tracks with disabled tracks, update mode, interpolation, wrap, transitions and
colored markers. It also checks compressed and unsupported input refusals in
ordinary edits, merge and layer, including dry runs.

`tools/mcp_edit_history.py` requires all seven named tests and nonzero assertion
counts through the external MCP connection. Three fresh engine batches replay
all **144 saved Undo/Redo states**, with independently authored expected values
and unchanged source playback. A fourth batch plays both saved 3D metadata
states: **146 states total**. The existing 20-operation interpolation/playback
gate remains enabled, along with character, graph and FX gates.

## Local evidence, 2026-10-05

- `edit_engine_errors_before_20261005.log`: 249 assertions-based tests pass,
  but the new whole-suite gate fails on eight engine errors.
- `edit_history_regressions_20261005.log`: confirmed lost split head on local
  Undo and Godot's rejection of explicit spring collision paths.
- `edit_history_after_20261005.log`: 257/257 editor tests pass, zero captured
  engine errors. Existing Bone2D leaf-length warnings remain separately visible.
- `mcp_edit_history_before_reload_20261005.log` and
  `mcp_edit_history_after_reload_20261005.log`: 7/7 named tests and all 146
  saved playback states pass through the fresh visible editor and core reload.
- `mcp_edit_reload_20261005.log`: all ten toolkit families remain discoverable.
- `edit_history_complete_editor_20261005.log`: final 258/258 full suite, zero
  captured errors, including transformed and same-named spring colliders.
- `edit_history_tier1_20261005.log`: all 14 headless suites pass.
- `mcp_edit_ui_*20261005.log`: visible Ctrl+Z/Ctrl+Shift+Z restores recorded
  timelines for retime, split overwrite and merge overwrite. Undoing the first
  scene leaves the second scene's generated merge unchanged.

Logs and recovery copies are under `F:/GODOTAITESTING/` and the persistent
`toolkit_repair_snapshot_2026-09-30/edit_history_20261005` folder. Final UI and
platform CI outcomes are recorded in `FIX_ROADMAP.md`.

## Limits

The 72-case matrix uses value tracks; the additional 3D case tests the shared
rebuild and metadata path. It does not approve every operation/track-type
combination or character visual quality. Suite capture excludes backend startup
and shutdown diagnostics. Preset, library and remaining rig/modifier histories,
and broader visual reviews, remain separate roadmap work.
