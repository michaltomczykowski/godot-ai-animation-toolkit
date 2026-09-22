# Godot AI Animation Toolkit (addon)

Five custom MCP tools for Godot AI agents, built on one declarative clip-spec
engine:

- **`animation_presets`** (promoted to `custom_animation_presets`) — build clips
  in one call.
- **`animation_edit`** (promoted to `custom_animation_edit`) — edit any existing
  clip in place, hand-authored ones included.
- **`animation_fx`** (promoted to `custom_animation_fx`) — generators for game
  feel, UI, sprites and audio: shake, zoom_punch, hit_flash, damage_bar,
  typewriter, progress_fill, counter, dialog_pop, transition, wave, spring,
  pendulum, path_follow, flipbook, sprite_frames, audio_cue.
- **`animation_graph`** (promoted to `custom_animation_graph`) — AnimationTree
  authoring: state machines, blend spaces, blend trees, `wire`, `graph_get`,
  `locomotion`, `one_shot_layer`, `additive_lean`.
- **`animation_inspect`** (promoted to `custom_animation_inspect`) — read-only
  inspection, auditing and dry runs.

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

## `animation_fx`

| op | What it builds |
| --- | --- |
| `shake` | Seeded decaying positional noise (deterministic per seed). |
| `zoom_punch` | Camera punch on `Camera2D.zoom` / `Camera3D.fov`. |
| `hit_flash` | `modulate` flash and back, N times. |
| `damage_bar` | Hold, then ease to the new value (delayed ghost bar). |
| `typewriter` | `visible_ratio` reveal, smooth or character-stepped. |
| `progress_fill` | Numeric fill for ProgressBar `value` or any float. |
| `counter` | Rolling numbers through a method track with formatted text. |
| `dialog_pop` | Scale through an overshoot with an optional fade. |
| `transition` | Full-screen fade or wipe (pivot recentered). |
| `wave` | Cascading sine bob, one track per target. |
| `spring` | Damped spring settle to position + offset. |
| `pendulum` | Swinging rotation with optional decay. |
| `path_follow` | Follow a Path2D/Path3D curve. |
| `flipbook` | Step a Sprite2D's `frame`. |
| `sprite_frames` | Slice a spritesheet into a SpriteFrames resource. |
| `audio_cue` | Schedule an audio stream as a one-key audio clip. |

## `animation_graph`

| op | What it builds |
| --- | --- |
| `state_machine` | State machine root: states, transitions, xfade, conditions, advance/switch modes. |
| `blend_space` | 1D/2D blend space from clips at positions. |
| `blend_tree` | Recursive blend tree (blend2/blend3/add2/add3/one_shot/time_scale). |
| `wire` | Ensure the tree exists, is active, and optionally set a parameter. |
| `graph_get` | Dump a graph + flag missing clips / inactive trees. |
| `locomotion` | Ready-made idle/walk/run blend space or `walking`/`running` state machine. |
| `one_shot_layer` | Layer a one-shot (jump/attack) over the current root. |
| `additive_lean` | Additively layer a lean/tilt clip over the current root. |

## `animation_inspect`

| op | What it reports |
| --- | --- |
| `describe` | Human-readable summary per clip (tracks, keys, length, loop, autoplay, broken paths). |
| `timeline` | Per-track key table with serialized values and transitions. |
| `audit` | Scene/player health check: broken paths, zero-length clips, duplicate keys, loop seams, autoplay conflicts, unused clips. |
| `compare` | Diff two clips (length, loop mode, track paths, key deltas). |
| `stats` | Clip/track/key totals, track-type histogram, loop-mode breakdown. |
| `dry_run` | Run any presets/edit op and report the result without committing. |
| `help` | Op index from the registry. |

Read-only: it never touches the undo stack, so `batch_execute` (which requires
undoable commands) rejects it — call it directly.

## Architecture

- `spec/clip_spec.gd` — declarative clip data (tracks, typed keys, markers).
- `spec/spec_builder.gd` / `spec/spec_io.gd` — spec ⇄ `Animation`.
- `spec/spec_modifiers.gd` — pure spec → spec transforms (tier-1 tested).
- `registry/op_registry.gd` — single source of truth for tool descriptions,
  params schemas, op metadata, and `docs/op-index.md`.
- `spec/fx_specs.gd` — pure spec builders for the `animation_fx` generators.
- `spec/graph_builders.gd` — pure AnimationNode* graph builders + dumps.
- `handlers/generate.gd`, `handlers/fx.gd`, `handlers/graph.gd`,
  `handlers/edit.gd`, `handlers/inspect.gd` — tool entry points sharing
  `handlers/animation_tool_base.gd` (one undo action per mutating call;
  `dry_run` skips the commit).

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
