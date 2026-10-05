# Preset and library scene history

Repair branch: `repair/toolkit-quality`, unreleased. Engine: Godot 4.7.2.

## Scope and reproduced defects

The phase exercises the public Godot AI dispatcher and external MCP tools.
It does not approve character motion or animation visual quality.

| Defect | Repair |
| --- | --- |
| Showcase Undo clears owners; Redo fails to restore them. Saved generated nodes can disappear. | Commit every descendant owner with the node creation action; use the shared instance permission path. |
| Library dry runs accept unsafe paths and duplicate exports that writes reject. | Perform path and overwrite validation before the dry-run return. |
| Malformed template records, params, markers and keys produce script errors. | Validate document shapes and supported recipes before typed casts; parse JSON with an instance to return a typed error without logging an engine error. |
| Export writes null for unsupported values while reporting success. | Represent bool, text, exact integers and Transform3D; reject unrepresentable values, unsaved audio and non-native method args before touching the output. |
| JSON loses value loop-wrap and event-track metadata. | Preserve interpolation, wrap, key transitions, update mode, audio blending and colored markers. |
| `spec_apply` reports success for missing nodes and incompatible destinations. | Validate node/property, 3D/bone, audio and method destinations, key value types and enabled tracks before commit. `spec_import` remains independent of a scene. |

The showcase ownership correction follows Godot's
[Node ownership and remove_child contract](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-method-remove-child).
Track paths and metadata follow the
[Animation contract](https://docs.godotengine.org/en/4.7/classes/class_animation.html).

## Coverage

`test_preset_library_history.gd` is registry checked and covers:

- Eight preset clip writers across local new, overwrite, missing-library,
  locked-instance and already-editable-instance layouts: 40 writes.
- Preset and FX template forwarding across those five layouts: 10 writes.
- Inline spec application across those layouts: five writes.
- Showcase under the edited root, a local parent and both instance permission
  states: four writes.

The primary matrix is **59 writes / 118 saved Undo/Redo states**. Each case
checks dry/rejected behavior, exactly one scene action and no global action,
original resource identity on Undo, Redo, persisted properties, source/peer
isolation and engine errors. Snapshots include Control pivots, 3D transforms,
clips and metadata, ownership, autoplay and instance permission restoration.
Label sizes depend on the theme while off-tree; compare persisted text and
font overrides instead of their transient minimum size.

`test_library_contracts.gd` separately checks non-undoable file writes, byte
preservation on dry/rejected calls, recipe reopening, malformed documents,
invalid destinations and unrepresentable export values. It also round-trips
2D/bool/text, typed 3D, Transform3D, and method/audio clips, producing **eight
additional saved states**. File operations are not classified as scene Undo.

`tools/mcp_preset_library_history.py` requires all eleven named tests and
meaningful assertion counts. Seven fresh engine batches play all **126 saved
states** using independently authored expected property values, easing and
quaternion checks. The cue batch confirms a method fires and audio starts;
the showcase batch checks all seven clips and autoplay declarations. The gate
is mandatory in `tools/ci_mcp_route.py`; prior family gates remain enabled.

## Local verification

- Failing baseline retained: showcase ownership, dry-run disagreement,
  malformed-data script errors and failed exported values.
- Current external MCP run: eleven named tests pass, all 126 saved states
  pass, no captured runtime engine errors.
- Repeated after Godot AI core reload; all ten families remain registered.
- Visible Godot Ctrl+Z/Ctrl+Shift+Z passes for pivot-affecting bounce, a
  template-applied bounce and the complete seven-player showcase. Snapshots
  are prepared and checked by `tools/mcp_preset_library_ui_history.py`.
- All fourteen local headless suites pass.

Full editor results and this checkpoint's Windows/Linux CI are recorded below
after completion. Earlier checkpoint `ff8cdbc` passed all platform jobs in
GitHub Actions run 37364196616, after rerunning hosted-runner cancellations.

## Recovery and remaining work

The phase snapshot is
`F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/preset_library_history_20261006`.
It contains source/patch, failing and passing logs, visible UI records, and
saved history/source scenes. `FIX_ROADMAP.md` remains the repair ledger.

Broader rig/modifier and motion histories and fixed-camera visual review remain
open. Operation status remains partial until every applicable gate passes.
