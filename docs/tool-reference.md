# Toolkit tool reference

Exposed to agents as the promoted first-class tools
**`custom_animation_presets`** (create clips), **`custom_animation_fx`**
(generators for game feel, UI, sprites and audio), **`custom_animation_graph`**
(AnimationTree authoring), **`custom_animation_edit`** (edit existing clips),
**`custom_animation_inspect`** (read-only inspection), **`custom_animation_library`**
(reusable templates + JSON clip specs), **`custom_animation_rig`** (skeleton
poses, pose-driven clips and procedural recipes) and
**`custom_animation_motion`** (procedural humanoid cycles and secondary spring
bones), all reachable through
`custom_manage(op="invoke", tool_name=...)`.

A ninth family, **`animation_rig_modifiers`** (the five modifier setups:
`ik_setup`, `spring_setup`, `look_at_setup`, `retarget_setup`, `twist_setup`),
shares the `animation_rig` handler and is documented in the `animation_rig`
section below. It is **not promoted**: the Godot AI server promotes at most
eight tools, so with nine families one has to give up its slot. Call it as
`custom_manage(op="invoke", tool_name="animation_rig_modifiers",
params={"op": "ik_setup", ...})`.

`dry_run: true` is side-effect free on every op that advertises it: no scene
node is added or changed, no clip is written, no undo action is committed and
**no file is created** (`pose_save`, `template_save`, `template_delete` and
`rig_profile` all report what they would write instead).

Every file the toolkit writes is confined to `res://animation_toolkit/…` with a
plain file name. `res://`, `user://`, an absolute path, a `..` escape and a
project file such as `res://project.godot` are refused, and the refusal names
the allowed root. Ops that promise undoability (`pose_apply` and the `*_setup`
family) refuse outright when there is no editor undo history, so `undoable:
true` is never a claim without an undo stack behind it.

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
{"tool": "custom_animation_presets", "params": {"op": "pulse", "player_path": "/Main/HUD",
  "target_path": "Label", "property": "modulate:a",
  "from_value": 0.2, "to_value": 1.0, "loop_mode": "pingpong", "duration": 1.2}}

{"tool": "custom_animation_presets", "params": {"op": "orbit", "player_path": "/Main/HUD",
  "target_path": "Satellite", "radius": 80.0, "duration": 3.0, "loop_mode": "linear"}}

{"tool": "custom_animation_presets", "params": {"op": "drift", "player_path": "/Main",
  "target_path": "Scanline", "axis": "x", "distance": 480.0,
  "loop_mode": "pingpong", "duration": 2.0}}

{"tool": "custom_animation_presets", "params": {"op": "float", "player_path": "/Main",
  "target_path": "Pickup", "height": 0.4, "scale": 1.1,
  "loop_mode": "pingpong", "duration": 2.4}}

{"tool": "custom_animation_presets", "params": {"op": "stagger", "player_path": "/Main/HUD",
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
| `smooth` | `strength` (0-1) lerps every value key toward the midpoint of its neighbours, `passes` times; looping clips wrap the seam. Use it to take jitter or over-shoot out of captured clips. |
| `resample` | Rebuilds value tracks at `fps` samples/s using the engine's own interpolator, so per-key transitions and cubic tracks are preserved. `interpolation` sets the rebuilt track mode (`linear`/`nearest`). Optional `track_path`. |
| `reduce` | Drops the keys a clip does not need, inside a **measured** error budget: `angle` degrees for rotation tracks, `value_tolerance` units for the rest. Greedy and exact — it keeps the first/last key, measures the reduced track against every original key through the engine's interpolator, and re-inserts the worst offender until the budget holds (`max_keys` caps each track). Unlike `resample`, no key moves onto a new grid, so the dense procedural cycles (70+ keys per bone) shrink with the curve intact. Reports `removed_keys`, `kept_keys` and the worst `worst_error`. |
| `add_noise` | Deterministic micro-motion: `amount` (degrees for rotations, units for vectors) of seeded smooth noise, `frequency` cycles across the track, `seed`. Use it for breathing, tremor and idle life. |
| `overlap` | Delays the tracks matching `track_path` (exact path, node, or subtree prefix) by `delay` seconds — the one-call follow-through for forearms, hair or props. `wrap=true` folds the shift inside the clip. |
| `layer` | Combines `source_animation` onto the edited clip. `layer_mode="mix"` (default) blends toward the source by `weight`; `"add"` applies the source's delta from its first key (rotation multiply, vector/float add) — breathing or jiggle over a base. `source_player_path` reads the source from another player, `remap_node` rewrites its node path before matching. |

### Examples

```json
{"tool": "custom_animation_edit", "params": {"op": "retime", "player_path": "/Main/HUD",
  "animation_name": "open", "factor": 0.5}}

{"tool": "custom_animation_edit", "params": {"op": "retarget", "player_path": "/Main/HUD",
  "animation_name": "open", "from_path": "Panel", "to_path": "Popup/Panel",
  "mode": "prefix"}}

{"tool": "custom_animation_edit", "params": {"op": "mirror", "player_path": "/Main",
  "animation_name": "walk", "axis": "x", "pivot": {"x": 0, "y": 0}}}

{"tool": "custom_animation_edit", "params": {"op": "merge", "player_path": "/Main",
  "animation_name": "intro", "new_name": "intro_loop", "gap": 0.1,
  "sources": [{"animation_name": "intro"}, {"animation_name": "loop"}]}}

{"tool": "custom_animation_edit", "params": {"op": "loop", "player_path": "/Main",
  "animation_name": "walk", "loop_mode": "linear", "make_seamless": true}}

{"tool": "custom_animation_edit", "params": {"op": "overlap", "player_path": "/Main",
  "animation_name": "walk", "track_path": "Skeleton3D:B-forearm.L",
  "delay": 0.08, "wrap": true}}

{"tool": "custom_animation_edit", "params": {"op": "layer", "player_path": "/Main",
  "animation_name": "walk", "source_animation": "breathing",
  "layer_mode": "add", "weight": 0.4}}

{"tool": "custom_animation_edit", "params": {"op": "resample", "player_path": "/Main",
  "animation_name": "walk", "fps": 30, "interpolation": "linear"}}
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
| `motion_report` | Per-track motion quality: key density, peak speed/acceleration, loop-seam pops, quaternion hemisphere flips and constant tracks, each with a `fix` hint. |
| `motion_audit` | Plays the clip on a Skeleton3D (posed and restored, never saved) and **grades** it in world space: per foot the ground-contact windows and the horizontal slide while planted, plus the hips' bob and travel, each pass/fail against a budget (`max_slide` 5 cm, `max_hip_bob` 12 cm) with a `fix` hint. Contact is "within `contact_threshold` (5 mm) of the foot's rest height", and a window's slide is the foot's *net* displacement while it was down — a foot that lifts, swings and lands ahead is a step, not a slide. A clip authored in place is reported as `in_place`, because its stance foot travelling with the body is by design. |
| `rig_profile` | Understand a rig without touching it: detected roles with ranked candidates, T/A pose, limb lengths and reach, facing/lateral/up axes, capabilities (walk/run/jump/turn/strafe/blink/IK/springs), missing roles, warnings and suggested next ops. `save=true` writes `res://animation_toolkit/rig_profiles/<name>.json`; rig and motion ops accept that file (or its name) as their `profile` param, so detection is never guessed twice. |
| `sample` | FK probe: apply the clip to the skeleton in memory and report world positions (and optional euler rotations) of requested bones at N times, plus derived foot heights and ground-contact windows. The skeleton's pose is restored afterwards. |
| `preview` | Renders the posed character to PNGs at clip times, so a clip can be *seen* (contact, foot planting, follow-through) instead of only read. A private copy of the character subtree (`character_path`, default the skeleton's outermost ancestor) is posed in an offscreen viewport with its own lights, framed by a camera (`yaw`, `elevation`, `margin`) and freed again; the edited scene is never touched. Params: `times` or `samples`, `width`/`height`, `output_dir`, `basename`, `background`, `overwrite`. The reply is **deferred** (one editor frame per image) and needs a rendering device - headless editors get an explicit error. |
| `dry_run` | Runs any generator or edit op (`forward_op` from `animation_presets`, `animation_fx`, `animation_graph`, `animation_edit`, `animation_library`, `animation_rig`, `animation_motion`) and reports what it *would* produce — nothing is committed. |
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
{"tool": "custom_animation_inspect", "params": {"op": "describe", "player_path": "/Main/HUD"}}

{"tool": "custom_animation_inspect", "params": {"op": "audit", "severity": "warning"}}

{"tool": "custom_animation_inspect", "params": {"op": "rig_profile", "skeleton_path": "/Main/Rig/Skeleton3D",
  "save": true, "name": "hero"}}

{"tool": "custom_animation_inspect", "params": {"op": "sample", "player_path": "/Main/Rig/AnimationPlayer",
  "animation_name": "walk", "skeleton_path": "/Main/Rig/Skeleton3D", "samples": 24}}

{"tool": "custom_animation_inspect", "params": {"op": "preview", "player_path": "/Main/Rig/AnimationPlayer",
  "animation_name": "reach", "skeleton_path": "/Main/Rig/Skeleton3D", "times": [0.0, 0.4],
  "output_dir": "res://animation_toolkit/previews"}}

{"tool": "custom_animation_inspect", "params": {"op": "dry_run", "tool": "animation_edit",
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
{"tool": "custom_animation_fx", "params": {"op": "shake", "player_path": "/Main",
  "target_path": "Camera2D", "intensity": 10, "duration": 0.4, "seed": 7}}

{"tool": "custom_animation_fx", "params": {"op": "typewriter", "player_path": "/Main/HUD",
  "target_path": "DialogLabel", "steps": 40, "duration": 1.6}}

{"tool": "custom_animation_fx", "params": {"op": "wave", "player_path": "/Main/HUD",
  "target_paths": ["Card1", "Card2", "Card3"], "amplitude": 10, "phase_step": 0.15}}

{"tool": "custom_animation_fx", "params": {"op": "sprite_frames", "sprite_path": "/Main/Player",
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
| `blend_tree` | A recursive blend tree spec: `blend2`/`blend3`/`add2`/`add3`/`one_shot`/`time_scale`/`animation`, with nested state machines and blend spaces. The spec's root is wired to the tree's `output` node (an unconnected `output` builds cleanly and then plays nothing); the reply's `output_source` names the node it wired, which is the only way to read a connection back in 4.7. |
| `wire` | Ensures the tree exists, is active and pointed at the player; optionally sets a parameter. `create=false` turns the call into a check: a missing tree is reported instead of created. A named player is never given another player's tree — the lookup follows `anim_player` exactly, and `graph_get` lists the existing trees when it finds none. |
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
{"tool": "custom_animation_graph", "params": {"op": "state_machine", "player_path": "/Main",
  "states": [{"name": "idle", "animation": "idle"}, {"name": "walk", "animation": "walk"}],
  "transitions": [
    {"from": "idle", "to": "walk", "xfade": 0.2, "condition": "walking"},
    {"from": "walk", "to": "idle", "xfade": 0.2, "advance_expression": "!walking"}]}}

{"tool": "custom_animation_graph", "params": {"op": "blend_space", "player_path": "/Main",
  "dimensions": 1, "min": 0, "max": 2,
  "points": [{"animation": "idle", "position": 0}, {"animation": "walk", "position": 1},
             {"animation": "run", "position": 2}]}}

{"tool": "custom_animation_graph", "params": {"op": "locomotion", "player_path": "/Main",
  "mode": "state_machine", "start": "idle"}}

{"tool": "custom_animation_graph", "params": {"op": "one_shot_layer", "player_path": "/Main",
  "animation": "jump", "fadein": 0.1, "fadeout": 0.2}}
```

## `animation_library`

Reuse and interchange. Templates store a presets/fx/motion/rig call (its op and
params) as a named recipe in a project file; clip specs are a typed JSON format
for whole clips. File writes are **not** part of the undo stack (like the core's
`scene_save`); clip creation through `template_apply` / `spec_apply` is one
scene-pinned undo action.

| op | What it does |
| --- | --- |
| `template_save` | Store `{tool, forward_op, ...params}` under a name in `res://animation_toolkit/library.json`. `tool` is `animation_presets`, `animation_fx`, `animation_motion` or `animation_rig`. |
| `template_apply` | Run the stored op again, with per-call overrides (`player_path`, `target_path`, `animation_name`, any op param). `dry_run` works. |
| `template_list` | List templates with tool, op, description and params. |
| `template_delete` | Remove a template. |
| `spec_export` | Write a clip to JSON (`res://animation_toolkit/clips/<clip>.json` by default) — typed values, method and audio tracks, markers. |
| `spec_import` | Read and validate a spec file or inline spec; reports tracks, keys, paths and issues. |
| `spec_apply` | Build a clip from a spec file or inline spec, optionally remapping every track onto `target_path`. |

Spec format (versioned, values tagged by kind):

```json
{ "format": "godot-ai-animation-clip", "version": 1,
  "length": 1.0, "loop_mode": 2,
  "markers": [{"name": "peak", "time": 0.5, "color": {"kind": "color", "r": 1, "g": 1, "b": 1, "a": 1}}],
  "tracks": [{
    "type": 0, "path": "Sprite:position", "enabled": true, "interp": 0, "update_mode": 0,
    "keys": [{"time": 0.0, "value": {"kind": "vector2", "x": 0, "y": 0}, "transition": 1.0}]
  }] }
```

Notes:

- `spec_apply` resolves `target_path` the way the presets do: scene-absolute
  paths become root_node-relative track paths, relative paths are used as-is.
- Audio keys reference streams by `res://` path (resources cannot be inlined);
  a missing file is an error.
- The library file and spec files are project data - commit them if you want
  the recipes shared with the team.

### Examples

```json
{"tool": "custom_animation_library", "params": {"op": "template_save", "name": "button_pop",
  "tool": "animation_presets", "forward_op": "bounce", "intensity": 0.2, "duration": 0.5}}

{"tool": "custom_animation_library", "params": {"op": "template_apply", "name": "button_pop",
  "player_path": "/Main/HUD", "target_path": "MenuButton"}}

{"tool": "custom_animation_library", "params": {"op": "spec_export", "player_path": "/Main/HUD",
  "animation_name": "open"}}

{"tool": "custom_animation_library", "params": {"op": "spec_apply", "player_path": "/Main/HUD",
  "path": "res://animation_toolkit/clips/open.json",
  "target_path": "/Main/HUD/Panel2", "animation_name": "open_2"}}
```

## `animation_rig`

Served by **two** catalog families: `animation_rig` (promoted — this section's
poses, inspection and recipes) and `animation_rig_modifiers` (not promoted —
the five `*_setup` rows below, because the server promotes at most eight
tools). Call both through `custom_manage`, and pass the same params either way.

Phase 6a/6b: **poses and rig building**. A pose is portable, rest-relative data
— `{bone: {rotation delta, position delta, scale}}` — so it survives rig
changes, blends, mirrors and JSON round-trips, and so the same pose applies to
both human-dummy variants.

| op | What it does |
| --- | --- |
| `rig_chain` | Build bones from a spec (`bones`: name/parent/rest, rotation in degrees) or turn a Node3D/Node2D subtree into a skeleton. Creates the skeleton when `skeleton_path` is empty. A bone name containing `/` or `:` is refused before anything is committed: it would break the `Skeleton3D:<bone>:<property>` track paths built from it (dots are fine). |
| `ik_setup` | Attach a 3D IK modifier to a Skeleton3D, wire it to a target node and (optionally) a pole. `kind=spline` is the exception: `SplineIK3D` follows a **Path3D** (`target_path`, created at the end bone when omitted) because it has no target setting anywhere in its class chain. Chains are validated: `two_bone` needs exactly three parent-ordered bones (or two with `use_virtual_end`), the chain solvers a root and an end with the end below it. Default markers come from the **rest** frame, and a second marker asking for the same name gets its own (`IKTarget2`) so both paths still resolve. |
| `spring_setup` | Attach a `SpringBoneSimulator3D` with one spring per `springs` entry (root/end bone, stiffness, drag, gravity, radius, rotation axis, centre, collisions). `end_bone` defaults to the root's leaf. |
| `look_at_setup` | Attach a `LookAtModifier3D` so one bone tracks a target node (created a metre in front of the bone when omitted), with origin, limits, secondary rotation and turn duration. |
| `retarget_setup` | Attach a `RetargetModifier3D` under a source Skeleton3D so a child target skeleton follows it in model space, with an `auto` bone-name profile (built from the source), `humanoid`, or a `res://` profile. Refuses a map that matches nothing (or misses the hips/leg core the source actually has) instead of building a modifier that moves nothing, and reports `source_only_bones`, `target_only_bones` and mapped-parent mismatches. `move_target=false` **reconfigures the modifier that is already there** rather than adding an inert second one — and only for the source that modifier was built for. |
| `twist_setup` | Attach a `BoneTwistDisperser3D` so a twist applied to one bone is spread over the bones above it. `disperse` takes `{root_bone?, end_bone?, mode? (even\|weighted), weight_position?, extend_end_bone?, twist_from_rest?, twist_from?}`; the root/end default to the detected (or explicit) spine chain. Parameters Godot only reads in another mode are rejected instead of queued and ignored (`damping` is custom-mode only, `weight_position` is weighted-only, `twist_from_rest=false` needs an explicit reference quaternion), and a two-joint range sets `extend_end_bone` and warns that the twist lands whole. The response's `joint_bones` is the *predicted* list; `rig_get` reports the real one (`joints_pending` until Godot has built it on a later frame). |
| `walk_cycle` | Build a looping in-place walk from bone roles (auto-detected by name or given in `roles`): thigh swing, knee bend, counter-swinging arms and a hip bob. `arm_down` lowers the arms from the rest pose for T-pose rigs. |
| `idle_breathing` | Build a subtle looping idle: the whole torso chain breathes (ramping from the lower spine to the chest), a light head counter-move and an optional hip bob. |
| `blink` | Build a quick blink on the eye/eyelid bones - `scale` (default) or `rotate` - with an optional number of blinks per clip. |
| `jumping_jack` | Build a looping jack: arms swing from the rest pose to overhead (`amplitude`), thighs spread (`stride`), hips rise (`bob`). |
| `squat` | Build a looping squat with planted feet: the hips drop by `bob` metres and a two-bone solve bends each leg so the ankles stay at their rest positions (`amplitude` eases the arms forward). |
| `punch` | Build a looping boxing combo: guard, `cycles` alternating straight punches along the rig's facing direction (ankle -> toe), `bob` crouch. `amplitude` is the *total* torso twist in degrees, shared up the spine chain. |
| `bake_pose_sequence` | Sample a skeleton into a clip: seek the source clip on its AnimationPlayer, run the active modifiers (IK, springs, retarget) through the skeleton's update, then key the final pose (captured at `modification_processed`). Deterministic: every sample advances the skeleton by exactly the fps step (so springs integrate identically twice) and stateful modifiers are reset first. Restores **every** skeleton it touched - including a retarget's target - plus the player's animation, time and play state, and refuses to write a clip when no modifier reported in, because those poses would be the pre-modifier ones. The reply lists the `modifiers` it captured through, the `sample_delta` and the `restored_skeletons`. |
| `pose_save` | Capture a Skeleton3D/Skeleton2D pose (inline and/or `res://animation_toolkit/poses/<name>.json`). |
| `pose_apply` | Write a pose back: `blend` 0-1 toward it, `mirror` (L/R swap), `reset_first`, `bones` subset. One undo action. |
| `pose_blend` | Slerp/lerp two poses into a third (optionally mirrored and/or saved). |
| `pose_to_clip` | Keyframe a `[{pose, time, transition?, mirror?, aim?}]` sequence into an Animation clip. An `aim` entry solves a three-bone chain so the end bone's origin lands on a world `target` (see below). |
| `pose_list` | List saved pose files with their bone counts. |
| `rig_get` | Dump bones (index/parent/rest), the current pose, modifiers, spring settings, twist settings (with the joint list Godot really built) and issues. |

Notes:

- **Every `*_setup` verifies itself and rolls back on failure.** After the undo
  action commits, the op reads the modifier's settings back through the
  modifier and resolves what it just wired: `ik_setup` checks that the target
  (and pole) settings point at nodes that exist, `retarget_setup` checks that
  the target became a child of the modifier and that every mapped bone resolves
  on both skeletons, and spline IK additionally requires the `Path3D` to have
  curve points. If any of that is false the action is undone and the call
  returns a typed error — no setup reports success it cannot confirm.
- **A retarget target must end up a direct child of the modifier.**
  `RetargetModifier3D` only drives its own children, so a target left inside
  another node (a wrapper, a nested instanced scene) is refused with an
  explanation rather than accepted and left inert. Pass `move_target=false` to
  reconfigure an existing modifier instead of moving anything.
- **Modifiers are created inactive** (`active` defaults to false), because an
  active `SkeletonModifier3D` also drives the skeleton while you edit the scene.
  Pass `active=true` (or enable the modifier) when the scene is ready.
- **IK is 3D-only for now.** The 2D skeleton modification stack is Experimental
  in Godot 4.7, so `ik_setup` refuses 2D skeletons with a clear error; 2D chains
  can still be built with `rig_chain` and posed with `pose_apply` /
  `pose_to_clip`.
- **`retarget_setup` moves the target under the modifier** (`move_target`, on by
  default), because `RetargetModifier3D` only drives skeletons that are its own
  children. It refuses skeletons inside a non-editable scene instance, where the
  move (and the modifier itself) would not survive the scene save. `profile:
  "auto"` builds a profile from the source skeleton, so two rigs with the same
  bone names but different rests retarget without any setup; the response lists
  which profile bones mapped and which did not.
- **`rig_chain` bone specs** take `{name, parent?, position?, rotation?,
  scale?, length?}`. `position`/`scale` accept `[x, y, z]` or `{x, y, z}`,
  `rotation` is in degrees (XYZ euler for 3D, about Z for 2D), and `length` is
  the Bone2D length. Parents may be bones from the same spec or bones that
  already exist on the skeleton; cycles and unknown parents are refused.
- **Torso twist and lean are distributed over the spine chain**, not hard-coded
  per bone. Both families detect the chain (hips -> spine -> chest -> neck ->
  head on the human dummy) and take an explicit `spine_chain` when given, which
  must be one parent chain. The same distributor (`spec/spine_twist.gd`) serves
  the recipes, so a parameter means the same *total* on any rig:
  - `idle_cycle`: `overrides.twist` is the total twist in degrees, shared over
    the chain; `twist_spread` (0-1, also an override key) keeps it on the lower
    spine at 0 and spreads it over the whole chain at 1.
  - `walk_cycle` / `run_cycle` / `strafe_cycle`: the counter-rotation is weighted
    by chain position, and `overrides.chest_yaw` scales it (it used to be
    shadowed by a local of the same name, so setting it did nothing).
  - `turn_cycle`: the lead ramps up the chain and the head trails it, bounded per
    step, so a multi-step turn cannot corkscrew the spine.
  - `jump`: the lean ramps up the whole chain instead of bending at two bones.
  - `punch`: `amplitude` is the total torso twist, most of it in the upper chest.
- **`twist_setup` hands the distributing to the engine.** Godot 4.7 only builds a
  disperser's per-joint list once the modifier has been in the tree for a frame
  and the amounts are index-based, so the op sets root/end and the engine's
  `even` / `weighted` modes (plus `weight_position`, `damping`,
  `twist_from_rest`) and reports the joint bones it will use; custom per-joint
  amounts are set in the modifier's Inspector. An `end_bone` that is not below
  the `root_bone` is refused.
- **Bone clips are ordinary clips.** 3D bones key `TYPE_ROTATION_3D` tracks at
  paths like `Skeleton3D:B-thigh.R`; 2D bones key `Skeleton2D/Bone:rotation`
  value tracks. Every other toolkit op therefore works on them: `retime`,
  `mirror`, `reverse`, `amplitude`, `spec_export`, templates.
- **Lean clips**: `pose_to_clip` only emits tracks for bones that actually move,
  so a pose pair that waves an arm produces one track, not one per bone.
- **Contact keys (`aim`)**: a key may carry
  `aim: [{chain: [root, mid, end], target: [x, y, z], pole?: [x, y, z]}]`. The
  chain is solved analytically (law of cosines in the plane spanned by the
  shoulder-to-target line and the pole) so the **end bone's origin sits exactly
  on the world target**, and the keys carry that solution — no modifier, no
  runtime target node. The target is clamped to the chain's reach (and flagged
  in the response), `pole` chooses which way the mid bone bends (without it the
  base pose's bend is kept), and the base `pose` for that key is applied first,
  so an aim key can ride on a body pose. An aim-only key (no `pose`) starts from
  rest. The live skeleton is posed only to solve and is restored afterwards, so
  this is safe to run on a scene you are editing. Chain bones must be three
  (`root -> mid -> end`) and the solver is 3D-only.
- **Mirroring** follows the reflection rule: a rotation keeps its angle and
  mirrors its axis (`q = (x, -y, -z, w)`), positions negate X, scale is kept.
  L/R bones swap by name (`.L`/`.R`, `_L`/`_R`, `-L`/`-R`, `Left`/`Right`).
- **Rest-relative** storage means a pose saved from one rig applies to any rig
  with the same bone names — including the F/M human dummy pair.
- **Recipes aim bones at world directions.** `arm_down`, the arm raises in
  `jumping_jack`, the leg spread, the `squat` arms and the `punch` extension all
  rotate a bone from its rest direction toward a target direction, clamped so
  it never rotates past the target — so T-pose and A-pose rests both work.
  `squat` additionally solves each leg analytically (law of cosines in the
  sagittal plane) so the ankles stay at their rest positions, and `punch`
  derives the character's facing direction from the feet (ankle to toe), so the
  punches follow the rig instead of an assumed +Z.
- **Rig profiles.** Every recipe op takes `profile` (a name under
  `res://animation_toolkit/rig_profiles/` or a `res://` path). Roles saved by
  `animation_inspect rig_profile` are applied as if passed in `roles`; bones the
  profile names that are missing on this skeleton are ignored so detection can
  fill them in. Explicit `roles` still win over the profile.
- **`bake_pose_sequence` side effects**: it plays the source clip on the player
  and stops it afterwards (unless it was already playing); nodes other than the
  skeleton that the source clip animates are left at the last sampled time; and
  spring bones integrate with the frame delta rather than the sample step, so
  baked springs are approximate. Bakes are capped at 1200 samples
  (`duration x fps`) and the rig tool allows 30 s per call.
- **Players inside scene instances**: writing a clip to an AnimationPlayer that
  lives inside an instanced scene (a character scene dropped in a level, an
  imported FBX) only survives the scene save because the toolkit turns
  **Editable Children** on for those instance levels and swaps in a
  scene-local copy of the animation library. Both happen inside the same undo
  action; without them the editor silently drops the new clip on save.
- `rig_get` flags scaled skeletons (spring bones and IK assume unit scale) and
  clips that animate bones the skeleton does not have.

### Examples

```json
{"tool": "custom_animation_rig", "params": {"op": "pose_save",
  "skeleton_path": "/Main/Rig/Skeleton3D", "name": "wave_mid"}}

{"tool": "custom_animation_rig", "params": {"op": "pose_apply",
  "skeleton_path": "/Main/Rig/Skeleton3D", "name": "wave_mid", "blend": 0.5}}

{"tool": "custom_animation_rig", "params": {"op": "pose_blend",
  "from": "idle", "to": "wave_mid", "factor": 0.35, "name": "wave_low"}}

{"tool": "custom_animation_rig", "params": {"op": "pose_to_clip",
  "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D",
  "animation_name": "wave", "loop_mode": "linear",
  "keys": [{"name": "idle", "time": 0.0},
           {"name": "wave_mid", "time": 0.5, "transition": "ease_in_out"},
           {"name": "idle", "time": 1.0}]}}
```

## `animation_motion`

Procedural humanoid cycles. Unlike `animation_rig`'s sparse recipes, these build
**densely sampled** clips from analytic curves (24 keys/s by default) with the
legs solved by a two-bone IK, so planted feet stay planted, phase offsets give
follow-through, and the result looks smooth at any playback rate.

| op | Notes |
| --- | --- |
| `walk_cycle` | Full gait: contact/passing timing, pelvis bob (2x) + sway + yaw + roll, counter-rotating torso shared up the spine chain, arm swing with elbow and clavicle follow-through, head stabilisation, planted feet with heel-strike/toe-off roll. `speed` solves the stride from a target m/s. `stride`, `knee_bend` (a planted crouch), `arm_swing`, `bob`, `sway`, `lean`, `arm_down`, `chest_yaw`, `twist_spread`. |
| `run_cycle` | Same engine with a flight phase, a forward lean, a wider stride, bent elbows and a bigger bob. Use a shorter `duration` (0.5-0.7 s). |
| `strafe_cycle` | Looping sideways gait: the leading foot steps out, the trailing foot closes, the knees still bend forward and the pelvis shifts along the travel axis. `direction` left/right, `speed`-driven like the walk. |
| `idle_cycle` | A loopable idle with presence: a pronounced look-around (head yaw, with a second harmonic so it lingers left/right) and a torso twist shared up the spine chain over breathing, weight shift and seeded micro-noise. `look`, `twist` (the *total* twist in degrees, 22), `twist_spread`, `amplitude`, `head_amplitude`, `bob`, `sway`, `lean`. |
| `jump` | One-shot jump: anticipation crouch, launch, air arc, descend, landing absorb and recovery. Feet are planted before takeoff and after landing; `height`, `crouch`, `distance` (forward travel). Emits `takeoff` / `apex` / `land` markers. |
| `turn_cycle` | One-shot in-place pivot turn: anticipation, a stepping foot, stance feet held at their rest orientation, overshoot settle. `angle`, `direction`, `steps`. Emits `anticipate` / `step` / `settle` per step. |
| `walk_start` / `walk_stop` | Short blend in/out of a gait. The gait-facing end is sampled from the cycle at `phase`, so it matches frame-for-frame and can be concatenated or cross-faded. |
| `cycle` | Generic entry point: `preset` = `walk` / `run` / `idle`, same params as the dedicated ops. |
| `character_setup` | One call, one undo: builds `idle` + `walk` + `run` (plus `jump`/`turn_<dir>` when `include_jump`/`include_turn`), wires a locomotion blend space on speed — a jump one-shot layer when requested — creates the `AnimationTree`, sets the root-motion track on player and tree, and returns `speed_parameter`, `speed_values`, `jump_request_parameter` and a game-side `apply_snippet`. `speed`/`run_speed` become the blend positions; `overwrite` defaults to true so a re-run refreshes the set. |
| `secondary_motion` | Bakes **offline spring bones** into an existing clip: each name in `bones` (hair, tail, cloth root — must be unkeyed in the clip) lags behind its animated parent with a damped angular spring (`stiffness` 1/s², `damping` 1/s, 120/12 = snappy hair), keyed as ordinary rotation tracks. Deterministic; no live modifier needed. |

How motion is generated:

- **Analytic drivers, dense samples.** Each bone channel is a sine/noise curve
  (amplitude, frequency, phase, lag) composed in world space and converted into
  the bone's rest frame — so the same numbers read the same way on any rig.
- **Planted feet.** Per sample the hips and pelvis motion are applied, then each
  leg is solved (law of cosines in the sagittal plane) so the ankle follows its
  trajectory: the stance foot slides back at the cycle's ground speed, the swing
  foot arcs forward and up. The ankle is pitched through heel strike and toe-off
  and the toe bone is held on the ground while the foot rolls over it.
- **Speed-driven.** Pass `speed` (m/s) and the stride is solved from
  `speed * stance * duration / (2 * leg_length)`; unreachable speeds are clamped
  and reported in `warnings` with the duration that would work. `speed`,
  `stride_used` and `cadence` come back in the result.
- **Phase markers.** Gaits emit `contact.L/R`, `toe_off.L/R` and `passing.L/R`;
  jump and turn emit their phase cues. Hook footstep audio or gameplay events on
  them, or use them to phase-sync blends.
- **Multi-step pivots.** `turn_cycle steps: 2` splits a 180-degree turn into two
  pivots — each with its own anticipation, settle and the *opposite* foot lifting
  — so it reads as two weight shifts instead of one spin. The clip only carries
  body rotation, so re-base the root yaw between steps in your driver (or play
  the clip in place and rotate the rig in script); `steps: 1` is the classic
  single pivot. The torso lead is a bounded fraction of *each step's* angle and
  ramps up `spine_chain` (the head trails it), which is what stops a long spine
  from corkscrewing over a multi-step turn.
- **One torso chain, one meaning.** The chain is detected from the bone parents
  (or given as `spine_chain`, which must be one parent chain), and the
  per-bone amounts come from a shared distributor, so `twist`/`chest_yaw`/`lean`
  mean the same *total* on a 3-bone and a 6-bone spine. `twist_spread` (0-1)
  slides the idle and gait twist between the hips alone and the whole chain.
- **Loop closure by construction.** Integer frequencies and a final sample that
  re-evaluates phase 0 make every track close exactly; the commit pass also
  aligns quaternion hemispheres and snaps the loop seam.
- **Styles.** `style` = `default` / `relaxed` / `heavy` / `sneaky` scales the
  config before `overrides` (e.g. `{"stride": 18, "lag": 0.1}`), so one call can
  produce very different characters.
- **Root motion.** `root_motion=true` keys the hips forward at the implied speed
  and wires `AnimationPlayer.root_motion_track` in the same undo action (set
  `set_root_motion=false` to skip). Apply it in game code with
  `get_root_motion_position()` / `get_root_motion_rotation()` — and the
  `*_accumulator()` variants when the node itself rotates.
- T-pose rigs are detected: the arms are lowered automatically so the swing has
  a real axis (an explicit `arm_down` always wins). A-pose rigs are untouched.
- **Rig profiles.** Every cycle op takes `profile` (a name under
  `res://animation_toolkit/rig_profiles/` or a `res://` path); the roles saved
  by `animation_inspect rig_profile` are reused, explicit `roles` still win, and
  profile bones missing on this skeleton are ignored so detection fills them in.
- **`character_setup`** returns a snippet that feeds `velocity.length()` into
  `speed_parameter` each physics frame; the tree is created **inactive** by
  default like the graph ops (`active=true` to enable it), and root motion is
  wired on both the player and the tree.

### Examples

```json
{"tool": "custom_animation_motion", "params": {"op": "walk_cycle",
  "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D",
  "animation_name": "walk", "duration": 1.0, "loop_mode": "linear"}}

{"tool": "custom_animation_motion", "params": {"op": "character_setup",
  "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D",
  "speed": 1.4, "run_speed": 4.0, "include_jump": true}}

{"tool": "custom_animation_motion", "params": {"op": "run_cycle",
  "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D",
  "animation_name": "run", "duration": 0.6, "loop_mode": "linear", "style": "heavy"}}

{"tool": "custom_animation_motion", "params": {"op": "idle_cycle",
  "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D",
  "animation_name": "idle", "duration": 3.0, "loop_mode": "linear",
  "overrides": {"look": 18, "twist": 22, "twist_spread": 0.8}}}

{"tool": "custom_animation_motion", "params": {"op": "secondary_motion",
  "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D",
  "animation_name": "walk", "bones": ["B-hair01", "B-hair02"],
  "stiffness": 120.0, "damping": 12.0}}

{"tool": "custom_animation_motion", "params": {"op": "jump",
  "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D",
  "animation_name": "jump", "duration": 1.2, "height": 0.6, "crouch": 0.25}}

{"tool": "custom_animation_motion", "params": {"op": "strafe_cycle",
  "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D",
  "animation_name": "strafe_left", "duration": 0.9, "direction": "left",
  "speed": 1.0, "loop_mode": "linear"}}

{"tool": "custom_animation_motion", "params": {"op": "walk_start",
  "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D",
  "animation_name": "walk_start", "duration": 0.35, "phase": 0.0}}
```
