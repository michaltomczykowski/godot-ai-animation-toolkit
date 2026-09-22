# Toolkit tool reference

Exposed to agents as the promoted first-class tools
**`custom_animation_presets`** (create clips), **`custom_animation_edit`**
(edit existing clips) and **`custom_animation_inspect`** (read-only inspection),
all reachable through `custom_manage(op="invoke", tool_name="animation_presets"
| "animation_edit" | "animation_inspect")`.

A generated per-op index with every parameter lives in
[`op-index.md`](op-index.md) — it is rendered from
`registry/op_registry.gd` and checked for freshness by the tier-1 suite.

## `animation_presets` — common parameters

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

## Per-op parameters (presets)

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

## `animation_edit`

Edits an existing clip in place. Requires `player_path` + `animation_name`; every
call commits **one scene-pinned undo action** and returns
`keys_before` / `keys_after` / `length_before` / `length_after` so a caller can
see exactly what changed. Hand-authored clips are supported; clips containing
bezier / blend-shape / animation tracks, or compressed tracks, are refused with
a `WRONG_TYPE` / `INVALID_PARAMS` error instead of being rewritten lossily.

| op | Notes |
| --- | --- |
| `retime` | `factor` (multiplier) or `length` (seconds). `keys_only=true` changes the clip length but leaves key times alone — handy for re-phasing loops. |
| `retarget` | `mode="node"` swaps the node part and keeps the property; `"prefix"` rewrites a node path or whole subtree (segment-aware, so `Sprite` never matches `SpriteExtra`); `"exact"` matches the full track path including the property. `paths:[{from,to,mode}]` applies a batch. |
| `reverse` | Mirrors key times about the clip length (markers too), then sorts. |
| `mirror` | `axis` is any combination of `x`/`y`/`z`. Position components flip about `pivot` (default origin); quaternion and euler rotation tracks are mirrored as proper rotations; `scale` is only touched with `include_scale=true`; `modulate` and custom properties pass through. |
| `offset` | `wrap=true` rotates the shift inside the clip length (loop phase shift) and dedupes keys that land on the same time; `wrap=false` clamps at 0 and grows the length to fit the last key. |
| `ease_range` | Sets the per-key transition (`linear`/`ease_in`/`ease_out`/`ease_in_out` or a number) on every value key in `[from, to]`. |
| `set_interp` | Track-level interpolation. `cubic` is only accepted for position/rotation/scale 3D tracks; value tracks use `linear`/`nearest`. Optional `track_path` narrows it to one track. |
| `trim` | Keeps `[from, to]`, shifted to 0, length `to - from`. With `keep_bounds=true` (default) value tracks get boundary keys sampled by linear interpolation so the motion at the edges survives. |
| `split_at` | Cuts at `time`; the tail keeps `animation_name`, the head becomes `head_name` (default `<name>_a`). |
| `merge` | Concatenates `sources` (each `{animation_name, player_path?}`, same player by default) with an optional `gap`. Tracks that share (type, path) are merged; the result is always `LOOP_NONE`. |
| `amplitude` | `factor` scales each key's distance from a baseline (default: the track's first key). `factor=0` flattens onto the baseline, `2.0` doubles the motion. Quaternions slerp from identity. |
| `loop` | Sets `loop_mode`; `make_seamless=true` appends (or rewrites) a final key equal to the first value so a linear loop wraps without a jump. |
| `key_edit` | `action` is `add` / `set` / `remove` / `move`; the track is selected by `track_path` (e.g. `"Sprite:position"`) or `track_index`; keys are matched within `tolerance`. `value` is coerced against the target property's real type (or the track's existing key type), so `{"x": 10, "y": 0}` works for a `Vector2` track. |
| `cleanup` | Collapses consecutive equal keys to the last one (so holds keep their end), optionally drops keys closer than `min_gap`, removes empty tracks, and preserves the clip length. |

### Examples

```json
{"op": "animation_edit", "params": {"op": "retime", "player_path": "/Main/HUD",
  "animation_name": "open", "factor": 0.5}}

{"op": "animation_edit", "params": {"op": "retarget", "player_path": "/Main/HUD",
  "animation_name": "open", "from_path": "Panel", "to_path": "Popup/Panel",
  "mode": "prefix"}}

{"op": "animation_edit", "params": {"op": "mirror", "player_path": "/Main",
  "animation_name": "walk", "axis": "x", "pivot": {"x": 0, "y": 0}}}

{"op": "animation_edit", "params": {"op": "merge", "player_path": "/Main",
  "animation_name": "intro", "new_name": "intro_loop", "gap": 0.1,
  "sources": [{"animation_name": "intro"}, {"animation_name": "loop"}]}}

{"op": "animation_edit", "params": {"op": "loop", "player_path": "/Main",
  "animation_name": "walk", "loop_mode": "linear", "make_seamless": true}}
```

## `animation_inspect`

Read-only: it never mutates the scene or the undo stack, so the core's
`batch_execute` (which requires undoable commands) does not accept it — call it
directly, or through `custom_manage(op="invoke")`.

| op | What it reports |
| --- | --- |
| `describe` | A human-readable summary per clip: tracks, keys, length, loop mode, autoplay, broken paths. Omit `animation_name` to summarise every clip on the player. |
| `timeline` | The key table for one clip: per track, each key's time, value (serialized) and transition; `track_path` filters, `max_keys` caps. |
| `audit` | Scene- or player-wide health check. Findings carry a `severity`, a `code` and a `fix` hint. |
| `compare` | Diff two clips (same player by default): length, loop mode, added/removed tracks, changed key counts and max value delta. |
| `stats` | Clip/track/key totals, track-type histogram, loop-mode breakdown, longest/shortest clip. |
| `dry_run` | Runs any `animation_presets` / `animation_edit` op (`forward_op`) and reports what it *would* produce — nothing is committed. |
| `help` | The op index straight from the registry: names, summaries, params and examples. |

### Audit findings

| code | severity | meaning | suggested fix |
| --- | --- | --- | --- |
| `broken_path` | error | the track path does not resolve against the player's root node | `animation_edit retarget` |
| `zero_length` | error | the clip has no length (Godot clamps to 0.001s) and will not play | rebuild the clip |
| `autoplay_missing` | error | `autoplay` names a clip that does not exist | clear autoplay or create the clip |
| `duplicate_keys` | warning | two keys share a time | `animation_edit key_edit remove` |
| `loop_snap` | warning | a linear loop starts and ends on different values, so it pops at the seam | `animation_edit loop make_seamless=true` |
| `autoplay_conflict` | warning | two autoplaying players write the same track path | keep one autoplaying |
| `compressed_track` | warning | the track is compressed; edit ops refuse it | re-save uncompressed |
| `no_keys` | warning | the track has no keys | remove it or add keys |
| `single_key`, `constant_track` | info | the track holds one constant value | `animation_edit cleanup` |
| `unused_clip` | info | no autoplay and no AnimationTree references the clip | may be played from script |

### Examples

```json
{"op": "animation_inspect", "params": {"op": "describe", "player_path": "/Main/HUD"}}

{"op": "animation_inspect", "params": {"op": "audit", "severity": "warning"}}

{"op": "animation_inspect", "params": {"op": "dry_run", "tool": "animation_edit",
  "forward_op": "retime", "player_path": "/Main", "animation_name": "walk", "factor": 0.5}}
```
