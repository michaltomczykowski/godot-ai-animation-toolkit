# `animation_presets` — tool reference

Exposed to agents as the promoted first-class tool **`custom_animation_presets`**
(and reachable through `custom_manage(op="invoke", tool_name="animation_presets")`).

## Common parameters

| Param | Type | Required | Notes |
| --- | --- | --- | --- |
| `op` | `"pulse" \| "bounce" \| "orbit" \| "sweep" \| "drift"` | yes | Which preset to build. |
| `player_path` | string | yes | Scene path to an existing `AnimationPlayer` (presets never auto-create one). |
| `target_path` | string | yes | Node to animate: relative to the player's `root_node` (e.g. `"Button"`) or scene-absolute (e.g. `"/Main/Button"`). Must be a `Control`, `Node2D`, or `Node3D`. |
| `animation_name` | string | no | Clip name; defaults to the preset name. |
| `overwrite` | bool | no | `false` (default) refuses an existing clip with the same name. |

## Per-op parameters

| Param | Applies to | Default | Notes |
| --- | --- | --- | --- |
| `property` | pulse | `"scale"` | Any property on the target; subpaths like `"modulate:a"` are supported. |
| `from_scale` / `to_scale` | pulse | `1.0` / `1.1` | Scale shortcut when `property="scale"` and no explicit values are given. |
| `from_value` / `to_value` | pulse | — | Required for a non-`scale` property; coerced to the property's real type (`float`, `Vector2`, `Vector3`, `Color`). |
| `duration` | all | `0.4` pulse/bounce, `2.0` orbit, `1.0` sweep/drift | Clip length in seconds. |
| `loop_mode` | pulse, orbit, sweep, drift | `"none"` | `"none" \| "linear" \| "pingpong"`. `drift` refuses `"linear"` (the clip ends at a net offset and would snap back). |
| `intensity` | bounce | `0.15` | Peak overshoot fraction (`peak = 1 + intensity`, `dip = 1 - intensity/4`). |
| `radius` | orbit | `1.0` (3D) / `100.0` (2D) | Circle radius; 16 linear segments trace the circle (chord error ≈ 2%). |
| `clockwise` | orbit, sweep | `true` | Direction of travel / rotation. |
| `turns` | sweep | `1.0` | Full turns; 3D rotates around local Y, Control/Node2D in-plane. |
| `axis` | drift | `"x"` | `"x" \| "y" \| "z"` (3D), `"x" \| "y"` (2D/Control). |
| `distance` | orbit, sweep, drift | by dimension | Offset magnitude (orbit uses `radius`). |

## Behaviour

- **Baseline**: every preset starts from the target's *current* transform, so a
  scaled/rotated/offset node does not snap to identity when the clip starts.
- **One undo step**: the clip, any auto-created default `AnimationLibrary`, and
  a recentered Control `pivot_offset` (bounce/sweep) are committed as a single
  scene-pinned action. One Ctrl-Z reverts all of it.
- **Errors**: `MISSING_REQUIRED_PARAM`, `VALUE_OUT_OF_RANGE`, `WRONG_TYPE`,
  `PROPERTY_NOT_ON_CLASS`, `NODE_NOT_FOUND`, `EDITOR_NOT_READY` — the same
  codes the core Godot AI tools use.
- **Non-`scale` pulse values** are coerced against the target property's real
  type: `float`/`int`, `Vector2`, `Vector3`, and `Color` (hex string, named
  color, or `{r,g,b[,a]}` dict) are supported.

## Examples

```json
{"op": "pulse", "params": {"op": "pulse", "player_path": "/Main/HUD",
  "target_path": "Label", "property": "modulate:a",
  "from_value": 0.2, "to_value": 1.0, "loop_mode": "pingpong", "duration": 1.2}}

{"op": "orbit", "params": {"op": "orbit", "player_path": "/Main/HUD",
  "target_path": "Satellite", "radius": 80.0, "duration": 3.0, "loop_mode": "linear"}}

{"op": "drift", "params": {"op": "drift", "player_path": "/Main",
  "target_path": "Scanline", "axis": "x", "distance": 480.0,
  "loop_mode": "pingpong", "duration": 2.0}}
```
