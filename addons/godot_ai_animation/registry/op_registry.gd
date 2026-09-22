@tool
extends RefCounted

## Op registry — the single source of truth for the toolkit's tool surface.
##
## Each family (one Godot AI custom tool) declares its description, params
## schema, handler script and op descriptors. `plugin.gd` registers the tools
## from here, `tools/gen_docs.ps1` renders `docs/op-index.md` from here, and the
## tier-1 suite fails when the schema and the descriptors drift apart.
##
## Keep every description under the core's 600-char custom-tool cap; the
## tier-1 suite checks that too.

const FAMILY_PRESETS := "animation_presets"
const FAMILY_EDIT := "animation_edit"
const FAMILY_INSPECT := "animation_inspect"
const FAMILY_FX := "animation_fx"
const FAMILY_GRAPH := "animation_graph"

const MAX_DESCRIPTION_CHARS := 600


static func families() -> Dictionary:
	return {
		FAMILY_PRESETS: {
			"handler": "res://addons/godot_ai_animation/handlers/generate.gd",
			"summary": "One-call animation presets for an AnimationPlayer.",
			"description": _presets_description(),
			"schema": _presets_schema(),
			"ops": _presets_ops(),
			"requires_writable": true,
			"undoable": true,
		},
		FAMILY_EDIT: {
			"handler": "res://addons/godot_ai_animation/handlers/edit.gd",
			"summary": "Edit an existing Animation clip in place.",
			"description": _edit_description(),
			"schema": _edit_schema(),
			"ops": _edit_ops(),
			"requires_writable": true,
			"undoable": true,
		},
		FAMILY_INSPECT: {
			"handler": "res://addons/godot_ai_animation/handlers/inspect.gd",
			"summary": "Read-only inspection, auditing and dry runs.",
			"description": _inspect_description(),
			"schema": _inspect_schema(),
			"ops": _inspect_ops(),
			"requires_writable": false,
			"undoable": false,
		},
		FAMILY_FX: {
			"handler": "res://addons/godot_ai_animation/handlers/fx.gd",
			"summary": "One-call generators for game feel, UI, sprites and audio.",
			"description": _fx_description(),
			"schema": _fx_schema(),
			"ops": _fx_ops(),
			"requires_writable": true,
			"undoable": true,
		},
		FAMILY_GRAPH: {
			"handler": "res://addons/godot_ai_animation/handlers/graph.gd",
			"summary": "AnimationTree authoring: state machines, blend spaces, blend trees.",
			"description": _graph_description(),
			"schema": _graph_schema(),
			"ops": _graph_ops(),
			"requires_writable": true,
			"undoable": true,
		},
	}


static func family_names() -> Array:
	return [FAMILY_PRESETS, FAMILY_FX, FAMILY_GRAPH, FAMILY_EDIT, FAMILY_INSPECT]


static func family(name: String) -> Dictionary:
	return families().get(name, {})


static func op_descriptors(name: String) -> Array:
	return family(name).get("ops", [])


static func op_names(name: String) -> Array:
	var names: Array = []
	for descriptor in op_descriptors(name):
		names.append(descriptor.name)
	return names


static func find_op(name: String, op_name: String) -> Dictionary:
	for descriptor in op_descriptors(name):
		if descriptor.name == op_name:
			return descriptor
	return {}


# ============================================================================
# animation_presets
# ============================================================================

static func _presets_description() -> String:
	return (
		"One-call animation presets for an AnimationPlayer. Ops: pulse (breathing / "
		+ "ping-pong on any property), bounce (press feedback), orbit (circular "
		+ "position), sweep (full-turn rotation), drift (one-axis offset), spin (3D "
		+ "quaternion turn), float (3D bob), stagger (reveal a list of targets in "
		+ "order), showcase (build a runnable demo). Each preset commits one "
		+ "undoable action with typed keys and named transitions; Controls get "
		+ "their pivot recentered for bounce/sweep. Requires the Godot AI addon."
	)


static func _presets_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"op": {
				"type": "string",
				"enum": [
					"pulse", "bounce", "orbit", "sweep", "drift",
					"spin", "float", "stagger", "showcase",
				],
				"description": "Which preset to build.",
			},
			"player_path": {
				"type": "string",
				"description": "Scene path to the AnimationPlayer (it must already exist). Not used by showcase.",
			},
			"target_path": {
				"type": "string",
				"description": (
					"Node to animate: relative to the player's root_node "
					+ "(e.g. \"Button\") or scene-absolute (e.g. \"/Main/Button\"). "
					+ "Not used by showcase."
				),
			},
			"parent_path": {
				"type": "string",
				"description": "showcase: parent node for the demo subtree (default: the edited scene root).",
			},
			"name": {
				"type": "string",
				"description": "showcase: name for the demo subtree (default \"AnimationShowcase\").",
			},
			"animation_name": {
				"type": "string",
				"description": "Clip name; defaults to the preset name.",
			},
			"overwrite": {
				"type": "boolean",
				"default": false,
				"description": "Replace an existing clip with the same name.",
			},
			"property": {
				"type": "string",
				"description": "pulse: property to breathe (default \"scale\").",
			},
			"from_scale": {"type": "number", "default": 1.0},
			"to_scale": {"type": "number", "default": 1.1},
			"from_value": {
				"description": "pulse: start value for a non-scale property (typed to the property).",
			},
			"to_value": {"description": "pulse: end value."},
			"intensity": {
				"type": "number",
				"description": "bounce: peak overshoot fraction (default 0.15).",
			},
			"radius": {
				"type": "number",
				"description": "orbit: circle radius (default 1.0 for 3D, 100.0 for 2D).",
			},
			"clockwise": {"type": "boolean", "default": true},
			"turns": {
				"type": "number",
				"description": "sweep/spin/float: full turns (spin/sweep default 1.0; float default 0.0).",
			},
			"height": {
				"type": "number",
				"description": "float: vertical offset (default 0.7; negative bobs down).",
			},
			"scale": {
				"type": "number",
				"description": "float: peak scale factor (default 1.25).",
			},
			"target_paths": {
				"type": "array",
				"items": {"type": "string"},
				"description": (
					"stagger: ordered targets to reveal, each relative to the player's "
					+ "root_node or scene-absolute."
				),
			},
			"use_selection": {
				"type": "boolean",
				"default": false,
				"description": "stagger: use the editor's selection (in selection order) instead of target_paths.",
			},
			"effect": {
				"type": "string",
				"enum": ["fade_in", "slide_in", "pop_in"],
				"description": "stagger: reveal effect applied to every target.",
			},
			"stagger": {
				"type": "number",
				"description": "stagger: seconds between targets (default 0.06).",
			},
			"direction": {
				"type": "string",
				"enum": ["left", "right", "up", "down"],
				"description": "stagger slide_in: direction the items travel from (default left).",
			},
			"axis": {
				"type": "string",
				"enum": ["x", "y", "z"],
				"description": "drift: axis to offset along (z only for 3D targets).",
			},
			"distance": {
				"type": "number",
				"description": "orbit/sweep/drift distance (defaults by dimension).",
			},
			"duration": {"type": "number", "description": "Clip length in seconds."},
			"loop_mode": {
				"type": "string",
				"enum": ["none", "linear", "pingpong"],
				"description": "Drift refuses \"linear\" (the clip ends at a net offset).",
			},
			"dry_run": {
				"type": "boolean",
				"default": false,
				"description": "Report what the call would build without committing anything (no undo action).",
			},
		},
		"required": ["op", "player_path", "target_path"],
	}


static func _presets_ops() -> Array:
	return _with_dry_run([
		{
			"name": "pulse",
			"summary": "Breathing / ping-pong on any property (scale shortcut, or typed from_value/to_value).",
			"params": ["player_path", "target_path", "property", "from_scale", "to_scale", "from_value", "to_value", "duration", "loop_mode", "animation_name", "overwrite"],
			"example": {"op": "pulse", "player_path": "/Main/HUD", "target_path": "Label", "property": "modulate:a", "from_value": 0.2, "to_value": 1.0, "loop_mode": "pingpong", "duration": 1.2},
		},
		{
			"name": "bounce",
			"summary": "Center-pivot scale overshoot with settle-back — UI press feedback.",
			"params": ["player_path", "target_path", "intensity", "duration", "animation_name", "overwrite"],
			"example": {"op": "bounce", "player_path": "/Main/HUD", "target_path": "Button", "intensity": 0.2},
		},
		{
			"name": "orbit",
			"summary": "Circular position orbit (XZ plane for 3D, screen space for 2D/Control).",
			"params": ["player_path", "target_path", "radius", "clockwise", "duration", "loop_mode", "animation_name", "overwrite"],
			"example": {"op": "orbit", "player_path": "/Main/HUD", "target_path": "Satellite", "radius": 80.0, "duration": 3.0, "loop_mode": "linear"},
		},
		{
			"name": "sweep",
			"summary": "Full-turn rotation sweep — radar scans, cooldown rings.",
			"params": ["player_path", "target_path", "turns", "clockwise", "duration", "loop_mode", "animation_name", "overwrite"],
			"example": {"op": "sweep", "player_path": "/Main/HUD", "target_path": "CooldownRing", "turns": 1.0, "loop_mode": "linear"},
		},
		{
			"name": "drift",
			"summary": "One-axis position offset — scanlines, marquee, conveyor.",
			"params": ["player_path", "target_path", "axis", "distance", "duration", "loop_mode", "animation_name", "overwrite"],
			"example": {"op": "drift", "player_path": "/Main", "target_path": "Scanline", "axis": "x", "distance": 480.0, "loop_mode": "pingpong", "duration": 2.0},
		},
		{
			"name": "spin",
			"summary": "3D quaternion turn around local Y.",
			"params": ["player_path", "target_path", "turns", "clockwise", "duration", "loop_mode", "animation_name", "overwrite"],
			"example": {"op": "spin", "player_path": "/Main", "target_path": "Pickup", "turns": 1.0, "loop_mode": "linear"},
		},
		{
			"name": "float",
			"summary": "3D bob: rise + scale + turn through the transform.",
			"params": ["player_path", "target_path", "height", "scale", "turns", "duration", "loop_mode", "animation_name", "overwrite"],
			"example": {"op": "float", "player_path": "/Main", "target_path": "Pickup", "height": 0.4, "scale": 1.1, "loop_mode": "pingpong", "duration": 2.4},
		},
		{
			"name": "stagger",
			"summary": "Reveal a list of targets one after another in one clip.",
			"params": ["player_path", "target_paths", "use_selection", "effect", "direction", "distance", "stagger", "duration", "animation_name", "overwrite"],
			"example": {"op": "stagger", "player_path": "/Main/HUD", "target_paths": ["Item1", "Item2", "Item3"], "effect": "slide_in", "direction": "left", "stagger": 0.08, "duration": 0.3},
		},
		{
			"name": "showcase",
			"summary": "Build a runnable demo of every preset (7 nodes + 7 autoplaying clips).",
			"params": ["parent_path", "name", "overwrite"],
			"example": {"op": "showcase", "parent_path": "/Main"},
		},
	])


# ============================================================================
# animation_edit
# ============================================================================

static func _edit_description() -> String:
	return (
		"Edit an existing Animation clip in place (hand-authored clips included). "
		+ "Ops: retime, retarget (rename or bulk-remap track paths), reverse, "
		+ "mirror, offset, ease_range, set_interp, trim, split_at, merge, "
		+ "amplitude, loop, key_edit, cleanup. Needs player_path + "
		+ "animation_name; every call commits one scene-pinned undo action. "
		+ "Refuses clips with bezier/blend-shape/compressed tracks instead of "
		+ "dropping data. Requires the Godot AI addon."
	)


static func _edit_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"op": {
				"type": "string",
				"enum": [
					"retime", "retarget", "reverse", "mirror", "offset",
					"ease_range", "set_interp", "trim", "split_at", "merge",
					"amplitude", "loop", "key_edit", "cleanup",
				],
				"description": "Which edit to apply.",
			},
			"player_path": {
				"type": "string",
				"description": "Scene path to the AnimationPlayer that owns the clip.",
			},
			"animation_name": {
				"type": "string",
				"description": "Name of the clip to edit (merge: the default player for sources without one).",
			},
			"factor": {
				"type": "number",
				"description": "retime: time multiplier (>0). amplitude: value multiplier (1.0 = unchanged, 0.0 = flat).",
			},
			"length": {
				"type": "number",
				"description": "retime: target clip length in seconds (alternative to factor).",
			},
			"keys_only": {
				"type": "boolean",
				"default": false,
				"description": "retime: change the clip length but leave key times alone.",
			},
			"from_path": {
				"type": "string",
				"description": "retarget: track path (mode=exact) or node path (mode=node/prefix) to rewrite.",
			},
			"to_path": {"type": "string", "description": "retarget: replacement path."},
			"mode": {
				"type": "string",
				"enum": ["node", "prefix", "exact"],
				"description": "retarget: node = same node part, property kept; prefix = node path or subtree; exact = whole track path.",
			},
			"paths": {
				"type": "array",
				"items": {"type": "object"},
				"description": "retarget: batch of {from, to, mode} remaps applied in order (alternative to from_path/to_path).",
			},
			"axis": {
				"type": "string",
				"description": "mirror: plane(s) to mirror across — any of \"x\", \"y\", \"z\" (e.g. \"x\" or \"xy\").",
			},
			"pivot": {
				"description": "mirror: pivot for position tracks ({x,y[,z]}); default origin.",
			},
			"include_scale": {
				"type": "boolean",
				"default": false,
				"description": "mirror: also negate scale components on the mirrored axes.",
			},
			"delta": {"type": "number", "description": "offset: seconds to shift every key (may be negative)."},
			"wrap": {
				"type": "boolean",
				"default": false,
				"description": "offset: rotate the shift inside the clip length (loop phase shift) instead of extending it.",
			},
			"from": {"type": "number", "description": "ease_range/trim: start of the time range (default 0)."},
			"to": {"type": "number", "description": "ease_range/trim: end of the time range (default clip length)."},
			"transition": {
				"description": "ease_range/key_edit: per-key transition — \"linear\", \"ease_in\", \"ease_out\", \"ease_in_out\", or a number.",
			},
			"interpolation": {
				"type": "string",
				"enum": ["linear", "nearest", "cubic"],
				"description": "set_interp: track interpolation (cubic only for position/rotation/scale 3D tracks).",
			},
			"track_path": {
				"type": "string",
				"description": "set_interp/key_edit: track to target (e.g. \"Sprite:position\"). key_edit also accepts track_index.",
			},
			"track_index": {"type": "integer", "description": "key_edit: track index (alternative to track_path)."},
			"keep_bounds": {
				"type": "boolean",
				"default": true,
				"description": "trim: sample keys at both cut edges so the motion at the edges survives.",
			},
			"time": {"type": "number", "description": "split_at: cut time. key_edit: key time to add/set/remove/move."},
			"head_name": {"type": "string", "description": "split_at: name for the head clip (default \"<name>_a\"; the tail keeps the original name)."},
			"sources": {
				"type": "array",
				"items": {"type": "object"},
				"description": "merge: clips to concatenate as {animation_name, player_path?}; defaults to the edited player.",
			},
			"new_name": {"type": "string", "description": "merge/split_at: name for the produced clip (merge default \"<first>_merged\")."},
			"gap": {"type": "number", "description": "merge: seconds of silence inserted between clips."},
			"overwrite": {
				"type": "boolean",
				"default": false,
				"description": "merge/split_at: replace an existing clip with the produced name.",
			},
			"baseline": {
				"description": "amplitude: value the deltas are measured from (default: each track's first key).",
			},
			"loop_mode": {
				"type": "string",
				"enum": ["none", "linear", "pingpong"],
				"description": "loop: new loop mode.",
			},
			"make_seamless": {
				"type": "boolean",
				"default": false,
				"description": "loop: append a final key equal to the first so a linear loop wraps without a jump.",
			},
			"action": {
				"type": "string",
				"enum": ["add", "set", "remove", "move"],
				"description": "key_edit: what to do with the key.",
			},
			"value": {"description": "key_edit add/set: new key value (typed to the track); for method tracks, the method name."},
			"new_time": {"type": "number", "description": "key_edit move: new key time."},
			"tolerance": {"type": "number", "description": "key_edit/cleanup: match/equality tolerance in seconds or units (default 0.001 / 0.0001)."},
			"min_gap": {"type": "number", "description": "cleanup: drop keys closer than this to the previous kept key (default 0 = keep all)."},
			"drop_empty_tracks": {
				"type": "boolean",
				"default": true,
				"description": "cleanup: remove tracks that end up with no keys.",
			},
			"dry_run": {
				"type": "boolean",
				"default": false,
				"description": "Report what the edit would produce without committing anything (no undo action).",
			},
		},
		"required": ["op", "player_path", "animation_name"],
	}


static func _edit_ops() -> Array:
	return _with_dry_run([
		{
			"name": "retime",
			"summary": "Scale the clip's timeline by `factor` or to `length` (optionally keys_only).",
			"params": ["player_path", "animation_name", "factor", "length", "keys_only"],
			"example": {"op": "retime", "player_path": "/Main/HUD", "animation_name": "open", "factor": 0.5},
		},
		{
			"name": "retarget",
			"summary": "Rewrite track paths — rename a node, or bulk-remap a subtree prefix after a refactor.",
			"params": ["player_path", "animation_name", "from_path", "to_path", "mode", "paths"],
			"example": {"op": "retarget", "player_path": "/Main/HUD", "animation_name": "open", "from_path": "Panel", "to_path": "Popup/Panel", "mode": "prefix"},
		},
		{
			"name": "reverse",
			"summary": "Mirror every key time about the length so the clip plays backwards.",
			"params": ["player_path", "animation_name"],
			"example": {"op": "reverse", "player_path": "/Main/HUD", "animation_name": "open"},
		},
		{
			"name": "mirror",
			"summary": "Mirror position/rotation (and optionally scale) across a plane, about an optional pivot.",
			"params": ["player_path", "animation_name", "axis", "pivot", "include_scale"],
			"example": {"op": "mirror", "player_path": "/Main", "animation_name": "walk", "axis": "x", "pivot": {"x": 0, "y": 0}},
		},
		{
			"name": "offset",
			"summary": "Shift every key in time (optionally wrapping inside the clip length).",
			"params": ["player_path", "animation_name", "delta", "wrap"],
			"example": {"op": "offset", "player_path": "/Main/HUD", "animation_name": "pulse", "delta": 0.3, "wrap": true},
		},
		{
			"name": "ease_range",
			"summary": "Set the per-key transition on every value key inside a time range.",
			"params": ["player_path", "animation_name", "from", "to", "transition"],
			"example": {"op": "ease_range", "player_path": "/Main/HUD", "animation_name": "open", "from": 0.0, "to": 0.4, "transition": "ease_out"},
		},
		{
			"name": "set_interp",
			"summary": "Set track-level interpolation (linear/nearest/cubic) on value tracks, optionally one track.",
			"params": ["player_path", "animation_name", "interpolation", "track_path"],
			"example": {"op": "set_interp", "player_path": "/Main", "animation_name": "walk", "interpolation": "nearest", "track_path": "Sprite:frame"},
		},
		{
			"name": "trim",
			"summary": "Keep only a time range, shifted to 0, with optional sampled boundary keys.",
			"params": ["player_path", "animation_name", "from", "to", "keep_bounds"],
			"example": {"op": "trim", "player_path": "/Main", "animation_name": "walk", "from": 0.2, "to": 0.8},
		},
		{
			"name": "split_at",
			"summary": "Cut one clip into two at a time; the tail keeps the name, the head gets head_name.",
			"params": ["player_path", "animation_name", "time", "head_name", "overwrite"],
			"example": {"op": "split_at", "player_path": "/Main", "animation_name": "walk", "time": 0.5},
		},
		{
			"name": "merge",
			"summary": "Concatenate clips (optionally across players) into one, with an optional gap.",
			"params": ["player_path", "animation_name", "sources", "new_name", "gap", "overwrite"],
			"example": {"op": "merge", "player_path": "/Main", "animation_name": "intro", "sources": [{"animation_name": "intro"}, {"animation_name": "loop"}], "new_name": "full", "gap": 0.1},
		},
		{
			"name": "amplitude",
			"summary": "Scale key deltas about a baseline — soften or exaggerate a clip without rebuilding it.",
			"params": ["player_path", "animation_name", "factor", "baseline"],
			"example": {"op": "amplitude", "player_path": "/Main/HUD", "animation_name": "bounce", "factor": 0.5},
		},
		{
			"name": "loop",
			"summary": "Set the loop mode, optionally making a linear loop seamless.",
			"params": ["player_path", "animation_name", "loop_mode", "make_seamless"],
			"example": {"op": "loop", "player_path": "/Main", "animation_name": "walk", "loop_mode": "linear", "make_seamless": true},
		},
		{
			"name": "key_edit",
			"summary": "Add, set, remove or move a single key on a track.",
			"params": ["player_path", "animation_name", "action", "track_path", "track_index", "time", "value", "transition", "new_time", "tolerance"],
			"example": {"op": "key_edit", "player_path": "/Main/HUD", "animation_name": "open", "action": "set", "track_path": "Panel:position", "time": 0.2, "value": {"x": 10, "y": 0}},
		},
		{
			"name": "cleanup",
			"summary": "Drop redundant keys and empty tracks (dedupe holds, optional minimum gap).",
			"params": ["player_path", "animation_name", "tolerance", "min_gap", "drop_empty_tracks"],
			"example": {"op": "cleanup", "player_path": "/Main", "animation_name": "walk", "tolerance": 0.0001, "min_gap": 0.01},
		},
	])


# ============================================================================
# animation_inspect
# ============================================================================

static func _inspect_description() -> String:
	return (
		"Read-only inspection for animation work: describe (human-readable clip "
		+ "summary), timeline (per-track key table), audit (broken paths, "
		+ "zero-length clips, duplicate keys, loop seams, autoplay conflicts, "
		+ "unused clips), compare (diff two clips), stats (scene-wide numbers), "
		+ "dry_run (run any generator or edit op without "
		+ "committing), help (op index with params and examples). Never mutates "
		+ "the scene or the undo stack. Requires the Godot AI addon."
	)


static func _inspect_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"op": {
				"type": "string",
				"enum": ["describe", "timeline", "audit", "compare", "stats", "dry_run", "help"],
				"description": "Which inspection to run.",
			},
			"player_path": {
				"type": "string",
				"description": "Scene path to an AnimationPlayer. Omit for audit/stats to scan every player in the edited scene.",
			},
			"animation_name": {
				"type": "string",
				"description": "Clip to inspect (describe/timeline/compare). Omit for describe to summarise every clip on the player.",
			},
			"other_animation_name": {"type": "string", "description": "compare: the clip to diff against."},
			"other_player_path": {
				"type": "string",
				"description": "compare: player holding the other clip (default: the same player).",
			},
			"track_path": {
				"type": "string",
				"description": "timeline: only this track (e.g. \"Sprite:position\").",
			},
			"include_values": {
				"type": "boolean",
				"default": true,
				"description": "timeline: include each key's value.",
			},
			"max_keys": {
				"type": "integer",
				"description": "timeline/compare: cap on returned keys (default 200).",
			},
			"max_tracks": {
				"type": "integer",
				"description": "describe: cap on returned tracks per clip (default 64).",
			},
			"severity": {
				"type": "string",
				"enum": ["all", "error", "warning", "info"],
				"description": "audit: only findings of this severity (default all).",
			},
			"include_info": {
				"type": "boolean",
				"default": true,
				"description": "audit: include info-level findings (unused clips, constant tracks).",
			},
			"tolerance": {
				"type": "number",
				"description": "compare: value comparison tolerance (default 0.0001).",
			},
			"tool": {
				"type": "string",
				"enum": ["animation_presets", "animation_fx", "animation_graph", "animation_edit"],
				"description": "dry_run: which tool to run. help: which tool's ops to list (omit for all).",
			},
			"forward_op": {
				"type": "string",
				"description": "dry_run: the presets/fx/edit op to run (e.g. \"retime\"); its own params go in the same call.",
			},
			"op_name": {
				"type": "string",
				"description": "help: only this op (omit to list the tool's whole index).",
			},
		},
		"required": ["op"],
	}


static func _inspect_ops() -> Array:
	return [
		{
			"name": "describe",
			"summary": "Human-readable summary of one clip or every clip on a player.",
			"params": ["player_path", "animation_name", "max_tracks"],
			"example": {"op": "describe", "player_path": "/Main/HUD", "animation_name": "open"},
		},
		{
			"name": "timeline",
			"summary": "Per-track key table (times, values, transitions) for one clip.",
			"params": ["player_path", "animation_name", "track_path", "include_values", "max_keys"],
			"example": {"op": "timeline", "player_path": "/Main", "animation_name": "walk", "max_keys": 50},
		},
		{
			"name": "audit",
			"summary": "Scene or player health check: broken paths, dead clips, loop seams, autoplay conflicts.",
			"params": ["player_path", "severity", "include_info"],
			"example": {"op": "audit", "severity": "warning"},
		},
		{
			"name": "compare",
			"summary": "Diff two clips: length, loop mode, track paths, key counts and value deltas.",
			"params": ["player_path", "animation_name", "other_animation_name", "other_player_path", "tolerance", "max_keys"],
			"example": {"op": "compare", "player_path": "/Main", "animation_name": "walk", "other_animation_name": "walk_fast"},
		},
		{
			"name": "stats",
			"summary": "Clip/track/key totals, track-type histogram and loop-mode breakdown.",
			"params": ["player_path"],
			"example": {"op": "stats"},
		},
		{
			"name": "dry_run",
			"summary": "Run any presets/edit op and report the result without committing.",
			"params": ["tool", "forward_op", "player_path", "animation_name"],
			"example": {"op": "dry_run", "tool": "animation_edit", "forward_op": "retime", "player_path": "/Main", "animation_name": "walk", "factor": 0.5},
		},
		{
			"name": "help",
			"summary": "Op index from the registry: names, summaries, params and examples.",
			"params": ["tool", "op_name"],
			"example": {"op": "help", "tool": "animation_edit"},
		},
	]


## Every generate/edit op also accepts dry_run; declared once here so the
## descriptors, schema and generated docs stay in sync.
static func _with_dry_run(ops: Array) -> Array:
	for descriptor in ops:
		var params: Array = descriptor.get("params", [])
		if not params.has("dry_run"):
			params.append("dry_run")
	return ops


# ============================================================================
# animation_fx
# ============================================================================

static func _fx_description() -> String:
	return (
		"One-call animation generators for game feel, UI, sprites and audio. Ops: "
		+ "shake, zoom_punch, hit_flash, damage_bar (feedback); typewriter, "
		+ "progress_fill, counter, dialog_pop, transition (UI); wave, spring, "
		+ "pendulum, path_follow (motion); flipbook, sprite_frames, audio_cue "
		+ "(sprites/audio). Each commits one scene-pinned undo action with typed "
		+ "keys and named transitions. Requires the Godot AI addon."
	)


static func _fx_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"op": {
				"type": "string",
				"enum": [
					"shake", "zoom_punch", "hit_flash", "damage_bar",
					"typewriter", "progress_fill", "counter", "dialog_pop", "transition",
					"wave", "spring", "pendulum", "path_follow",
					"flipbook", "sprite_frames", "audio_cue",
				],
				"description": "Which generator to run.",
			},
			"player_path": {
				"type": "string",
				"description": "Scene path to the AnimationPlayer (not used by sprite_frames).",
			},
			"target_path": {
				"type": "string",
				"description": "Node to animate, relative to the player's root_node or scene-absolute.",
			},
			"animation_name": {
				"type": "string",
				"description": "Clip name; defaults to the op name.",
			},
			"overwrite": {
				"type": "boolean",
				"default": false,
				"description": "Replace an existing clip with the same name.",
			},
			"property": {
				"type": "string",
				"description": "Property to animate when the op allows one (shake: position; typewriter: visible_ratio; damage_bar/progress_fill: value; flipbook: frame).",
			},
			"duration": {"type": "number", "description": "Clip length in seconds (defaults per op: 0.4 shake, 0.25 zoom_punch, 0.18 hit_flash, 0.4 damage_bar, 1.5 typewriter, 0.8 progress_fill, 1.0 counter, 0.35 dialog_pop, 0.5 transition, 1.0 spring, 2.0 pendulum, 2.0 path_follow)."},
			"intensity": {"type": "number", "description": "shake: peak offset in pixels/units (default 8)."},
			"frequency": {"type": "number", "description": "shake/spring: oscillations per second (default 20 / 2)."},
			"decay": {
				"type": "number",
				"description": "shake/pendulum: falloff per clip (1.0 = none, 0.1 = settled; default 0.15 / 1.0).",
			},
			"seed": {"type": "integer", "description": "shake: deterministic noise seed (default 0)."},
			"axis": {
				"type": "string",
				"description": "shake/wave: axes to move along, any of \"x\", \"y\", \"z\" (default xy for 2D, xyz for 3D).",
			},
			"amount": {"type": "number", "description": "zoom_punch: fractional punch (0.08 = +8%)."},
			"peak_ratio": {"type": "number", "description": "zoom_punch: when the peak happens, 0-1 (default 0.3)."},
			"color": {"description": "hit_flash: flash color (hex string or {r,g,b[,a]}); transition: overlay color."},
			"count": {"type": "integer", "description": "hit_flash: number of flashes (default 1)."},
			"steps": {
				"type": "integer",
				"description": "typewriter: discrete characters (0 = smooth). counter: number of increments.",
			},
			"delay": {"type": "number", "description": "typewriter/progress_fill/damage_bar: seconds to hold before the motion."},
			"from_ratio": {"type": "number", "description": "typewriter: starting visible_ratio (default 0)."},
			"to_ratio": {"type": "number", "description": "typewriter: ending visible_ratio (default 1)."},
			"from": {"type": "number", "description": "progress_fill/counter/damage_bar: starting value (default: the property's current value)."},
			"to": {"type": "number", "description": "progress_fill/counter/damage_bar: ending value."},
			"format": {"type": "string", "description": "counter: printf format for the number (default \"%d\")."},
			"prefix": {"type": "string", "description": "counter: text before the number."},
			"suffix": {"type": "string", "description": "counter: text after the number."},
			"method": {"type": "string", "description": "counter: setter called with the formatted string (default \"set_text\")."},
			"target_paths": {
				"type": "array",
				"items": {"type": "string"},
				"description": "wave: ordered targets to bob (relative to the player's root_node or scene-absolute).",
			},
			"use_selection": {"type": "boolean", "default": false, "description": "wave: use the editor's selection instead of target_paths."},
			"amplitude": {"type": "number", "description": "wave: bob height (default 12). pendulum: swing in degrees (default 18)."},
			"period": {"type": "number", "description": "wave/pendulum: seconds per cycle (default 1.2 / 1.0)."},
			"phase_step": {"type": "number", "description": "wave: seconds each following target lags (default 0.12)."},
			"cycles": {"type": "integer", "description": "wave: loops of the sine in the clip (default 1)."},
			"offset": {"description": "spring: travel offset as {x,y[,z]} matching the target's position type."},
			"damping": {"type": "number", "description": "spring: 0-1 damping ratio (default 0.35; >= 1 is critically damped)."},
			"samples": {"type": "integer", "description": "spring/path_follow: key samples (default 30 / 24)."},
			"path_node": {"type": "string", "description": "path_follow: scene path to the Path2D/Path3D to follow."},
			"frames": {"type": "integer", "description": "flipbook: number of frames to step through."},
			"fps": {"type": "number", "description": "flipbook/sprite_frames: frames per second (default 12)."},
			"from_frame": {"type": "integer", "description": "flipbook/sprite_frames: first frame index (default 0)."},
			"to_frame": {"type": "integer", "description": "sprite_frames: last frame index (default: the last cell)."},
			"sprite_path": {"type": "string", "description": "sprite_frames: scene path to the AnimatedSprite2D."},
			"texture": {"type": "string", "description": "sprite_frames: res:// path of the spritesheet texture."},
			"hframes": {"type": "integer", "description": "sprite_frames: sheet columns (default 4)."},
			"vframes": {"type": "integer", "description": "sprite_frames: sheet rows (default 1)."},
			"loop": {"type": "boolean", "default": true, "description": "sprite_frames: loop the animation."},
			"play": {"type": "boolean", "default": true, "description": "sprite_frames: start playing after assigning."},
			"stream": {"type": "string", "description": "audio_cue: res:// path of the audio stream."},
			"time": {"type": "number", "description": "audio_cue: when the cue fires (default 0)."},
			"start_offset": {"type": "number", "description": "audio_cue: trim from the start of the stream."},
			"end_offset": {"type": "number", "description": "audio_cue: trim from the end of the stream."},
			"mode": {
				"type": "string",
				"enum": ["fade_in", "fade_out", "wipe_right", "wipe_left", "wipe_up", "wipe_down"],
				"description": "transition: which effect to build.",
			},
			"from_scale": {"type": "number", "description": "dialog_pop: starting scale factor (default 0.85)."},
			"overshoot": {"type": "number", "description": "dialog_pop: peak scale factor (default 1.06)."},
			"fade": {"type": "boolean", "default": true, "description": "dialog_pop: also fade the alpha in."},
			"loop_mode": {
				"type": "string",
				"enum": ["none", "linear", "pingpong"],
				"description": "wave/path_follow/flipbook: loop mode (default linear / none / linear).",
			},
			"dry_run": {
				"type": "boolean",
				"default": false,
				"description": "Report what the call would build without committing anything (no undo action).",
			},
		},
		"required": ["op"],
	}


static func _fx_ops() -> Array:
	return _with_dry_run([
		{
			"name": "shake",
			"summary": "Seeded decaying screen shake on a camera/control position.",
			"params": ["player_path", "target_path", "intensity", "duration", "frequency", "decay", "seed", "axis", "property", "animation_name", "overwrite"],
			"example": {"op": "shake", "player_path": "/Main", "target_path": "Camera2D", "intensity": 10, "duration": 0.4, "seed": 7},
		},
		{
			"name": "zoom_punch",
			"summary": "Camera punch: overshoot then settle (Camera2D zoom / Camera3D fov).",
			"params": ["player_path", "target_path", "amount", "duration", "peak_ratio", "animation_name", "overwrite"],
			"example": {"op": "zoom_punch", "player_path": "/Main", "target_path": "Camera2D", "amount": 0.12},
		},
		{
			"name": "hit_flash",
			"summary": "Flash a CanvasItem's modulate and back (damage feedback).",
			"params": ["player_path", "target_path", "color", "duration", "count", "animation_name", "overwrite"],
			"example": {"op": "hit_flash", "player_path": "/Main", "target_path": "Player", "color": "#ffffff", "count": 2},
		},
		{
			"name": "damage_bar",
			"summary": "Delayed follow-up bar: hold, then ease to the new value.",
			"params": ["player_path", "target_path", "property", "from", "to", "delay", "duration", "animation_name", "overwrite"],
			"example": {"op": "damage_bar", "player_path": "/Main/HUD", "target_path": "GhostBar", "to": 40, "delay": 0.3},
		},
		{
			"name": "typewriter",
			"summary": "Reveal text with visible_ratio, smoothly or in character steps.",
			"params": ["player_path", "target_path", "property", "duration", "steps", "delay", "from_ratio", "to_ratio", "animation_name", "overwrite"],
			"example": {"op": "typewriter", "player_path": "/Main/HUD", "target_path": "DialogLabel", "steps": 40, "duration": 1.6},
		},
		{
			"name": "progress_fill",
			"summary": "Fill a numeric property (ProgressBar value, modulate:a, custom float).",
			"params": ["player_path", "target_path", "property", "from", "to", "duration", "delay", "animation_name", "overwrite"],
			"example": {"op": "progress_fill", "player_path": "/Main/HUD", "target_path": "HealthBar", "to": 100, "duration": 0.6},
		},
		{
			"name": "counter",
			"summary": "Rolling numbers via a method track calling a setter with formatted text.",
			"params": ["player_path", "target_path", "from", "to", "steps", "duration", "format", "prefix", "suffix", "method", "animation_name", "overwrite"],
			"example": {"op": "counter", "player_path": "/Main/HUD", "target_path": "ScoreLabel", "from": 0, "to": 1250, "prefix": "$"},
		},
		{
			"name": "dialog_pop",
			"summary": "Modal entrance: scale through an overshoot, optionally fading in.",
			"params": ["player_path", "target_path", "from_scale", "overshoot", "duration", "fade", "animation_name", "overwrite"],
			"example": {"op": "dialog_pop", "player_path": "/Main/HUD", "target_path": "DialogPanel", "duration": 0.35},
		},
		{
			"name": "transition",
			"summary": "Full-screen fade or wipe on an overlay Control.",
			"params": ["player_path", "target_path", "mode", "duration", "animation_name", "overwrite"],
			"example": {"op": "transition", "player_path": "/Main", "target_path": "FadeOverlay", "mode": "fade_out", "duration": 0.5},
		},
		{
			"name": "wave",
			"summary": "Cascading sine bob for a list of targets (or the editor selection).",
			"params": ["player_path", "target_paths", "use_selection", "axis", "amplitude", "period", "phase_step", "cycles", "loop_mode", "animation_name", "overwrite"],
			"example": {"op": "wave", "player_path": "/Main/HUD", "target_paths": ["Card1", "Card2", "Card3"], "amplitude": 10, "phase_step": 0.15},
		},
		{
			"name": "spring",
			"summary": "Damped spring settle from the current position to position + offset.",
			"params": ["player_path", "target_path", "offset", "frequency", "damping", "duration", "samples", "animation_name", "overwrite"],
			"example": {"op": "spring", "player_path": "/Main", "target_path": "Player", "offset": {"x": 0, "y": -60}, "frequency": 2.5, "damping": 0.3},
		},
		{
			"name": "pendulum",
			"summary": "Swinging rotation with optional decay (2D rotation, 3D local Z).",
			"params": ["player_path", "target_path", "amplitude", "period", "duration", "decay", "animation_name", "overwrite"],
			"example": {"op": "pendulum", "player_path": "/Main", "target_path": "Sign", "amplitude": 22, "period": 1.4, "duration": 3.0},
		},
		{
			"name": "path_follow",
			"summary": "Follow a Path2D/Path3D curve by sampling it into position keys.",
			"params": ["player_path", "target_path", "path_node", "duration", "samples", "loop_mode", "animation_name", "overwrite"],
			"example": {"op": "path_follow", "player_path": "/Main", "target_path": "Drone", "path_node": "/Main/PatrolPath", "duration": 4.0, "loop_mode": "linear"},
		},
		{
			"name": "flipbook",
			"summary": "Step a Sprite2D's frame through a range with nearest interpolation.",
			"params": ["player_path", "target_path", "property", "frames", "fps", "from_frame", "loop_mode", "animation_name", "overwrite"],
			"example": {"op": "flipbook", "player_path": "/Main", "target_path": "Sprite2D", "frames": 8, "fps": 12},
		},
		{
			"name": "sprite_frames",
			"summary": "Slice a spritesheet into a SpriteFrames resource and assign it to an AnimatedSprite2D.",
			"params": ["sprite_path", "texture", "hframes", "vframes", "fps", "loop", "from_frame", "to_frame", "play", "animation_name", "overwrite"],
			"example": {"op": "sprite_frames", "sprite_path": "/Main/Player", "texture": "res://art/run.png", "hframes": 6, "vframes": 1, "fps": 12},
		},
		{
			"name": "audio_cue",
			"summary": "Schedule an audio stream as a one-key audio clip on the player.",
			"params": ["player_path", "target_path", "stream", "time", "start_offset", "end_offset", "animation_name", "overwrite"],
			"example": {"op": "audio_cue", "player_path": "/Main", "target_path": "Player", "stream": "res://sfx/land.wav", "time": 0.2},
		},
	])


# ============================================================================
# animation_graph
# ============================================================================

static func _graph_description() -> String:
	return (
		"Author AnimationTree graphs on top of an AnimationPlayer: state_machine "
		+ "(states, transitions, xfade, conditions, advance/switch modes), "
		+ "blend_space (1D/2D), blend_tree (recursive blend2/blend3/add2/add3/"
		+ "one_shot/time_scale), wire (create or configure the tree, set "
		+ "parameters), graph_get (dump a graph, flag missing clips), plus "
		+ "locomotion, one_shot_layer and additive_lean setups. One scene-pinned "
		+ "undo action per call; every op accepts dry_run. Requires the Godot AI "
		+ "addon."
	)


static func _graph_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"op": {
				"type": "string",
				"enum": [
					"state_machine", "blend_space", "blend_tree", "wire", "graph_get",
					"locomotion", "one_shot_layer", "additive_lean",
				],
				"description": "Which graph op to run.",
			},
			"player_path": {
				"type": "string",
				"description": "Scene path to the AnimationPlayer that owns the clips (graph_get: optional, used to validate references).",
			},
			"tree_path": {
				"type": "string",
				"description": "Scene path to the AnimationTree. Missing trees are created at that path; omit to reuse or create one next to the player.",
			},
			"name": {
				"type": "string",
				"description": "Name for a created tree (default \"AnimationTree\"), or for the layer node in one_shot_layer/additive_lean.",
			},
			"parent_path": {
				"type": "string",
				"description": "Where to create a new AnimationTree (default: the player's parent).",
			},
			"active": {
				"type": "boolean",
				"default": false,
				"description": "Activate the tree. Off by default because an active AnimationTree also drives the scene while you edit it - turn it on when the scene is ready to play.",
			},
			"create": {"type": "boolean", "default": true, "description": "wire: create the tree when missing."},
			"parameter_path": {"type": "string", "description": "wire: tree parameter to set (e.g. \"parameters/conditions/walking\")."},
			"parameter_value": {"description": "wire: value for parameter_path."},
			"states": {
				"type": "array",
				"items": {"type": "object"},
				"description": "state_machine: [{name, animation, position?}] — one AnimationNodeAnimation per state.",
			},
			"advance_mode": {
				"type": "string",
				"enum": ["auto", "enabled", "disabled"],
				"description": "Per transition: \"auto\" fires when its condition/expression is true (Godot only evaluates conditions in auto mode), \"enabled\" is reachable by travel() only, \"disabled\" blocks it.",
			},
			"transitions": {
				"type": "array",
				"items": {"type": "object"},
				"description": "state_machine: [{from, to, xfade?, advance_mode?, switch_mode?, condition?, advance_expression?, priority?, reset?}].",
			},
			"allow_transition_to_self": {"type": "boolean", "default": false},
			"reset_ends": {"type": "boolean", "default": false},
			"state_machine_type": {
				"type": "string",
				"enum": ["root", "nested", "grouped"],
				"description": "state_machine: graph role (default root).",
			},
			"start": {"type": "string", "description": "state_machine/locomotion: start state to report a runtime hint for."},
			"dimensions": {"type": "integer", "description": "blend_space: 1 (float axis) or 2 (Vector2 axis)."},
			"points": {
				"type": "array",
				"items": {"type": "object"},
				"description": "blend_space: [{animation, position, name?}] — position is a float (1D) or {x,y} (2D).",
			},
			"min": {"description": "blend_space: minimum space (number for 1D, {x,y} for 2D)."},
			"max": {"description": "blend_space: maximum space (number for 1D, {x,y} for 2D)."},
			"snap": {"description": "blend_space: snap step (number for 1D, {x,y} for 2D)."},
			"sync": {"type": "boolean", "default": true, "description": "blend_space: sync the blended clips' time."},
			"root": {
				"type": "object",
				"description": "blend_tree: recursive node spec, e.g. {type: \"blend2\", inputs: [{type: \"animation\", animation: \"walk\"}, ...]}.",
			},
			"animation": {
				"type": "string",
				"description": "one_shot_layer/additive_lean: the clip to layer (jump/attack/lean).",
			},
			"base": {
				"type": "string",
				"description": "one_shot_layer/additive_lean: clip to layer onto when the tree has no root yet.",
			},
			"fadein": {"type": "number", "description": "one_shot_layer: fade-in seconds (default 0.1)."},
			"fadeout": {"type": "number", "description": "one_shot_layer: fade-out seconds (default 0.2)."},
			"autorestart": {"type": "boolean", "default": false, "description": "one_shot_layer: restart automatically."},
			"mix_mode": {
				"type": "string",
				"enum": ["blend", "add"],
				"description": "one_shot_layer: blend the shot over the base or add it (default blend).",
			},
			"mode": {
				"type": "string",
				"enum": ["blend_space", "state_machine"],
				"description": "locomotion: how to blend idle/walk/run (default blend_space on speed 0-2).",
			},
			"idle": {"type": "string", "description": "locomotion: idle clip name (default \"idle\")."},
			"walk": {"type": "string", "description": "locomotion: walk clip name (default \"walk\")."},
			"run": {"type": "string", "description": "locomotion: run clip name (default \"run\")."},
			"dry_run": {
				"type": "boolean",
				"default": false,
				"description": "Report what the graph would look like without committing anything (no undo action).",
			},
		},
		"required": ["op", "player_path"],
	}


static func _graph_ops() -> Array:
	return _with_dry_run([
		{
			"name": "state_machine",
			"summary": "Build a state machine (states + transitions with xfade, conditions and modes) as the tree root.",
			"params": ["player_path", "tree_path", "name", "parent_path", "active", "states", "transitions", "advance_mode", "allow_transition_to_self", "reset_ends", "state_machine_type", "start"],
			"example": {"op": "state_machine", "player_path": "/Main", "states": [{"name": "idle", "animation": "idle"}, {"name": "walk", "animation": "walk"}], "transitions": [{"from": "idle", "to": "walk", "xfade": 0.2, "condition": "walking"}, {"from": "walk", "to": "idle", "xfade": 0.2, "advance_expression": "!walking"}]},
		},
		{
			"name": "blend_space",
			"summary": "Build a 1D or 2D blend space from clips at positions (speed, direction, ...).",
			"params": ["player_path", "tree_path", "name", "parent_path", "active", "dimensions", "points", "min", "max", "snap", "sync"],
			"example": {"op": "blend_space", "player_path": "/Main", "dimensions": 1, "points": [{"animation": "idle", "position": 0}, {"animation": "walk", "position": 1}, {"animation": "run", "position": 2}], "min": 0, "max": 2},
		},
		{
			"name": "blend_tree",
			"summary": "Build a blend tree from a recursive spec (blend2/blend3/add2/add3/one_shot/time_scale/animation).",
			"params": ["player_path", "tree_path", "name", "parent_path", "active", "root"],
			"example": {"op": "blend_tree", "player_path": "/Main", "root": {"type": "blend2", "inputs": [{"type": "animation", "animation": "walk"}, {"type": "animation", "animation": "run"}]}},
		},
		{
			"name": "wire",
			"summary": "Ensure an AnimationTree exists for the player, is active, and optionally set a parameter.",
			"params": ["player_path", "tree_path", "name", "parent_path", "active", "create", "parameter_path", "parameter_value"],
			"example": {"op": "wire", "player_path": "/Main", "parameter_path": "parameters/conditions/walking", "parameter_value": true},
		},
		{
			"name": "graph_get",
			"summary": "Dump a graph: states, transitions, blend points, tree structure, parameters, and missing-clip issues.",
			"params": ["player_path", "tree_path"],
			"example": {"op": "graph_get", "tree_path": "/Main/AnimationTree"},
		},
		{
			"name": "locomotion",
			"summary": "Ready-made idle/walk/run setup: a speed blend space or a walking/running state machine.",
			"params": ["player_path", "tree_path", "name", "parent_path", "active", "mode", "idle", "walk", "run", "start"],
			"example": {"op": "locomotion", "player_path": "/Main", "mode": "state_machine", "start": "idle"},
		},
		{
			"name": "one_shot_layer",
			"summary": "Layer a one-shot clip (jump/attack/hit) on top of the existing tree root.",
			"params": ["player_path", "tree_path", "name", "parent_path", "active", "animation", "base", "fadein", "fadeout", "autorestart", "mix_mode"],
			"example": {"op": "one_shot_layer", "player_path": "/Main", "animation": "jump", "fadein": 0.1, "fadeout": 0.2},
		},
		{
			"name": "additive_lean",
			"summary": "Additively layer a clip (lean/tilt) on top of the existing tree root.",
			"params": ["player_path", "tree_path", "name", "parent_path", "active", "animation", "base"],
			"example": {"op": "additive_lean", "player_path": "/Main", "animation": "lean", "name": "Lean"},
		},
	])


# ============================================================================
# Markdown rendering (docs/op-index.md)
# ============================================================================

static func render_markdown() -> String:
	var lines: Array = []
	lines.append("# Op index (generated)")
	lines.append("")
	lines.append("Generated from `registry/op_registry.gd` by `tools/gen_docs.ps1` — do not edit by hand.")
	lines.append("")
	lines.append("Every tool commits one scene-pinned undo action per call and returns the same")
	lines.append("error codes as the core tools (`INVALID_PARAMS`, `VALUE_OUT_OF_RANGE`,")
	lines.append("`WRONG_TYPE`, `NODE_NOT_FOUND`, `PROPERTY_NOT_ON_CLASS`, `EDITOR_NOT_READY`).")
	lines.append("")
	for family_name in family_names():
		var info := family(family_name)
		lines.append("## `%s`" % family_name)
		lines.append("")
		lines.append(str(info.get("summary", "")))
		lines.append("")
		lines.append("Handler: `%s`" % str(info.get("handler", "")))
		lines.append("")
		lines.append("| op | What it does | Params |")
		lines.append("| --- | --- | --- |")
		for descriptor in info.get("ops", []):
			var params: Array = []
			for param in descriptor.get("params", []):
				params.append("`%s`" % param)
			lines.append("| `%s` | %s | %s |" % [
				descriptor.get("name", ""),
				descriptor.get("summary", ""),
				", ".join(params),
			])
		lines.append("")
		lines.append("### `%s` parameters" % family_name)
		lines.append("")
		lines.append("| Param | Type | Notes |")
		lines.append("| --- | --- | --- |")
		var schema: Dictionary = info.get("schema", {})
		var properties: Dictionary = schema.get("properties", {})
		for param_name in properties:
			var prop: Dictionary = properties[param_name]
			var type_label := str(prop.get("type", "any"))
			if prop.has("enum"):
				type_label += ": " + " \\| ".join(prop.enum)
			if prop.has("default"):
				type_label += " (default `%s`)" % str(prop.get("default"))
			lines.append("| `%s` | %s | %s |" % [param_name, type_label, str(prop.get("description", ""))])
		lines.append("")
		var required: Array = schema.get("required", [])
		if not required.is_empty():
			var required_list: Array = []
			for name in required:
				required_list.append("`%s`" % name)
			lines.append("Required: %s." % ", ".join(required_list))
			lines.append("")
		lines.append("### Examples")
		lines.append("")
		lines.append("```json")
		for descriptor in info.get("ops", []):
			var example = descriptor.get("example", {})
			if example.is_empty():
				continue
			lines.append(JSON.stringify(example))
		lines.append("```")
		lines.append("")
	return "\n".join(lines)
