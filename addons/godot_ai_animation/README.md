# Godot AI Animation Toolkit (addon)

Two custom MCP tools for Godot AI agents, built on one declarative clip-spec
engine:

- **`animation_presets`** (promoted to `custom_animation_presets`) — build clips
  in one call.
- **`animation_edit`** (promoted to `custom_animation_edit`) — edit any existing
  clip in place, hand-authored ones included.

## `animation_presets`

| op | What it builds |
| --- | --- |
| `pulse` | Breathing / ping-pong on any property (`scale` shortcut or typed `from_value`/`to_value`). |
| `bounce` | Center-pivot scale overshoot with settle-back — UI press feedback. |
| `orbit` | Circular position orbit (XZ for 3D, screen space for 2D/Control). |
| `sweep` | Full-turn rotation sweep (radar / cooldown ring). |
| `drift` | One-axis position offset (scanlines, marquee, conveyor). |
| `spin` | 3D quaternion turn around local Y. |
| `float` | 3D bob: rise + scale + turn through the transform. |
| `stagger` | Reveal a list of targets one after another in one clip (`target_paths` or the editor selection). |
| `showcase` | Builds a runnable demo of every preset (7 nodes + 7 autoplaying clips). |

Every preset commits **one scene-pinned undo action**; Controls get
`pivot_offset` recentered inside the same action for `bounce`/`sweep`.

## `animation_edit`

| op | What it does |
| --- | --- |
| `retime` | Scale the timeline by `factor` or to `length` (optionally `keys_only`). |
| `retarget` | Rename a node's tracks, or bulk-remap a subtree prefix after a refactor. |
| `reverse` | Play the clip backwards. |
| `mirror` | Mirror position/rotation (optionally scale) across a plane, about a pivot. |
| `offset` | Shift every key in time, optionally wrapping inside the loop. |
| `ease_range` | Set per-key transitions inside a time range. |
| `set_interp` | Track-level interpolation (linear / nearest / cubic for 3D transform tracks). |
| `trim` | Keep a time range, with sampled boundary keys. |
| `split_at` | Cut one clip into two. |
| `merge` | Concatenate clips (optionally across players) into one. |
| `amplitude` | Scale key deltas about a baseline. |
| `loop` | Set the loop mode, optionally making a linear loop seamless. |
| `key_edit` | Add / set / remove / move a single key. |
| `cleanup` | Drop redundant keys and empty tracks. |

Edit ops refuse clips with bezier / blend-shape / animation tracks or
compressed tracks rather than rewriting them lossily.

## Architecture

- `spec/clip_spec.gd` — declarative clip data (tracks, typed keys, markers).
- `spec/spec_builder.gd` / `spec/spec_io.gd` — spec ⇄ `Animation`.
- `spec/spec_modifiers.gd` — pure spec → spec transforms (tier-1 tested).
- `registry/op_registry.gd` — single source of truth for tool descriptions,
  params schemas, op metadata, and `docs/op-index.md`.
- `handlers/generate.gd`, `handlers/edit.gd` — tool entry points sharing
  `handlers/animation_tool_base.gd` (one undo action per call).

## Requirements

- [Godot AI](https://github.com/hi-godot/godot-ai) `>= 4.1.0` installed in the
  same project (this addon registers through its custom-tools API).
- Godot 4.5–4.7.

## Install

1. Copy `addons/godot_ai_animation/` into your project's `addons/`.
2. Enable **Godot AI Animation Toolkit** in *Project → Project Settings →
   Plugins* (enable Godot AI too, in any order).
3. The tools appear in the Godot AI dock's Tools tab and in
   `custom_manage(op="list")`.

## Usage

```json
{"op": "pulse", "params": {
  "op": "bounce",
  "player_path": "/Main/HUD",
  "target_path": "Button",
  "intensity": 0.2
}}
```

```json
{"op": "animation_edit", "params": {
  "op": "retime",
  "player_path": "/Main/HUD",
  "animation_name": "open",
  "factor": 0.5
}}
```

See the repository README, `docs/tool-reference.md` and the generated
`docs/op-index.md` for the full parameter tables.
