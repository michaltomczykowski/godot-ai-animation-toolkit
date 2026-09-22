# Op index (generated)

Generated from `registry/op_registry.gd` by `tools/gen_docs.ps1` — do not edit by hand.

Every tool commits one scene-pinned undo action per call and returns the same
error codes as the core tools (`INVALID_PARAMS`, `VALUE_OUT_OF_RANGE`,
`WRONG_TYPE`, `NODE_NOT_FOUND`, `PROPERTY_NOT_ON_CLASS`, `EDITOR_NOT_READY`).

## `animation_presets`

One-call animation presets for an AnimationPlayer.

Handler: `res://addons/godot_ai_animation/handlers/generate.gd`

| op | What it does | Params |
| --- | --- | --- |
| `pulse` | Breathing / ping-pong on any property (scale shortcut, or typed from_value/to_value). | `player_path`, `target_path`, `property`, `from_scale`, `to_scale`, `from_value`, `to_value`, `duration`, `loop_mode`, `animation_name`, `overwrite`, `dry_run` |
| `bounce` | Center-pivot scale overshoot with settle-back — UI press feedback. | `player_path`, `target_path`, `intensity`, `duration`, `animation_name`, `overwrite`, `dry_run` |
| `orbit` | Circular position orbit (XZ plane for 3D, screen space for 2D/Control). | `player_path`, `target_path`, `radius`, `clockwise`, `duration`, `loop_mode`, `animation_name`, `overwrite`, `dry_run` |
| `sweep` | Full-turn rotation sweep — radar scans, cooldown rings. | `player_path`, `target_path`, `turns`, `clockwise`, `duration`, `loop_mode`, `animation_name`, `overwrite`, `dry_run` |
| `drift` | One-axis position offset — scanlines, marquee, conveyor. | `player_path`, `target_path`, `axis`, `distance`, `duration`, `loop_mode`, `animation_name`, `overwrite`, `dry_run` |
| `spin` | 3D quaternion turn around local Y. | `player_path`, `target_path`, `turns`, `clockwise`, `duration`, `loop_mode`, `animation_name`, `overwrite`, `dry_run` |
| `float` | 3D bob: rise + scale + turn through the transform. | `player_path`, `target_path`, `height`, `scale`, `turns`, `duration`, `loop_mode`, `animation_name`, `overwrite`, `dry_run` |
| `stagger` | Reveal a list of targets one after another in one clip. | `player_path`, `target_paths`, `use_selection`, `effect`, `direction`, `distance`, `stagger`, `duration`, `animation_name`, `overwrite`, `dry_run` |
| `showcase` | Build a runnable demo of every preset (7 nodes + 7 autoplaying clips). | `parent_path`, `name`, `overwrite`, `dry_run` |

### `animation_presets` parameters

| Param | Type | Notes |
| --- | --- | --- |
| `op` | string: pulse \| bounce \| orbit \| sweep \| drift \| spin \| float \| stagger \| showcase | Which preset to build. |
| `player_path` | string | Scene path to the AnimationPlayer (it must already exist). Not used by showcase. |
| `target_path` | string | Node to animate: relative to the player's root_node (e.g. "Button") or scene-absolute (e.g. "/Main/Button"). Not used by showcase. |
| `parent_path` | string | showcase: parent node for the demo subtree (default: the edited scene root). |
| `name` | string | showcase: name for the demo subtree (default "AnimationShowcase"). |
| `animation_name` | string | Clip name; defaults to the preset name. |
| `overwrite` | boolean (default `false`) | Replace an existing clip with the same name. |
| `property` | string | pulse: property to breathe (default "scale"). |
| `from_scale` | number (default `1.0`) |  |
| `to_scale` | number (default `1.1`) |  |
| `from_value` | any | pulse: start value for a non-scale property (typed to the property). |
| `to_value` | any | pulse: end value. |
| `intensity` | number | bounce: peak overshoot fraction (default 0.15). |
| `radius` | number | orbit: circle radius (default 1.0 for 3D, 100.0 for 2D). |
| `clockwise` | boolean (default `true`) |  |
| `turns` | number | sweep/spin/float: full turns (spin/sweep default 1.0; float default 0.0). |
| `height` | number | float: vertical offset (default 0.7; negative bobs down). |
| `scale` | number | float: peak scale factor (default 1.25). |
| `target_paths` | array | stagger: ordered targets to reveal, each relative to the player's root_node or scene-absolute. |
| `use_selection` | boolean (default `false`) | stagger: use the editor's selection (in selection order) instead of target_paths. |
| `effect` | string: fade_in \| slide_in \| pop_in | stagger: reveal effect applied to every target. |
| `stagger` | number | stagger: seconds between targets (default 0.06). |
| `direction` | string: left \| right \| up \| down | stagger slide_in: direction the items travel from (default left). |
| `axis` | string: x \| y \| z | drift: axis to offset along (z only for 3D targets). |
| `distance` | number | orbit/sweep/drift distance (defaults by dimension). |
| `duration` | number | Clip length in seconds. |
| `loop_mode` | string: none \| linear \| pingpong | Drift refuses "linear" (the clip ends at a net offset). |
| `dry_run` | boolean (default `false`) | Report what the call would build without committing anything (no undo action). |

Required: `op`, `player_path`, `target_path`.

### Examples

```json
{"duration":1.2,"from_value":0.2,"loop_mode":"pingpong","op":"pulse","player_path":"/Main/HUD","property":"modulate:a","target_path":"Label","to_value":1.0}
{"intensity":0.2,"op":"bounce","player_path":"/Main/HUD","target_path":"Button"}
{"duration":3.0,"loop_mode":"linear","op":"orbit","player_path":"/Main/HUD","radius":80.0,"target_path":"Satellite"}
{"loop_mode":"linear","op":"sweep","player_path":"/Main/HUD","target_path":"CooldownRing","turns":1.0}
{"axis":"x","distance":480.0,"duration":2.0,"loop_mode":"pingpong","op":"drift","player_path":"/Main","target_path":"Scanline"}
{"loop_mode":"linear","op":"spin","player_path":"/Main","target_path":"Pickup","turns":1.0}
{"duration":2.4,"height":0.4,"loop_mode":"pingpong","op":"float","player_path":"/Main","scale":1.1,"target_path":"Pickup"}
{"direction":"left","duration":0.3,"effect":"slide_in","op":"stagger","player_path":"/Main/HUD","stagger":0.08,"target_paths":["Item1","Item2","Item3"]}
{"op":"showcase","parent_path":"/Main"}
```

## `animation_edit`

Edit an existing Animation clip in place.

Handler: `res://addons/godot_ai_animation/handlers/edit.gd`

| op | What it does | Params |
| --- | --- | --- |
| `retime` | Scale the clip's timeline by `factor` or to `length` (optionally keys_only). | `player_path`, `animation_name`, `factor`, `length`, `keys_only`, `dry_run` |
| `retarget` | Rewrite track paths — rename a node, or bulk-remap a subtree prefix after a refactor. | `player_path`, `animation_name`, `from_path`, `to_path`, `mode`, `paths`, `dry_run` |
| `reverse` | Mirror every key time about the length so the clip plays backwards. | `player_path`, `animation_name`, `dry_run` |
| `mirror` | Mirror position/rotation (and optionally scale) across a plane, about an optional pivot. | `player_path`, `animation_name`, `axis`, `pivot`, `include_scale`, `dry_run` |
| `offset` | Shift every key in time (optionally wrapping inside the clip length). | `player_path`, `animation_name`, `delta`, `wrap`, `dry_run` |
| `ease_range` | Set the per-key transition on every value key inside a time range. | `player_path`, `animation_name`, `from`, `to`, `transition`, `dry_run` |
| `set_interp` | Set track-level interpolation (linear/nearest/cubic) on value tracks, optionally one track. | `player_path`, `animation_name`, `interpolation`, `track_path`, `dry_run` |
| `trim` | Keep only a time range, shifted to 0, with optional sampled boundary keys. | `player_path`, `animation_name`, `from`, `to`, `keep_bounds`, `dry_run` |
| `split_at` | Cut one clip into two at a time; the tail keeps the name, the head gets head_name. | `player_path`, `animation_name`, `time`, `head_name`, `overwrite`, `dry_run` |
| `merge` | Concatenate clips (optionally across players) into one, with an optional gap. | `player_path`, `animation_name`, `sources`, `new_name`, `gap`, `overwrite`, `dry_run` |
| `amplitude` | Scale key deltas about a baseline — soften or exaggerate a clip without rebuilding it. | `player_path`, `animation_name`, `factor`, `baseline`, `dry_run` |
| `loop` | Set the loop mode, optionally making a linear loop seamless. | `player_path`, `animation_name`, `loop_mode`, `make_seamless`, `dry_run` |
| `key_edit` | Add, set, remove or move a single key on a track. | `player_path`, `animation_name`, `action`, `track_path`, `track_index`, `time`, `value`, `transition`, `new_time`, `tolerance`, `dry_run` |
| `cleanup` | Drop redundant keys and empty tracks (dedupe holds, optional minimum gap). | `player_path`, `animation_name`, `tolerance`, `min_gap`, `drop_empty_tracks`, `dry_run` |

### `animation_edit` parameters

| Param | Type | Notes |
| --- | --- | --- |
| `op` | string: retime \| retarget \| reverse \| mirror \| offset \| ease_range \| set_interp \| trim \| split_at \| merge \| amplitude \| loop \| key_edit \| cleanup | Which edit to apply. |
| `player_path` | string | Scene path to the AnimationPlayer that owns the clip. |
| `animation_name` | string | Name of the clip to edit (merge: the default player for sources without one). |
| `factor` | number | retime: time multiplier (>0). amplitude: value multiplier (1.0 = unchanged, 0.0 = flat). |
| `length` | number | retime: target clip length in seconds (alternative to factor). |
| `keys_only` | boolean (default `false`) | retime: change the clip length but leave key times alone. |
| `from_path` | string | retarget: track path (mode=exact) or node path (mode=node/prefix) to rewrite. |
| `to_path` | string | retarget: replacement path. |
| `mode` | string: node \| prefix \| exact | retarget: node = same node part, property kept; prefix = node path or subtree; exact = whole track path. |
| `paths` | array | retarget: batch of {from, to, mode} remaps applied in order (alternative to from_path/to_path). |
| `axis` | string | mirror: plane(s) to mirror across — any of "x", "y", "z" (e.g. "x" or "xy"). |
| `pivot` | any | mirror: pivot for position tracks ({x,y[,z]}); default origin. |
| `include_scale` | boolean (default `false`) | mirror: also negate scale components on the mirrored axes. |
| `delta` | number | offset: seconds to shift every key (may be negative). |
| `wrap` | boolean (default `false`) | offset: rotate the shift inside the clip length (loop phase shift) instead of extending it. |
| `from` | number | ease_range/trim: start of the time range (default 0). |
| `to` | number | ease_range/trim: end of the time range (default clip length). |
| `transition` | any | ease_range/key_edit: per-key transition — "linear", "ease_in", "ease_out", "ease_in_out", or a number. |
| `interpolation` | string: linear \| nearest \| cubic | set_interp: track interpolation (cubic only for position/rotation/scale 3D tracks). |
| `track_path` | string | set_interp/key_edit: track to target (e.g. "Sprite:position"). key_edit also accepts track_index. |
| `track_index` | integer | key_edit: track index (alternative to track_path). |
| `keep_bounds` | boolean (default `true`) | trim: sample keys at both cut edges so the motion at the edges survives. |
| `time` | number | split_at: cut time. key_edit: key time to add/set/remove/move. |
| `head_name` | string | split_at: name for the head clip (default "<name>_a"; the tail keeps the original name). |
| `sources` | array | merge: clips to concatenate as {animation_name, player_path?}; defaults to the edited player. |
| `new_name` | string | merge/split_at: name for the produced clip (merge default "<first>_merged"). |
| `gap` | number | merge: seconds of silence inserted between clips. |
| `overwrite` | boolean (default `false`) | merge/split_at: replace an existing clip with the produced name. |
| `baseline` | any | amplitude: value the deltas are measured from (default: each track's first key). |
| `loop_mode` | string: none \| linear \| pingpong | loop: new loop mode. |
| `make_seamless` | boolean (default `false`) | loop: append a final key equal to the first so a linear loop wraps without a jump. |
| `action` | string: add \| set \| remove \| move | key_edit: what to do with the key. |
| `value` | any | key_edit add/set: new key value (typed to the track); for method tracks, the method name. |
| `new_time` | number | key_edit move: new key time. |
| `tolerance` | number | key_edit/cleanup: match/equality tolerance in seconds or units (default 0.001 / 0.0001). |
| `min_gap` | number | cleanup: drop keys closer than this to the previous kept key (default 0 = keep all). |
| `drop_empty_tracks` | boolean (default `true`) | cleanup: remove tracks that end up with no keys. |
| `dry_run` | boolean (default `false`) | Report what the edit would produce without committing anything (no undo action). |

Required: `op`, `player_path`, `animation_name`.

### Examples

```json
{"animation_name":"open","factor":0.5,"op":"retime","player_path":"/Main/HUD"}
{"animation_name":"open","from_path":"Panel","mode":"prefix","op":"retarget","player_path":"/Main/HUD","to_path":"Popup/Panel"}
{"animation_name":"open","op":"reverse","player_path":"/Main/HUD"}
{"animation_name":"walk","axis":"x","op":"mirror","pivot":{"x":0,"y":0},"player_path":"/Main"}
{"animation_name":"pulse","delta":0.3,"op":"offset","player_path":"/Main/HUD","wrap":true}
{"animation_name":"open","from":0.0,"op":"ease_range","player_path":"/Main/HUD","to":0.4,"transition":"ease_out"}
{"animation_name":"walk","interpolation":"nearest","op":"set_interp","player_path":"/Main","track_path":"Sprite:frame"}
{"animation_name":"walk","from":0.2,"op":"trim","player_path":"/Main","to":0.8}
{"animation_name":"walk","op":"split_at","player_path":"/Main","time":0.5}
{"animation_name":"intro","gap":0.1,"new_name":"full","op":"merge","player_path":"/Main","sources":[{"animation_name":"intro"},{"animation_name":"loop"}]}
{"animation_name":"bounce","factor":0.5,"op":"amplitude","player_path":"/Main/HUD"}
{"animation_name":"walk","loop_mode":"linear","make_seamless":true,"op":"loop","player_path":"/Main"}
{"action":"set","animation_name":"open","op":"key_edit","player_path":"/Main/HUD","time":0.2,"track_path":"Panel:position","value":{"x":10,"y":0}}
{"animation_name":"walk","min_gap":0.01,"op":"cleanup","player_path":"/Main","tolerance":0.0001}
```

## `animation_inspect`

Read-only inspection, auditing and dry runs.

Handler: `res://addons/godot_ai_animation/handlers/inspect.gd`

| op | What it does | Params |
| --- | --- | --- |
| `describe` | Human-readable summary of one clip or every clip on a player. | `player_path`, `animation_name`, `max_tracks` |
| `timeline` | Per-track key table (times, values, transitions) for one clip. | `player_path`, `animation_name`, `track_path`, `include_values`, `max_keys` |
| `audit` | Scene or player health check: broken paths, dead clips, loop seams, autoplay conflicts. | `player_path`, `severity`, `include_info` |
| `compare` | Diff two clips: length, loop mode, track paths, key counts and value deltas. | `player_path`, `animation_name`, `other_animation_name`, `other_player_path`, `tolerance`, `max_keys` |
| `stats` | Clip/track/key totals, track-type histogram and loop-mode breakdown. | `player_path` |
| `dry_run` | Run any presets/edit op and report the result without committing. | `tool`, `forward_op`, `player_path`, `animation_name` |
| `help` | Op index from the registry: names, summaries, params and examples. | `tool`, `op_name` |

### `animation_inspect` parameters

| Param | Type | Notes |
| --- | --- | --- |
| `op` | string: describe \| timeline \| audit \| compare \| stats \| dry_run \| help | Which inspection to run. |
| `player_path` | string | Scene path to an AnimationPlayer. Omit for audit/stats to scan every player in the edited scene. |
| `animation_name` | string | Clip to inspect (describe/timeline/compare). Omit for describe to summarise every clip on the player. |
| `other_animation_name` | string | compare: the clip to diff against. |
| `other_player_path` | string | compare: player holding the other clip (default: the same player). |
| `track_path` | string | timeline: only this track (e.g. "Sprite:position"). |
| `include_values` | boolean (default `true`) | timeline: include each key's value. |
| `max_keys` | integer | timeline/compare: cap on returned keys (default 200). |
| `max_tracks` | integer | describe: cap on returned tracks per clip (default 64). |
| `severity` | string: all \| error \| warning \| info | audit: only findings of this severity (default all). |
| `include_info` | boolean (default `true`) | audit: include info-level findings (unused clips, constant tracks). |
| `tolerance` | number | compare: value comparison tolerance (default 0.0001). |
| `tool` | string: animation_presets \| animation_edit | dry_run: which tool to run. help: which tool's ops to list (omit for all). |
| `forward_op` | string | dry_run: the presets/edit op to run (e.g. "retime"); its own params go in the same call. |
| `op_name` | string | help: only this op (omit to list the tool's whole index). |

Required: `op`.

### Examples

```json
{"animation_name":"open","op":"describe","player_path":"/Main/HUD"}
{"animation_name":"walk","max_keys":50,"op":"timeline","player_path":"/Main"}
{"op":"audit","severity":"warning"}
{"animation_name":"walk","op":"compare","other_animation_name":"walk_fast","player_path":"/Main"}
{"op":"stats"}
{"animation_name":"walk","factor":0.5,"forward_op":"retime","op":"dry_run","player_path":"/Main","tool":"animation_edit"}
{"op":"help","tool":"animation_edit"}
```
