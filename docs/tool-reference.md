# Toolkit tool reference

Exposed to agents as the promoted first-class tools
**`custom_animation_presets`** (create clips), **`custom_animation_fx`**
(generators for game feel, UI, sprites and audio), **`custom_animation_graph`**
(AnimationTree authoring), **`custom_animation_edit`** (edit existing clips) and
**`custom_animation_inspect`** (read-only inspection), all reachable through
`custom_manage(op="invoke", tool_name=...)`.

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

## `animation_fx`

One-call generators for game feel, UI, sprites and audio. Same contract as the
presets: one scene-pinned undo action per call, typed keys, `dry_run` supported
and `animation_name` defaulting to the op name.

| op | What it builds | Key params |
| --- | --- | --- |
| `shake` | Seeded decaying positional noise (camera/control) | `intensity`, `frequency`, `decay`, `seed`, `axis` |
| `zoom_punch` | Camera punch: overshoot then settle (`Camera2D.zoom`, `Camera3D.fov`) | `amount`, `peak_ratio` |
| `hit_flash` | `modulate` flash and back, N times | `color`, `count` |
| `damage_bar` | Delayed follow-up bar: hold, then ease | `from`, `to`, `delay` |
| `typewriter` | Text reveal via `visible_ratio`, smooth or stepped | `steps`, `delay`, `from_ratio`, `to_ratio` |
| `progress_fill` | Numeric fill (ProgressBar `value`, custom float) | `from`, `to`, `delay` |
| `counter` | Rolling numbers: method track calling a setter with formatted text | `from`, `to`, `steps`, `format`, `prefix`, `suffix`, `method` |
| `dialog_pop` | Modal entrance: scale through an overshoot, optional fade | `from_scale`, `overshoot`, `fade` |
| `transition` | Full-screen fade or wipe (pivot recentered for wipes) | `mode`, `duration` |
| `wave` | Cascading sine bob, one track per target | `target_paths`/`use_selection`, `amplitude`, `period`, `phase_step`, `cycles` |
| `spring` | Damped spring settle to position + offset | `offset`, `frequency`, `damping`, `samples` |
| `pendulum` | Swinging rotation with optional decay (2D float, 3D local Z) | `amplitude`, `period`, `decay` |
| `path_follow` | Follow a `Path2D`/`Path3D` curve, sampled into position keys | `path_node`, `samples`, `loop_mode` |
| `flipbook` | Step a `Sprite2D.frame` with nearest interpolation | `frames`, `fps`, `from_frame` |
| `sprite_frames` | Slice a spritesheet into a `SpriteFrames` resource and assign it | `sprite_path`, `texture`, `hframes`, `vframes`, `fps`, `loop` |
| `audio_cue` | Schedule a stream as a one-key audio clip | `stream`, `time`, `start_offset`, `end_offset` |

Notes:

- **`shake`** is deterministic for a given `seed`, samples at 2x the frequency,
  and always settles exactly on the original position.
- **`counter`** uses a method track: the node needs a setter that takes the
  formatted string (a `Label`'s `set_text` works out of the box).
- **`transition`** wipes recenter the Control's `pivot_offset` inside the same
  undo action, like `bounce`/`sweep` do.
- **`sprite_frames`** replaces the node's `sprite_frames` resource and (by
  default) starts playing; it targets an `AnimatedSprite2D` — for a `Sprite2D`
  sheet use `flipbook` plus `hframes`/`vframes` on the node.

### Examples

```json
{"op": "animation_fx", "params": {"op": "shake", "player_path": "/Main",
  "target_path": "Camera2D", "intensity": 10, "duration": 0.4, "seed": 7}}

{"op": "animation_fx", "params": {"op": "typewriter", "player_path": "/Main/HUD",
  "target_path": "DialogLabel", "steps": 40, "duration": 1.6}}

{"op": "animation_fx", "params": {"op": "wave", "player_path": "/Main/HUD",
  "target_paths": ["Card1", "Card2", "Card3"], "amplitude": 10, "phase_step": 0.15}}

{"op": "animation_fx", "params": {"op": "sprite_frames", "sprite_path": "/Main/Player",
  "texture": "res://art/run.png", "hframes": 6, "vframes": 1, "fps": 12}}
```

## `animation_graph`

Authors `AnimationTree` graphs on top of an `AnimationPlayer`. The tree is
created next to the player (or at `tree_path`), pointed at the player, activated,
and committed as ONE scene-pinned undo action.

| op | What it builds |
| --- | --- |
| `state_machine` | An `AnimationNodeStateMachine` root from `states` + `transitions` (xfade, advance/switch modes, conditions, expressions, priority). |
| `blend_space` | A 1D or 2D `AnimationNodeBlendSpace` from clips at positions. |
| `blend_tree` | A recursive blend tree spec: `blend2`/`blend3`/`add2`/`add3`/`one_shot`/`time_scale`/`animation`, with nested state machines and blend spaces. |
| `wire` | Ensures the tree exists, is active and pointed at the player; optionally sets a parameter. |
| `graph_get` | Dumps a graph: states, transitions, blend points, tree nodes, parameters, playback paths, and issues (missing clips, inactive tree, unresolved player). |
| `locomotion` | Ready-made idle/walk/run: a speed blend space (default) or a state machine driven by `walking`/`running`. |
| `one_shot_layer` | Layers a one-shot (jump/attack/hit) over the existing tree root, exposing `parameters/.../request`. |
| `additive_lean` | Layers a clip additively over the existing root, exposing `parameters/.../add_amount`. |

Notes:

- Godot adds `Start`/`End` markers to state machines and an `output` port to
  blend trees; the ops ignore them in counts and dumps.
- State machines have no persisted start state: the ops report a `start_hint`
  with the playback path to call at runtime
  (`tree.get("parameters/<name>/playback").start("idle")`).
- Conditions become bool parameters: `parameters/conditions/<name>`.
- Blend amounts / one-shot requests are parameters on the tree
  (`parameters/<node>/blend_amount`, `/request`, `/add_amount`).
- `graph_get` reports `missing_clip` when the graph references a clip the player
  does not have, instead of failing the build.

### Examples

```json
{"op": "animation_graph", "params": {"op": "state_machine", "player_path": "/Main",
  "states": [{"name": "idle", "animation": "idle"}, {"name": "walk", "animation": "walk"}],
  "transitions": [
    {"from": "idle", "to": "walk", "xfade": 0.2, "condition": "walking"},
    {"from": "walk", "to": "idle", "xfade": 0.2, "advance_expression": "!walking"}]}}

{"op": "animation_graph", "params": {"op": "blend_space", "player_path": "/Main",
  "dimensions": 1, "min": 0, "max": 2,
  "points": [{"animation": "idle", "position": 0}, {"animation": "walk", "position": 1},
             {"animation": "run", "position": 2}]}}

{"op": "animation_graph", "params": {"op": "locomotion", "player_path": "/Main",
  "mode": "state_machine", "start": "idle"}}

{"op": "animation_graph", "params": {"op": "one_shot_layer", "player_path": "/Main",
  "animation": "jump", "fadein": 0.1, "fadeout": 0.2}}
```
