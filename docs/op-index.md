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

## `animation_fx`

One-call generators for game feel, UI, sprites and audio.

Handler: `res://addons/godot_ai_animation/handlers/fx.gd`

| op | What it does | Params |
| --- | --- | --- |
| `shake` | Seeded decaying screen shake on a camera/control position. | `player_path`, `target_path`, `intensity`, `duration`, `frequency`, `decay`, `seed`, `axis`, `property`, `animation_name`, `overwrite`, `dry_run` |
| `zoom_punch` | Camera punch: overshoot then settle (Camera2D zoom / Camera3D fov). | `player_path`, `target_path`, `amount`, `duration`, `peak_ratio`, `animation_name`, `overwrite`, `dry_run` |
| `hit_flash` | Flash a CanvasItem's modulate and back (damage feedback). | `player_path`, `target_path`, `color`, `duration`, `count`, `animation_name`, `overwrite`, `dry_run` |
| `damage_bar` | Delayed follow-up bar: hold, then ease to the new value. | `player_path`, `target_path`, `property`, `from`, `to`, `delay`, `duration`, `animation_name`, `overwrite`, `dry_run` |
| `typewriter` | Reveal text with visible_ratio, smoothly or in character steps. | `player_path`, `target_path`, `property`, `duration`, `steps`, `delay`, `from_ratio`, `to_ratio`, `animation_name`, `overwrite`, `dry_run` |
| `progress_fill` | Fill a numeric property (ProgressBar value, modulate:a, custom float). | `player_path`, `target_path`, `property`, `from`, `to`, `duration`, `delay`, `animation_name`, `overwrite`, `dry_run` |
| `counter` | Rolling numbers via a method track calling a setter with formatted text. | `player_path`, `target_path`, `from`, `to`, `steps`, `duration`, `format`, `prefix`, `suffix`, `method`, `animation_name`, `overwrite`, `dry_run` |
| `dialog_pop` | Modal entrance: scale through an overshoot, optionally fading in. | `player_path`, `target_path`, `from_scale`, `overshoot`, `duration`, `fade`, `animation_name`, `overwrite`, `dry_run` |
| `transition` | Full-screen fade or wipe on an overlay Control. | `player_path`, `target_path`, `mode`, `duration`, `animation_name`, `overwrite`, `dry_run` |
| `wave` | Cascading sine bob for a list of targets (or the editor selection). | `player_path`, `target_paths`, `use_selection`, `axis`, `amplitude`, `period`, `phase_step`, `cycles`, `loop_mode`, `animation_name`, `overwrite`, `dry_run` |
| `spring` | Damped spring settle from the current position to position + offset. | `player_path`, `target_path`, `offset`, `frequency`, `damping`, `duration`, `samples`, `animation_name`, `overwrite`, `dry_run` |
| `pendulum` | Swinging rotation with optional decay (2D rotation, 3D local Z). | `player_path`, `target_path`, `amplitude`, `period`, `duration`, `decay`, `animation_name`, `overwrite`, `dry_run` |
| `path_follow` | Follow a Path2D/Path3D curve by sampling it into position keys. | `player_path`, `target_path`, `path_node`, `duration`, `samples`, `loop_mode`, `animation_name`, `overwrite`, `dry_run` |
| `flipbook` | Step a Sprite2D's frame through a range with nearest interpolation. | `player_path`, `target_path`, `property`, `frames`, `fps`, `from_frame`, `loop_mode`, `animation_name`, `overwrite`, `dry_run` |
| `sprite_frames` | Slice a spritesheet into a SpriteFrames resource and assign it to an AnimatedSprite2D. | `sprite_path`, `texture`, `hframes`, `vframes`, `fps`, `loop`, `from_frame`, `to_frame`, `play`, `animation_name`, `overwrite`, `dry_run` |
| `audio_cue` | Schedule an audio stream as a one-key audio clip on the player. | `player_path`, `target_path`, `stream`, `time`, `start_offset`, `end_offset`, `animation_name`, `overwrite`, `dry_run` |

### `animation_fx` parameters

| Param | Type | Notes |
| --- | --- | --- |
| `op` | string: shake \| zoom_punch \| hit_flash \| damage_bar \| typewriter \| progress_fill \| counter \| dialog_pop \| transition \| wave \| spring \| pendulum \| path_follow \| flipbook \| sprite_frames \| audio_cue | Which generator to run. |
| `player_path` | string | Scene path to the AnimationPlayer (not used by sprite_frames). |
| `target_path` | string | Node to animate, relative to the player's root_node or scene-absolute. |
| `animation_name` | string | Clip name; defaults to the op name. |
| `overwrite` | boolean (default `false`) | Replace an existing clip with the same name. |
| `property` | string | Property to animate when the op allows one (shake: position; typewriter: visible_ratio; damage_bar/progress_fill: value; flipbook: frame). |
| `duration` | number | Clip length in seconds (defaults per op: 0.4 shake, 0.25 zoom_punch, 0.18 hit_flash, 0.4 damage_bar, 1.5 typewriter, 0.8 progress_fill, 1.0 counter, 0.35 dialog_pop, 0.5 transition, 1.0 spring, 2.0 pendulum, 2.0 path_follow). |
| `intensity` | number | shake: peak offset in pixels/units (default 8). |
| `frequency` | number | shake/spring: oscillations per second (default 20 / 2). |
| `decay` | number | shake/pendulum: falloff per clip (1.0 = none, 0.1 = settled; default 0.15 / 1.0). |
| `seed` | integer | shake: deterministic noise seed (default 0). |
| `axis` | string | shake/wave: axes to move along, any of "x", "y", "z" (default xy for 2D, xyz for 3D). |
| `amount` | number | zoom_punch: fractional punch (0.08 = +8%). |
| `peak_ratio` | number | zoom_punch: when the peak happens, 0-1 (default 0.3). |
| `color` | any | hit_flash: flash color (hex string or {r,g,b[,a]}); transition: overlay color. |
| `count` | integer | hit_flash: number of flashes (default 1). |
| `steps` | integer | typewriter: discrete characters (0 = smooth). counter: number of increments. |
| `delay` | number | typewriter/progress_fill/damage_bar: seconds to hold before the motion. |
| `from_ratio` | number | typewriter: starting visible_ratio (default 0). |
| `to_ratio` | number | typewriter: ending visible_ratio (default 1). |
| `from` | number | progress_fill/counter/damage_bar: starting value (default: the property's current value). |
| `to` | number | progress_fill/counter/damage_bar: ending value. |
| `format` | string | counter: printf format for the number (default "%d"). |
| `prefix` | string | counter: text before the number. |
| `suffix` | string | counter: text after the number. |
| `method` | string | counter: setter called with the formatted string (default "set_text"). |
| `target_paths` | array | wave: ordered targets to bob (relative to the player's root_node or scene-absolute). |
| `use_selection` | boolean (default `false`) | wave: use the editor's selection instead of target_paths. |
| `amplitude` | number | wave: bob height (default 12). pendulum: swing in degrees (default 18). |
| `period` | number | wave/pendulum: seconds per cycle (default 1.2 / 1.0). |
| `phase_step` | number | wave: seconds each following target lags (default 0.12). |
| `cycles` | integer | wave: loops of the sine in the clip (default 1). |
| `offset` | any | spring: travel offset as {x,y[,z]} matching the target's position type. |
| `damping` | number | spring: 0-1 damping ratio (default 0.35; >= 1 is critically damped). |
| `samples` | integer | spring/path_follow: key samples (default 30 / 24). |
| `path_node` | string | path_follow: scene path to the Path2D/Path3D to follow. |
| `frames` | integer | flipbook: number of frames to step through. |
| `fps` | number | flipbook/sprite_frames: frames per second (default 12). |
| `from_frame` | integer | flipbook/sprite_frames: first frame index (default 0). |
| `to_frame` | integer | sprite_frames: last frame index (default: the last cell). |
| `sprite_path` | string | sprite_frames: scene path to the AnimatedSprite2D. |
| `texture` | string | sprite_frames: res:// path of the spritesheet texture. |
| `hframes` | integer | sprite_frames: sheet columns (default 4). |
| `vframes` | integer | sprite_frames: sheet rows (default 1). |
| `loop` | boolean (default `true`) | sprite_frames: loop the animation. |
| `play` | boolean (default `true`) | sprite_frames: start playing after assigning. |
| `stream` | string | audio_cue: res:// path of the audio stream. |
| `time` | number | audio_cue: when the cue fires (default 0). |
| `start_offset` | number | audio_cue: trim from the start of the stream. |
| `end_offset` | number | audio_cue: trim from the end of the stream. |
| `mode` | string: fade_in \| fade_out \| wipe_right \| wipe_left \| wipe_up \| wipe_down | transition: which effect to build. |
| `from_scale` | number | dialog_pop: starting scale factor (default 0.85). |
| `overshoot` | number | dialog_pop: peak scale factor (default 1.06). |
| `fade` | boolean (default `true`) | dialog_pop: also fade the alpha in. |
| `loop_mode` | string: none \| linear \| pingpong | wave/path_follow/flipbook: loop mode (default linear / none / linear). |
| `dry_run` | boolean (default `false`) | Report what the call would build without committing anything (no undo action). |

Required: `op`.

### Examples

```json
{"duration":0.4,"intensity":10,"op":"shake","player_path":"/Main","seed":7,"target_path":"Camera2D"}
{"amount":0.12,"op":"zoom_punch","player_path":"/Main","target_path":"Camera2D"}
{"color":"#ffffff","count":2,"op":"hit_flash","player_path":"/Main","target_path":"Player"}
{"delay":0.3,"op":"damage_bar","player_path":"/Main/HUD","target_path":"GhostBar","to":40}
{"duration":1.6,"op":"typewriter","player_path":"/Main/HUD","steps":40,"target_path":"DialogLabel"}
{"duration":0.6,"op":"progress_fill","player_path":"/Main/HUD","target_path":"HealthBar","to":100}
{"from":0,"op":"counter","player_path":"/Main/HUD","prefix":"$","target_path":"ScoreLabel","to":1250}
{"duration":0.35,"op":"dialog_pop","player_path":"/Main/HUD","target_path":"DialogPanel"}
{"duration":0.5,"mode":"fade_out","op":"transition","player_path":"/Main","target_path":"FadeOverlay"}
{"amplitude":10,"op":"wave","phase_step":0.15,"player_path":"/Main/HUD","target_paths":["Card1","Card2","Card3"]}
{"damping":0.3,"frequency":2.5,"offset":{"x":0,"y":-60},"op":"spring","player_path":"/Main","target_path":"Player"}
{"amplitude":22,"duration":3.0,"op":"pendulum","period":1.4,"player_path":"/Main","target_path":"Sign"}
{"duration":4.0,"loop_mode":"linear","op":"path_follow","path_node":"/Main/PatrolPath","player_path":"/Main","target_path":"Drone"}
{"fps":12,"frames":8,"op":"flipbook","player_path":"/Main","target_path":"Sprite2D"}
{"fps":12,"hframes":6,"op":"sprite_frames","sprite_path":"/Main/Player","texture":"res://art/run.png","vframes":1}
{"op":"audio_cue","player_path":"/Main","stream":"res://sfx/land.wav","target_path":"Player","time":0.2}
```

## `animation_graph`

AnimationTree authoring: state machines, blend spaces, blend trees.

Handler: `res://addons/godot_ai_animation/handlers/graph.gd`

| op | What it does | Params |
| --- | --- | --- |
| `state_machine` | Build a state machine (states + transitions with xfade, conditions and modes) as the tree root. | `player_path`, `tree_path`, `name`, `parent_path`, `active`, `states`, `transitions`, `advance_mode`, `allow_transition_to_self`, `reset_ends`, `state_machine_type`, `start`, `dry_run` |
| `blend_space` | Build a 1D or 2D blend space from clips at positions (speed, direction, ...). | `player_path`, `tree_path`, `name`, `parent_path`, `active`, `dimensions`, `points`, `min`, `max`, `snap`, `sync`, `dry_run` |
| `blend_tree` | Build a blend tree from a recursive spec (blend2/blend3/add2/add3/one_shot/time_scale/animation). | `player_path`, `tree_path`, `name`, `parent_path`, `active`, `root`, `dry_run` |
| `wire` | Ensure an AnimationTree exists for the player, is active, and optionally set a parameter. | `player_path`, `tree_path`, `name`, `parent_path`, `active`, `create`, `parameter_path`, `parameter_value`, `dry_run` |
| `graph_get` | Dump a graph: states, transitions, blend points, tree structure, parameters, and missing-clip issues. | `player_path`, `tree_path`, `dry_run` |
| `locomotion` | Ready-made idle/walk/run setup: a speed blend space or a walking/running state machine. | `player_path`, `tree_path`, `name`, `parent_path`, `active`, `mode`, `idle`, `walk`, `run`, `start`, `dry_run` |
| `one_shot_layer` | Layer a one-shot clip (jump/attack/hit) on top of the existing tree root. | `player_path`, `tree_path`, `name`, `parent_path`, `active`, `animation`, `base`, `fadein`, `fadeout`, `autorestart`, `mix_mode`, `dry_run` |
| `additive_lean` | Additively layer a clip (lean/tilt) on top of the existing tree root. | `player_path`, `tree_path`, `name`, `parent_path`, `active`, `animation`, `base`, `dry_run` |

### `animation_graph` parameters

| Param | Type | Notes |
| --- | --- | --- |
| `op` | string: state_machine \| blend_space \| blend_tree \| wire \| graph_get \| locomotion \| one_shot_layer \| additive_lean | Which graph op to run. |
| `player_path` | string | Scene path to the AnimationPlayer that owns the clips (graph_get: optional, used to validate references). |
| `tree_path` | string | Scene path to the AnimationTree. Missing trees are created at that path; omit to reuse or create one next to the player. |
| `name` | string | Name for a created tree (default "AnimationTree"), or for the layer node in one_shot_layer/additive_lean. |
| `parent_path` | string | Where to create a new AnimationTree (default: the player's parent). |
| `active` | boolean (default `false`) | Activate the tree. Off by default because an active AnimationTree also drives the scene while you edit it - turn it on when the scene is ready to play. |
| `create` | boolean (default `true`) | wire: create the tree when missing. |
| `parameter_path` | string | wire: tree parameter to set (e.g. "parameters/conditions/walking"). |
| `parameter_value` | any | wire: value for parameter_path. |
| `states` | array | state_machine: [{name, animation, position?}] — one AnimationNodeAnimation per state. |
| `advance_mode` | string: auto \| enabled \| disabled | Per transition: "auto" fires when its condition/expression is true (Godot only evaluates conditions in auto mode), "enabled" is reachable by travel() only, "disabled" blocks it. |
| `transitions` | array | state_machine: [{from, to, xfade?, advance_mode?, switch_mode?, condition?, advance_expression?, priority?, reset?}]. |
| `allow_transition_to_self` | boolean (default `false`) |  |
| `reset_ends` | boolean (default `false`) |  |
| `state_machine_type` | string: root \| nested \| grouped | state_machine: graph role (default root). |
| `start` | string | state_machine/locomotion: start state to report a runtime hint for. |
| `dimensions` | integer | blend_space: 1 (float axis) or 2 (Vector2 axis). |
| `points` | array | blend_space: [{animation, position, name?}] — position is a float (1D) or {x,y} (2D). |
| `min` | any | blend_space: minimum space (number for 1D, {x,y} for 2D). |
| `max` | any | blend_space: maximum space (number for 1D, {x,y} for 2D). |
| `snap` | any | blend_space: snap step (number for 1D, {x,y} for 2D). |
| `sync` | boolean (default `true`) | blend_space: sync the blended clips' time. |
| `root` | object | blend_tree: recursive node spec, e.g. {type: "blend2", inputs: [{type: "animation", animation: "walk"}, ...]}. |
| `animation` | string | one_shot_layer/additive_lean: the clip to layer (jump/attack/lean). |
| `base` | string | one_shot_layer/additive_lean: clip to layer onto when the tree has no root yet. |
| `fadein` | number | one_shot_layer: fade-in seconds (default 0.1). |
| `fadeout` | number | one_shot_layer: fade-out seconds (default 0.2). |
| `autorestart` | boolean (default `false`) | one_shot_layer: restart automatically. |
| `mix_mode` | string: blend \| add | one_shot_layer: blend the shot over the base or add it (default blend). |
| `mode` | string: blend_space \| state_machine | locomotion: how to blend idle/walk/run (default blend_space on speed 0-2). |
| `idle` | string | locomotion: idle clip name (default "idle"). |
| `walk` | string | locomotion: walk clip name (default "walk"). |
| `run` | string | locomotion: run clip name (default "run"). |
| `dry_run` | boolean (default `false`) | Report what the graph would look like without committing anything (no undo action). |

Required: `op`, `player_path`.

### Examples

```json
{"op":"state_machine","player_path":"/Main","states":[{"animation":"idle","name":"idle"},{"animation":"walk","name":"walk"}],"transitions":[{"condition":"walking","from":"idle","to":"walk","xfade":0.2},{"advance_expression":"!walking","from":"walk","to":"idle","xfade":0.2}]}
{"dimensions":1,"max":2,"min":0,"op":"blend_space","player_path":"/Main","points":[{"animation":"idle","position":0},{"animation":"walk","position":1},{"animation":"run","position":2}]}
{"op":"blend_tree","player_path":"/Main","root":{"inputs":[{"animation":"walk","type":"animation"},{"animation":"run","type":"animation"}],"type":"blend2"}}
{"op":"wire","parameter_path":"parameters/conditions/walking","parameter_value":true,"player_path":"/Main"}
{"op":"graph_get","tree_path":"/Main/AnimationTree"}
{"mode":"state_machine","op":"locomotion","player_path":"/Main","start":"idle"}
{"animation":"jump","fadein":0.1,"fadeout":0.2,"op":"one_shot_layer","player_path":"/Main"}
{"animation":"lean","name":"Lean","op":"additive_lean","player_path":"/Main"}
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
| `tool` | string: animation_presets \| animation_fx \| animation_graph \| animation_edit \| animation_library \| animation_rig | dry_run: which tool to run. help: which tool's ops to list (omit for all). |
| `forward_op` | string | dry_run: the presets/fx/edit op to run (e.g. "retime"); its own params go in the same call. |
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

## `animation_library`

Project library: reusable templates and JSON clip specs.

Handler: `res://addons/godot_ai_animation/handlers/library.gd`

| op | What it does | Params |
| --- | --- | --- |
| `template_save` | Save a presets/fx call (its op and params) as a named template in the project library. | `name`, `tool`, `forward_op`, `description`, `library_path`, `overwrite`, `dry_run` |
| `template_apply` | Apply a saved template through its original tool, with per-call overrides. | `name`, `library_path`, `player_path`, `target_path`, `animation_name`, `overwrite`, `dry_run` |
| `template_list` | List the saved templates with their tool, op, description and params. | `library_path` |
| `template_delete` | Remove a template from the library file. | `name`, `library_path` |
| `spec_export` | Write a clip to a JSON spec file (typed values, method and audio tracks included). | `player_path`, `animation_name`, `path`, `overwrite` |
| `spec_import` | Read and validate a spec file or inline spec, reporting tracks, keys and issues. | `path`, `spec` |
| `spec_apply` | Build a clip from a spec file or inline spec, optionally remapping every track onto another node. | `player_path`, `animation_name`, `path`, `spec`, `target_path`, `overwrite`, `dry_run` |

### `animation_library` parameters

| Param | Type | Notes |
| --- | --- | --- |
| `op` | string: template_save \| template_apply \| template_list \| template_delete \| spec_export \| spec_import \| spec_apply | Which library op to run. |
| `name` | string | Template name (save/apply/delete). |
| `tool` | string: animation_presets \| animation_fx | template_save: which tool the stored op belongs to. |
| `forward_op` | string | template_save: the presets/fx op to store (e.g. "bounce"); its params go in the same call. |
| `description` | string | template_save: a note for other agents/users. |
| `library_path` | string | Template library file (default res://animation_toolkit/library.json). |
| `path` | string | spec_export/import/apply: JSON spec file. Export defaults to res://animation_toolkit/clips/<clip>.json. |
| `spec` | object | spec_import/spec_apply: an inline clip spec instead of a file. |
| `player_path` | string | Scene path to the AnimationPlayer (spec_export/apply). |
| `animation_name` | string | Clip to export, or the name to create when applying. |
| `target_path` | string | spec_apply: rewrite every track's node part to this node (apply a spec to another node). |
| `overwrite` | boolean (default `false`) | Replace an existing template/clip/file with the same name. |
| `dry_run` | boolean (default `false`) | Report what the call would do without writing anything. |

Required: `op`.

### Examples

```json
{"duration":0.5,"forward_op":"bounce","intensity":0.2,"name":"button_pop","op":"template_save","tool":"animation_presets"}
{"name":"button_pop","op":"template_apply","player_path":"/Main/HUD","target_path":"MenuButton"}
{"op":"template_list"}
{"name":"button_pop","op":"template_delete"}
{"animation_name":"open","op":"spec_export","player_path":"/Main/HUD"}
{"op":"spec_import","path":"res://animation_toolkit/clips/open.json"}
{"animation_name":"open_2","op":"spec_apply","path":"res://animation_toolkit/clips/open.json","player_path":"/Main/HUD","target_path":"/Main/HUD/Panel2"}
```

## `animation_rig`

Rig authoring: poses, clips from poses, rig inspection.

Handler: `res://addons/godot_ai_animation/handlers/rig.gd`

| op | What it does | Params |
| --- | --- | --- |
| `pose_save` | Capture a skeleton's pose as portable rest-relative data (inline and/or a pose file). | `skeleton_path`, `name`, `path`, `pose_dir`, `bones`, `overwrite`, `dry_run` |
| `pose_apply` | Write a saved or inline pose onto a skeleton, with blend / mirror / reset options. | `skeleton_path`, `name`, `path`, `pose_dir`, `pose`, `blend`, `mirror`, `reset_first`, `bones`, `dry_run` |
| `pose_blend` | Blend two poses (slerp rotations, lerp positions) into a new pose. | `from`, `to`, `factor`, `mirror`, `name`, `path`, `pose_dir`, `overwrite`, `dry_run` |
| `pose_to_clip` | Keyframe a pose sequence into an Animation clip (one rotation track per bone). | `player_path`, `skeleton_path`, `animation_name`, `keys`, `positions`, `scales`, `loop_mode`, `pose_dir`, `overwrite`, `dry_run` |
| `pose_list` | List the pose files saved in the project's pose directory. | `directory`, `dry_run` |
| `rig_get` | Dump a skeleton's bones, rests, pose, modifiers and springs, plus issues. | `skeleton_path`, `include_pose`, `dry_run` |
| `rig_chain` | Build bones on a skeleton from a bone spec, or turn a Node3D/Node2D subtree into a skeleton. | `skeleton_path`, `bones`, `node_path`, `kind`, `name`, `overwrite`, `dry_run` |
| `ik_setup` | Attach a 3D IK modifier (two-bone or chain solver) to a skeleton and wire it to a target node. | `skeleton_path`, `kind`, `chain`, `target_path`, `target_name`, `pole_path`, `use_virtual_end`, `end_bone_length`, `name`, `active`, `dry_run` |
| `spring_setup` | Attach spring bones (SpringBoneSimulator3D) to a skeleton, one spring setting per entry. | `skeleton_path`, `springs`, `name`, `active`, `mutable_bone_axes`, `dry_run` |
| `look_at_setup` | Attach a look-at modifier so one bone tracks a target node (created in front of the bone when omitted). | `skeleton_path`, `bone`, `target_path`, `target_name`, `forward_axis`, `origin_from`, `origin_bone`, `origin_node`, `origin_offset`, `origin_safe_margin`, `use_angle_limitation`, `primary_limit_angle`, `secondary_limit_angle`, `use_secondary_rotation`, `primary_axis`, `relative`, `duration`, `name`, `active`, `dry_run` |
| `retarget_setup` | Retarget a source skeleton's poses onto a child target skeleton through a RetargetModifier3D and a bone-name profile. | `skeleton_path`, `target_path`, `profile`, `position`, `rotation`, `scale`, `use_global_pose`, `move_target`, `name`, `active`, `dry_run` |
| `walk_cycle` | Build a looping in-place walk cycle (legs, knees, counter-swinging arms, hip bob) from bone roles. | `player_path`, `skeleton_path`, `animation_name`, `duration`, `stride`, `knee_bend`, `arm_swing`, `arm_down`, `bob`, `swing_axis`, `roles`, `loop_mode`, `overwrite`, `dry_run` |
| `idle_breathing` | Build a subtle looping idle: chest/spine breathing, a light head counter-move and an optional hip bob. | `player_path`, `skeleton_path`, `animation_name`, `duration`, `amplitude`, `head_amplitude`, `bob`, `axis`, `roles`, `loop_mode`, `overwrite`, `dry_run` |
| `blink` | Build a quick blink clip on the eye/eyelid bones, scale or rotate, optionally several blinks. | `player_path`, `skeleton_path`, `animation_name`, `bones`, `mode`, `closed_scale`, `angle`, `axis`, `blinks`, `duration`, `loop_mode`, `overwrite`, `dry_run` |
| `jumping_jack` | Build a looping jumping jack: arms swing down to overhead while the legs spread apart and back together, with a small rise. | `player_path`, `skeleton_path`, `animation_name`, `duration`, `amplitude`, `stride`, `bob`, `roles`, `loop_mode`, `overwrite`, `dry_run` |
| `squat` | Build a looping squat with planted feet: the hips drop, the knees bend forward and the leg chains are solved to keep the ankles in place. | `player_path`, `skeleton_path`, `animation_name`, `duration`, `bob`, `amplitude`, `roles`, `loop_mode`, `overwrite`, `dry_run` |
| `punch` | Build a looping boxing combo: guard, then alternating straight punches with a torso twist. `cycles` punches fit in the clip. | `player_path`, `skeleton_path`, `animation_name`, `duration`, `cycles`, `amplitude`, `bob`, `roles`, `loop_mode`, `overwrite`, `dry_run` |
| `bake_pose_sequence` | Sample a skeleton over time into a clip: seek the source clip, run the active modifiers (IK, springs, retarget), key the final pose. | `player_path`, `skeleton_path`, `animation_name`, `duration`, `fps`, `bones`, `positions`, `scales`, `source_animation`, `loop_mode`, `overwrite`, `dry_run` |

### `animation_rig` parameters

| Param | Type | Notes |
| --- | --- | --- |
| `op` | string: pose_save \| pose_apply \| pose_blend \| pose_to_clip \| pose_list \| rig_get \| rig_chain \| ik_setup \| spring_setup \| look_at_setup \| retarget_setup \| walk_cycle \| idle_breathing \| blink \| jumping_jack \| squat \| punch \| bake_pose_sequence | Rig op to run. |
| `roles` | object | Recipes: bone roles, e.g. {"thigh_l": "B-thigh.L"}; missing ones auto-detect. |
| `stride` | number | walk_cycle: leg swing, degrees (25). jumping_jack: leg spread (18). |
| `knee_bend` | number | walk_cycle: knee bend, degrees (30). |
| `arm_swing` | number | walk_cycle: arm counter-swing, degrees (20). |
| `arm_down` | number | walk_cycle: lower the arms this many degrees from the rest pose (T-pose rigs). |
| `bob` | number | Metres: walk_cycle / idle_breathing hip bob, jumping_jack rise, squat depth, punch crouch. |
| `swing_axis` | string: x \| y \| z | walk_cycle: swing axis (x). |
| `axis` | string: x \| y \| z | idle_breathing / blink: rotation axis (x). |
| `amplitude` | number | Degrees: idle_breathing chest rotation (2), jumping_jack arm swing (80), squat arms-forward (65), punch torso twist (12). |
| `head_amplitude` | number | idle_breathing: head counter-rotation, degrees (1). |
| `mode` | string: scale \| rotate | blink: how the lid closes (scale). |
| `closed_scale` | number | blink scale mode: closed Y scale (0.05). |
| `angle` | number | blink rotate mode: closing angle, degrees (25). |
| `blinks` | integer | blink: blinks per clip (1). |
| `cycles` | integer | punch: punches per clip (2; odd counts end mid-combo). |
| `fps` | integer | bake_pose_sequence: samples/s (30). |
| `source_animation` | string | bake_pose_sequence: clip to sample (default: playing). |
| `skeleton_path` | string | Skeleton3D/Skeleton2D scene path (default: first one). |
| `bones` | array | rig_chain: [{name, parent?, position?, rotation?, scale?, length?}] rests (degrees). Other ops: bone filter. |
| `node_path` | string | rig_chain: Node3D/Node2D subtree to turn into a skeleton (locals become rests). |
| `kind` | string: 3d \| 2d \| two_bone \| ccdik \| fabrik \| jacobian \| spline | rig_chain: 3d|2d. ik_setup: solver (two_bone). |
| `chain` | array | ik_setup: bones root -> effector. |
| `target_path` | string | ik_setup: existing target; created at the chain tip if omitted. |
| `target_name` | string | ik_setup: name of the created target (IKTarget). |
| `pole_path` | string | ik_setup two_bone: pole node for the bend direction. |
| `use_virtual_end` | boolean | ik_setup two_bone: last chain bone is the effector (off). |
| `end_bone_length` | number | ik_setup: virtual end length (0.1). |
| `active` | boolean | Modifier setups: enable now (off; it also drives the scene while you edit). |
| `springs` | array | spring_setup: per spring {root_bone, end_bone?, stiffness?, drag?, gravity?, radius?, ...}; end_bone defaults to the leaf. |
| `mutable_bone_axes` | boolean | spring_setup: allow any-axis rotation (off). |
| `bone` | string | look_at_setup: bone that tracks the target. |
| `forward_axis` | string: +x \| -x \| +y \| -y \| +z \| -z | look_at_setup: look direction (+z). |
| `origin_from` | string: self \| bone \| external_node | look_at_setup: look-direction source (self). |
| `origin_bone` | string | look_at_setup: origin bone (origin_from=bone). |
| `origin_node` | string | look_at_setup: origin node (origin_from=external_node). |
| `origin_offset` | any | look_at_setup: origin offset. |
| `origin_safe_margin` | number | look_at_setup: origin dead zone. |
| `use_angle_limitation` | boolean | look_at_setup: clamp the rotation (off). |
| `primary_limit_angle` | number | look_at_setup: primary limit, degrees. |
| `secondary_limit_angle` | number | look_at_setup: secondary limit, degrees. |
| `use_secondary_rotation` | boolean | look_at_setup: secondary axis rotation (off). |
| `primary_axis` | string: x \| y \| z | look_at_setup: primary rotation axis (y). |
| `relative` | boolean | look_at_setup: relative to initial orientation (off). |
| `duration` | number | look_at_setup: turn time, seconds (0 = instant). |
| `profile` | string | retarget_setup: auto | humanoid | res:// SkeletonProfile path. |
| `position` | boolean | retarget_setup: bone positions (off). |
| `rotation` | boolean (default `true`) | retarget_setup: bone rotations (on). |
| `scale` | boolean | retarget_setup: bone scales (off). |
| `use_global_pose` | boolean | retarget_setup: global poses (off; matching lengths). |
| `move_target` | boolean | retarget_setup: move target under modifier (on). |
| `name` | string | Pose name under res://animation_toolkit/poses/. |
| `path` | string | Explicit pose JSON path. |
| `pose` | object | Inline pose (as returned by pose_save). |
| `from` | any | pose_blend: first pose (inline or saved name). |
| `to` | any | pose_blend: second pose (inline or saved name). |
| `factor` | number | pose_blend: 0=from, 1=to (0.5). |
| `mirror` | boolean | Mirror poses across X (off; L/R swap). |
| `blend` | number | pose_apply: 0-1 blend toward target (1). |
| `reset_first` | boolean | pose_apply: reset poses first (off). |
| `player_path` | string | pose_to_clip: AnimationPlayer to receive the clip. |
| `animation_name` | string | pose_to_clip: clip name (pose_clip). |
| `keys` | array | pose_to_clip: [{pose|name|path, time, transition?, mirror?}]. |
| `positions` | boolean | pose_to_clip: also key positions (off). |
| `scales` | boolean | pose_to_clip: also key scales (off). |
| `loop_mode` | string: none \| linear \| pingpong | pose_to_clip: loop mode (none). |
| `directory` | string | pose_list: directory to scan. |
| `pose_dir` | string | Directory for named pose files. |
| `include_pose` | boolean | rig_get: include pose deltas (on). |
| `overwrite` | boolean | Replace an existing pose file or clip (off). |
| `dry_run` | boolean | Report without committing (off). |

Required: `op`.

### Examples

```json
{"name":"wave_mid","op":"pose_save","skeleton_path":"/Main/Rig/Skeleton3D"}
{"blend":0.5,"name":"wave_mid","op":"pose_apply","skeleton_path":"/Main/Rig/Skeleton3D"}
{"factor":0.35,"from":"idle","name":"wave_low","op":"pose_blend","to":"wave_mid"}
{"animation_name":"wave","keys":[{"name":"idle","time":0.0},{"name":"wave_mid","time":0.5,"transition":"ease_in_out"},{"name":"idle","time":1.0}],"loop_mode":"linear","op":"pose_to_clip","player_path":"/Main/Rig/AnimationPlayer","skeleton_path":"/Main/Rig/Skeleton3D"}
{"op":"pose_list"}
{"op":"rig_get","skeleton_path":"/Main/Rig/Skeleton3D"}
{"bones":[{"name":"spine","position":[0,0.2,0]},{"name":"chest","parent":"spine","position":[0,0.3,0]}],"op":"rig_chain","skeleton_path":"/Main/Rig/Skeleton3D"}
{"chain":["B-upperArm.L","B-forearm.L","B-hand.L"],"kind":"two_bone","op":"ik_setup","skeleton_path":"/Main/Rig/Skeleton3D","target_name":"HandTarget"}
{"op":"spring_setup","skeleton_path":"/Main/Rig/Skeleton3D","springs":[{"drag":0.2,"gravity":0.1,"radius":0.05,"root_bone":"B-hair01","stiffness":0.3}]}
{"bone":"B-head","forward_axis":"+z","op":"look_at_setup","skeleton_path":"/Main/Rig/Skeleton3D","target_name":"HeadTarget"}
{"op":"retarget_setup","profile":"auto","skeleton_path":"/Main/Source/Skeleton3D","target_path":"/Main/Target/Skeleton3D"}
{"animation_name":"walk","duration":1.0,"loop_mode":"linear","op":"walk_cycle","player_path":"/Main/Rig/AnimationPlayer","skeleton_path":"/Main/Rig/Skeleton3D"}
{"animation_name":"idle","duration":3.0,"loop_mode":"linear","op":"idle_breathing","player_path":"/Main/Rig/AnimationPlayer","skeleton_path":"/Main/Rig/Skeleton3D"}
{"animation_name":"blink","bones":["eyelid.L","eyelid.R"],"op":"blink","player_path":"/Main/Rig/AnimationPlayer","skeleton_path":"/Main/Rig/Skeleton3D"}
{"animation_name":"jack","duration":1.0,"loop_mode":"linear","op":"jumping_jack","player_path":"/Main/Rig/AnimationPlayer","skeleton_path":"/Main/Rig/Skeleton3D"}
{"animation_name":"squat","bob":0.25,"duration":2.0,"loop_mode":"linear","op":"squat","player_path":"/Main/Rig/AnimationPlayer","skeleton_path":"/Main/Rig/Skeleton3D"}
{"animation_name":"boxing","cycles":2,"duration":0.8,"loop_mode":"linear","op":"punch","player_path":"/Main/Rig/AnimationPlayer","skeleton_path":"/Main/Rig/Skeleton3D"}
{"animation_name":"walk_baked","duration":1.0,"loop_mode":"linear","op":"bake_pose_sequence","player_path":"/Main/Rig/AnimationPlayer","skeleton_path":"/Main/Rig/Skeleton3D"}
```
