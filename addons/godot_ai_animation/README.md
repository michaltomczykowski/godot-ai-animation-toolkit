# Godot AI Animation Toolkit (addon)

One-call animation presets for an `AnimationPlayer`, exposed to Godot AI agents
as a custom MCP tool: `animation_presets` (promoted to
`custom_animation_presets`).

| op | What it builds |
| --- | --- |
| `pulse` | Breathing / ping-pong on any property (`scale` shortcut or typed `from_value`/`to_value`). |
| `bounce` | Center-pivot scale overshoot with settle-back — UI press feedback. |
| `orbit` | Circular position orbit (XZ for 3D, screen space for 2D/Control). |
| `sweep` | Full-turn rotation sweep (radar / cooldown ring). |
| `drift` | One-axis position offset (scanlines, marquee, conveyor). |

Every preset commits **one scene-pinned undo action**; Controls get
`pivot_offset` recentered inside the same action for `bounce`/`sweep`.

## Requirements

- [Godot AI](https://github.com/hi-godot/godot-ai) `>= 4.1.0` installed in the
  same project (this addon registers through its custom-tools API).
- Godot 4.5–4.7.

## Install

1. Copy `addons/godot_ai_animation/` into your project's `addons/`.
2. Enable **Godot AI Animation Toolkit** in *Project → Project Settings →
   Plugins* (enable Godot AI too, in any order).
3. The tool appears in the Godot AI dock's Tools tab and in
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

See the repository README and `docs/tool-reference.md` for the full parameter
table.
