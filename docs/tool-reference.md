# `animation_presets` — tool reference

Exposed to agents as the promoted first-class tool **`custom_animation_presets`**
(and reachable through `custom_manage(op="invoke", tool_name="animation_presets")`).

## Common parameters

| Param | Type | Required | Notes |
| --- | --- | --- | --- |
| `op` | `"pulse" \| "bounce" \| "orbit" \| "sweep" \| "drift" \| "spin" \| "showcase"` | yes | Which preset to build. |
| `player_path` | string | yes\* | Scene path to an existing `AnimationPlayer` (presets never auto-create one). |
| `target_path` | string | yes\* | Node to animate: relative to the player's `root_node` (e.g. `"Button"`) or scene-absolute (e.g. `"/Main/Button"`). Must be a `Control`, `Node2D`, or `Node3D`. |
| `parent_path` | string | no | `showcase` only: parent for the demo subtree (default: the edited scene root). |
| `name` | string | no | `showcase` only: subtree name (default `"AnimationShowcase"`). |
| `target_paths` | array of strings | no\*\* | `stagger` only: ordered targets to reveal (each relative to `root_node` or scene-absolute). |
| `use_selection` | bool | no\*\* | `stagger` only: use the editor's current selection, in selection order, instead of `target_paths`. |
| `animation_name` | string | no | Clip name; defaults to the preset name. |
| `overwrite` | bool | no | `false` (default) refuses an existing clip with the same name. |

\* Not used by `showcase`, which builds its own nodes and players.
\*\* `stagger` needs exactly one of `target_paths` or `use_selection`.

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
| `turns` | sweep, spin, float | `1.0` (float: `0.0`) | Full turns; `sweep` rotates in-plane (or local Y for 3D), `spin` is a 3D quaternion turn, `float` adds a turn to the bob. |
| `height` | float | `0.7` | Vertical offset (negative bobs down). |
| `scale` | float | `1.25` | Peak scale factor relative to the target's baseline. |
| `axis` | drift | `"x"` | `"x" \| "y" \| "z"` (3D), `"x" \| "y"` (2D/Control). |
| `distance` | orbit, sweep, drift, stagger | by dimension | Offset magnitude (orbit uses `radius`; stagger `slide_in` uses it for the travel distance). |
| `effect` | stagger | `"fade_in"` | `"fade_in"` (CanvasItem `modulate:a`), `"slide_in"` (position), `"pop_in"` (scale from 0.6×). |
| `stagger` | stagger | `0.06` | Seconds between consecutive targets. |
| `direction` | stagger | `"left"` | `slide_in` travel direction: `left \| right \| up \| down`. |

## Float, stagger and the showcase

- **`float`** (3D only) bobs a `Node3D` through its `transform`: two keys from
  the target's current transform, raised by `height`, scaled by `scale`, turned
  `turns` full turns about local Y. The clip ends at a net offset, so
  `loop_mode="linear"` is refused — pass `"pingpong"` for a hover loop.
- **`stagger`** reveals many targets in **one clip** (one track per target, key
  times offset by `stagger`, length `(n-1)*stagger + duration`, `loop_mode`
  fixed to `"none"`), one undo action. Targets are ordered: the `target_paths`
  order, or the editor's selection order. Duplicates are refused, and `fade_in`
  needs a `CanvasItem`/`Control` target.
- **`showcase`** ignores `player_path`/`target_path` and builds a runnable demo
  subtree in one undo action:

| Node | Clip |
| --- | --- |
| `BounceButton` (Control) | `bounce` |
| `OrbitDot` (ColorRect) | `orbit`, radius 60 px |
| `SweepPivot`/`SweepBar` | `sweep`, linear loop |
| `DriftLine` (ColorRect) | `drift`, ping-pong |
| `PulseLabel` (Label) | `pulse` on `modulate:a`, ping-pong |
| `World3D/FloatCube` (MeshInstance3D) | `float`, 3D bob + scale + turn, ping-pong |
| `World3D/SpinCube` (MeshInstance3D) | `spin`, 3D quaternion turn, linear loop |

Seven `AnimationPlayer`s autoplay their clip; run the current scene (F6) to
watch it. `test_project/showcase.tscn` is the committed output.

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

{"op": "float", "params": {"op": "float", "player_path": "/Main",
  "target_path": "Pickup", "height": 0.4, "scale": 1.1,
  "loop_mode": "pingpong", "duration": 2.4}}

{"op": "stagger", "params": {"op": "stagger", "player_path": "/Main/HUD",
  "target_paths": ["Item1", "Item2", "Item3"], "effect": "slide_in",
  "direction": "left", "stagger": 0.08, "duration": 0.3}}
```
