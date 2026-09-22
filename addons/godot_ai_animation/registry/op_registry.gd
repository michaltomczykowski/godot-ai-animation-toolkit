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
	}


static func family_names() -> Array:
	return [FAMILY_PRESETS, FAMILY_EDIT, FAMILY_INSPECT]


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
		+ "dry_run (run any animation_presets / animation_edit op without "
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
				"enum": ["animation_presets", "animation_edit"],
				"description": "dry_run: which tool to run. help: which tool's ops to list (omit for all).",
			},
			"forward_op": {
				"type": "string",
				"description": "dry_run: the presets/edit op to run (e.g. \"retime\"); its own params go in the same call.",
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
