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
const FAMILY_LIBRARY := "animation_library"
const FAMILY_RIG := "animation_rig"
const FAMILY_RIG_MODIFIERS := "animation_rig_modifiers"
const FAMILY_MOTION := "animation_motion"

const MAX_DESCRIPTION_CHARS := 600
## The core registry rejects a custom tool whose params schema serializes past
## this (McpCustomToolSpec.MAX_SCHEMA_BYTES); the Godot AI server re-checks the
## pushed schema with python json.dumps (spaced separators), so the effective
## budget is a few hundred bytes tighter. A rejected family disappears silently
## and one bad definition drops the whole catalog - the tier-1 suite checks
## every schema against that stricter measurement.
const MAX_SCHEMA_BYTES := 8192


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
			"deferred": true,
			"timeout_ms": 30000,
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
		FAMILY_LIBRARY: {
			"handler": "res://addons/godot_ai_animation/handlers/library.gd",
			"summary": "Project library: reusable templates and JSON clip specs.",
			"description": _library_description(),
			"schema": _library_schema(),
			"ops": _library_ops(),
			"requires_writable": true,
			"undoable": true,
		},
		FAMILY_RIG: {
			"handler": "res://addons/godot_ai_animation/handlers/rig.gd",
			"summary": "Rig authoring: poses, clips from poses, rig inspection, recipes.",
			"description": _rig_description(),
			"schema": _schema_for(_rig_schema(), _rig_ops()),
			"ops": _rig_ops(),
			"requires_writable": true,
			"undoable": true,
			## bake_pose_sequence drives a full skeleton update per sample.
			"timeout_ms": 30000,
		},
		FAMILY_RIG_MODIFIERS: {
			"handler": "res://addons/godot_ai_animation/handlers/rig.gd",
			"summary": "Skeleton modifier setup: IK, springs, look-at, retarget, twist.",
			"description": _rig_modifiers_description(),
			"schema": _schema_for(_rig_schema(), _rig_modifiers_ops()),
			"ops": _rig_modifiers_ops(),
			"requires_writable": true,
			"undoable": true,
			## Not promoted: the server promotes at most eight tools, and with nine
			## families this one would be sorted out of the promoted set anyway. It
			## stays fully callable as custom_tool:animation_rig_modifiers.
			"promoted": false,
			"timeout_ms": 30000,
		},
		FAMILY_MOTION: {
			"handler": "res://addons/godot_ai_animation/handlers/motion.gd",
			"summary": "Procedural locomotion and idle cycles for a humanoid skeleton.",
			"description": _motion_description(),
			"schema": _motion_schema(),
			"ops": _motion_ops(),
			"requires_writable": true,
			"undoable": true,
			## Dense sampling plus a two-bone solve per sample.
			"timeout_ms": 30000,
		},
	}


static func family_names() -> Array:
	return [
		FAMILY_PRESETS, FAMILY_FX, FAMILY_GRAPH, FAMILY_EDIT, FAMILY_INSPECT,
		FAMILY_LIBRARY, FAMILY_RIG, FAMILY_MOTION, FAMILY_RIG_MODIFIERS,
	]


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
		+ "Ops: retime, retarget, reverse, mirror, offset, ease_range, set_interp, "
		+ "trim, split_at, merge, amplitude, loop, key_edit, cleanup, plus quality "
		+ "passes: smooth, resample, add_noise, overlap (per-limb follow-through) "
		+ "and layer (additive/mix another clip). Needs player_path + "
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
					"smooth", "resample", "reduce", "add_noise", "overlap", "layer",
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
			"strength": {"type": "number", "description": "smooth: 0-1 lerp toward the neighbour midpoint (0.5)."},
			"passes": {"type": "integer", "description": "smooth: passes over the keys (1)."},
			"fps": {"type": "number", "description": "resample: samples per second (30; 0-120)."},
			"angle": {"type": "number", "description": "reduce: error budget for rotation tracks, degrees (0.5)."},
			"value_tolerance": {"type": "number", "description": "reduce: error budget for other value tracks, units (0.001)."},
			"max_keys": {"type": "integer", "description": "reduce: key cap per track (0 = no cap)."},
			"amount": {"type": "number", "description": "add_noise: degrees for rotations, units for position/scale (2)."},
			"frequency": {"type": "number", "description": "add_noise: noise cycles across the track (3)."},
			"seed": {"type": "integer", "description": "add_noise: deterministic noise seed (0)."},
			"delay": {"type": "number", "description": "overlap: seconds to delay the matched tracks (needed for follow-through)."},
			"weight": {"type": "number", "description": "layer: 0-1 blend toward the source clip (1)."},
			"source_animation": {"type": "string", "description": "layer: clip to combine in."},
			"source_player_path": {"type": "string", "description": "layer: player holding the source clip (default: the edited player)."},
			"layer_mode": {
				"type": "string",
				"enum": ["add", "mix"],
				"description": "layer: add applies the source's delta from its first key, mix blends toward it.",
			},
			"remap_node": {"type": "string", "description": "layer: rewrite the source's node path to this node before matching."},
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
		{
			"name": "smooth",
			"summary": "Soften key values toward their neighbours - follow-through cleanup for noisy captures.",
			"params": ["player_path", "animation_name", "strength", "passes", "track_path"],
			"example": {"op": "smooth", "player_path": "/Main", "animation_name": "walk", "strength": 0.5, "passes": 2},
		},
		{
			"name": "resample",
			"summary": "Rebuild value tracks at a fixed sample rate, keeping the curve (engine-exact interpolation).",
			"params": ["player_path", "animation_name", "fps", "interpolation", "track_path"],
			"example": {"op": "resample", "player_path": "/Main", "animation_name": "walk", "fps": 30, "interpolation": "linear"},
		},
		{
			"name": "reduce",
			"summary": "Drop the keys a clip does not need, inside a measured error budget: `angle` degrees for rotation tracks, `value` units for the rest. The dense procedural cycles (70+ keys per bone) shrink to a fraction of their keys with the shape intact - unlike `resample`, no key moves onto a new grid. Reports keys removed and the worst measured error.",
			"params": ["player_path", "animation_name", "angle", "value_tolerance", "max_keys", "track_path"],
			"example": {"op": "reduce", "player_path": "/Main/Rig/AnimationPlayer", "animation_name": "walk", "angle": 0.5, "value_tolerance": 0.001},
		},
		{
			"name": "add_noise",
			"summary": "Add seeded, smooth micro-motion to value keys (breathing, tremor, life).",
			"params": ["player_path", "animation_name", "amount", "frequency", "seed", "track_path"],
			"example": {"op": "add_noise", "player_path": "/Main", "animation_name": "idle", "amount": 0.4, "frequency": 2.0, "track_path": "Skeleton3D:B-head"},
		},
		{
			"name": "overlap",
			"summary": "Delay one node/subtree's tracks by `delay` seconds - instant follow-through on any clip.",
			"params": ["player_path", "animation_name", "track_path", "delay", "wrap"],
			"example": {"op": "overlap", "player_path": "/Main", "animation_name": "walk", "track_path": "Skeleton3D:B-forearm.L", "delay": 0.08, "wrap": true},
		},
		{
			"name": "layer",
			"summary": "Combine another clip: add its delta from its first key (jiggle/breathing) or mix toward it.",
			"params": ["player_path", "animation_name", "source_animation", "source_player_path", "layer_mode", "weight", "remap_node"],
			"example": {"op": "layer", "player_path": "/Main", "animation_name": "walk", "source_animation": "idle", "layer_mode": "add", "weight": 0.4},
		},
	])


# ============================================================================
# animation_inspect
# ============================================================================

static func _inspect_description() -> String:
	return (
		"Read-only inspection for animation work: describe (clip summary), "
		+ "timeline (per-track keys), audit (broken paths, dead clips, loop "
		+ "seams, autoplay conflicts), compare (diff two clips), stats "
		+ "(scene-wide numbers), motion_report (key density, spikes, seam pops, "
		+ "flips), rig_profile (roles/candidates, T/A pose, limb reach, "
		+ "capabilities; saves a reusable profile), sample (FK probe: world "
		+ "positions, foot heights, contact windows), preview (deferred offscreen "
		+ "PNGs), dry_run (any generator/edit op, uncommitted), help (op index). "
		+ "Never mutates the scene or the undo stack. Requires the Godot AI addon."
	)


static func _inspect_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"op": {
				"type": "string",
				"enum": ["describe", "timeline", "audit", "compare", "stats", "motion_report", "motion_audit", "rig_profile", "sample", "preview", "dry_run", "help"],
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
				"enum": ["animation_presets", "animation_fx", "animation_graph", "animation_edit", "animation_library", "animation_rig", "animation_motion"],
				"description": "dry_run: which tool to run. help: which tool's ops to list (omit for all).",
			},
			"forward_op": {
				"type": "string",
				"description": "dry_run: the generator or edit op to run (e.g. \"retime\"); its own params go in the same call.",
			},
			"op_name": {
				"type": "string",
				"description": "help: only this op (omit to list the tool's whole index).",
			},
			"skeleton_path": {
				"type": "string",
				"description": "rig_profile/sample/preview: scene path to the Skeleton3D (default: the first one in the scene).",
			},
			"character_path": {
				"type": "string",
				"description": "preview: node copied into the frame, props included (default: the skeleton's outermost ancestor).",
			},
			"roles": {
				"type": "object",
				"description": "rig_profile/sample: explicit bone roles, e.g. {\"thigh_l\": \"B-thigh.L\"}; they win over detection.",
			},
			"profile": {
				"type": "string",
				"description": "rig_profile/sample: a saved rig profile (name or res:// path) whose roles are reused.",
			},
			"save": {
				"type": "boolean",
				"default": false,
				"description": "rig_profile: write the profile to res://animation_toolkit/rig_profiles/<name>.json.",
			},
			"name": {
				"type": "string",
				"description": "rig_profile: profile file name (default: the skeleton node name).",
			},
			"overwrite": {
				"type": "boolean",
				"default": false,
				"description": "rig_profile: replace an existing profile file. preview: replace existing PNGs (on).",
			},
			"bones": {
				"type": "array",
				"items": {"type": "string"},
				"description": "sample: bones to probe ([\"*\"] = every bone; default: the detected role bones).",
			},
			"times": {
				"type": "array",
				"items": {"type": "number"},
				"description": "sample/preview: explicit sample times in seconds (alternative to samples).",
			},
			"samples": {
				"type": "integer",
				"description": "sample/preview: evenly spaced samples over the clip (sample 24, preview 4; max 240).",
			},
			"include_rotation": {
				"type": "boolean",
				"default": false,
				"description": "sample: also report each bone's euler rotation in degrees.",
			},
			"contact_threshold": {
				"type": "number",
				"description": "sample/motion_audit: height above the lowest foot sample counted as ground contact (default 0.02).",
			},
			"max_slide": {
				"type": "number",
				"description": "motion_audit: worst foot travel while planted to pass, metres (0.05).",
			},
			"max_hip_bob": {
				"type": "number",
				"description": "motion_audit: hips' vertical range to pass, metres (0.12).",
			},
			"width": {"type": "integer", "description": "preview: frame width in pixels (480)."},
			"height": {"type": "integer", "description": "preview: frame height in pixels (270)."},
			"output_dir": {
				"type": "string",
				"description": "preview: directory for the PNGs (res://animation_toolkit/previews).",
			},
			"basename": {"type": "string", "description": "preview: file name prefix (default: the clip name)."},
			"yaw": {"type": "number", "description": "preview: camera yaw in degrees, 0 = front (28)."},
			"elevation": {"type": "number", "description": "preview: camera elevation in degrees (8)."},
			"margin": {"type": "number", "description": "preview: framing margin around the bones (1.35)."},
			"background": {"type": "string", "description": "preview: frame background colour (#2b2f36)."},
			"dry_run": {
				"type": "boolean",
				"description": "rig_profile: report without writing the profile file (off).",
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
			"name": "motion_report",
			"summary": "Per-track motion quality: key density, peak speed/acceleration, loop-seam pops, hemisphere flips, constant tracks - each with a fix hint.",
			"params": ["player_path", "animation_name", "max_tracks"],
			"example": {"op": "motion_report", "player_path": "/Main", "animation_name": "walk"},
		},
		{
			"name": "motion_audit",
			"summary": "Play the clip on a Skeleton3D (posed and restored, never saved) and grade it: per-foot ground-contact windows and the horizontal slide while planted, hip bob and travel, each pass/fail against a budget with a fix hint. The numeric answer to 'is this walk actually planted?' - a moonwalk reports a slide in metres, not a vibe. Needs foot/hips roles (auto-detected or via roles/profile).",
			"params": ["player_path", "animation_name", "skeleton_path", "roles", "profile", "samples", "contact_threshold", "max_slide", "max_hip_bob"],
			"example": {"op": "motion_audit", "player_path": "/Main/Rig/AnimationPlayer", "animation_name": "walk", "skeleton_path": "/Main/Rig/Skeleton3D", "max_slide": 0.03},
		},
		{
			"name": "rig_profile",
			"summary": "Understand a rig: detected roles with candidates, T/A pose, limb lengths/reach, facing/lateral axes, capabilities, missing roles and suggested ops; save=true writes a reusable profile.",
			"params": ["skeleton_path", "roles", "profile", "save", "name", "overwrite", "dry_run"],
			"example": {"op": "rig_profile", "skeleton_path": "/Main/Rig/Skeleton3D", "save": true, "name": "hero"},
		},
		{
			"name": "sample",
			"summary": "FK probe: world positions (and optional euler rotations) of requested bones at N times, plus derived foot heights and ground-contact windows. Pose is restored afterwards.",
			"params": ["player_path", "animation_name", "skeleton_path", "roles", "profile", "bones", "times", "samples", "include_rotation", "contact_threshold"],
			"example": {"op": "sample", "player_path": "/Main/Rig/AnimationPlayer", "animation_name": "walk", "bones": ["B-foot.L", "B-foot.R"], "samples": 24},
		},
		{
			"name": "preview",
			"summary": "Render the posed character offscreen to PNGs at clip times so an agent can see contact, foot planting and follow-through. A private copy of the character subtree is posed in an offscreen viewport; the edited scene is never touched. The reply is deferred (one editor frame per image) and needs a rendering device.",
			"params": ["player_path", "animation_name", "skeleton_path", "character_path", "times", "samples", "width", "height", "output_dir", "basename", "yaw", "elevation", "margin", "background", "overwrite"],
			"example": {"op": "preview", "player_path": "/Main/Rig/AnimationPlayer", "animation_name": "reach", "skeleton_path": "/Main/Rig/Skeleton3D", "times": [0.0, 0.4], "output_dir": "res://animation_toolkit/previews", "yaw": 28},
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
# animation_library
# ============================================================================

static func _library_description() -> String:
	return (
		"Project library for reuse and interchange. Templates: save any "
		+ "presets/fx/motion/rig call as a named recipe in res://animation_toolkit/"
		+ "library.json, then apply it later (with per-call overrides) to other "
		+ "players or targets. Clip specs: export a clip to JSON, import/validate "
		+ "one, or build a clip from a spec file or inline spec (optionally "
		+ "remapping every track onto another node). File writes are not part of "
		+ "the undo stack; clip creation is one scene-pinned undo action. "
		+ "Requires the Godot AI addon."
	)


static func _library_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"op": {
				"type": "string",
				"enum": [
					"template_save", "template_apply", "template_list", "template_delete",
					"spec_export", "spec_import", "spec_apply",
				],
				"description": "Which library op to run.",
			},
			"name": {"type": "string", "description": "Template name (save/apply/delete)."},
			"tool": {
				"type": "string",
				"enum": ["animation_presets", "animation_fx", "animation_motion", "animation_rig"],
				"description": "template_save: which tool the stored op belongs to.",
			},
			"forward_op": {
				"type": "string",
				"description": "template_save: the presets/fx/motion/rig op to store (e.g. \"bounce\"); its params go in the same call.",
			},
			"description": {"type": "string", "description": "template_save: a note for other agents/users."},
			"library_path": {
				"type": "string",
				"description": "Template library file (default res://animation_toolkit/library.json).",
			},
			"path": {
				"type": "string",
				"description": "spec_export/import/apply: JSON spec file. Export defaults to res://animation_toolkit/clips/<clip>.json.",
			},
			"spec": {
				"type": "object",
				"description": "spec_import/spec_apply: an inline clip spec instead of a file.",
			},
			"player_path": {"type": "string", "description": "Scene path to the AnimationPlayer (spec_export/apply)."},
			"animation_name": {"type": "string", "description": "Clip to export, or the name to create when applying."},
			"target_path": {
				"type": "string",
				"description": "spec_apply: rewrite every track's node part to this node (apply a spec to another node).",
			},
			"overwrite": {
				"type": "boolean",
				"default": false,
				"description": "Replace an existing template/clip/file with the same name.",
			},
			"dry_run": {
				"type": "boolean",
				"default": false,
				"description": "Report what the call would do without writing anything.",
			},
		},
		"required": ["op"],
	}


static func _library_ops() -> Array:
	return [
		{
			"name": "template_save",
			"summary": "Save a presets/fx/motion/rig call (its op and params) as a named template in the project library.",
			"params": ["name", "tool", "forward_op", "description", "library_path", "overwrite", "dry_run"],
			"example": {"op": "template_save", "name": "button_pop", "tool": "animation_presets", "forward_op": "bounce", "intensity": 0.2, "duration": 0.5},
		},
		{
			"name": "template_apply",
			"summary": "Apply a saved template through its original tool, with per-call overrides.",
			"params": ["name", "library_path", "player_path", "target_path", "animation_name", "overwrite", "dry_run"],
			"example": {"op": "template_apply", "name": "button_pop", "player_path": "/Main/HUD", "target_path": "MenuButton"},
		},
		{
			"name": "template_list",
			"summary": "List the saved templates with their tool, op, description and params.",
			"params": ["library_path"],
			"example": {"op": "template_list"},
		},
		{
			"name": "template_delete",
			"summary": "Remove a template from the library file.",
			"params": ["name", "library_path", "dry_run"],
			"example": {"op": "template_delete", "name": "button_pop"},
		},
		{
			"name": "spec_export",
			"summary": "Write a clip to a JSON spec file (typed values, method and audio tracks included).",
			"params": ["player_path", "animation_name", "path", "overwrite"],
			"example": {"op": "spec_export", "player_path": "/Main/HUD", "animation_name": "open"},
		},
		{
			"name": "spec_import",
			"summary": "Read and validate a spec file or inline spec, reporting tracks, keys and issues.",
			"params": ["path", "spec"],
			"example": {"op": "spec_import", "path": "res://animation_toolkit/clips/open.json"},
		},
		{
			"name": "spec_apply",
			"summary": "Build a clip from a spec file or inline spec, optionally remapping every track onto another node.",
			"params": ["player_path", "animation_name", "path", "spec", "target_path", "overwrite", "dry_run"],
			"example": {"op": "spec_apply", "player_path": "/Main/HUD", "path": "res://animation_toolkit/clips/open.json", "target_path": "/Main/HUD/Panel2", "animation_name": "open_2"},
		},
	]


# ============================================================================
# animation_rig
# ============================================================================

static func _rig_description() -> String:
	return (
		"Rig authoring: bones (rig_chain), poses (pose_save/pose_apply/pose_blend/"
		+ "pose_to_clip/pose_list), rig dumps (rig_get) and procedural recipes "
		+ "(walk_cycle, idle_breathing, blink, jumping_jack, squat, punch, "
		+ "bake_pose_sequence). Torso twist/lean is distributed over the detected "
		+ "spine chain. Modifier setup lives in animation_rig_modifiers."
	)


static func _rig_modifiers_description() -> String:
	return (
		"Skeleton modifier setup: TwoBoneIK3D (ik_setup, including spline "
		+ "chains), SpringBoneModifier3D (spring_setup), LookAtModifier3D "
		+ "(look_at_setup), RetargetModifier3D (retarget_setup) and "
		+ "TwistModifier3D (twist_setup). Each setup is verified after it commits "
		+ "and rolled back if the wiring did not take. Modifiers are created "
		+ "inactive because an active one also drives the scene while you edit it."
	)


static func _rig_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"op": {
				"type": "string",
				"enum": ["pose_save", "pose_apply", "pose_blend", "pose_to_clip", "pose_list", "rig_get", "rig_chain", "ik_setup", "spring_setup", "look_at_setup", "retarget_setup", "twist_setup", "walk_cycle", "idle_breathing", "blink", "jumping_jack", "squat", "punch", "bake_pose_sequence"],
				"description": "Rig op to run.",
			},
			"roles": {
				"type": "object",
				"description": "Recipes: bone roles {\"thigh_l\": \"B-thigh.L\"}; rest auto-detect.",
			},
			"stride": {"type": "number", "description": "walk_cycle: leg swing deg (25); jumping_jack: spread (18)."},
			"knee_bend": {"type": "number", "description": "walk_cycle: knee bend, degrees (30)."},
			"arm_swing": {"type": "number", "description": "walk_cycle: arm counter-swing deg (20)."},
			"arm_down": {"type": "number", "description": "walk_cycle: lower arms this many degrees from rest (T-pose)."},
			"bob": {"type": "number", "description": "Metres: walk/idle bob, jumping_jack rise, squat depth, punch crouch."},
			"swing_axis": {"type": "string", "enum": ["x", "y", "z"], "description": "walk_cycle: swing axis (x)."},
			"axis": {"type": "string", "enum": ["x", "y", "z"], "description": "idle_breathing / blink: rotation axis (x)."},
			"amplitude": {"type": "number", "description": "Degrees: idle_breathing chest (2), jumping_jack arms (80), squat arms (65), punch twist (12)."},
			"head_amplitude": {"type": "number", "description": "idle_breathing: head counter-rotation, deg (1)."},
			"mode": {"type": "string", "enum": ["scale", "rotate"], "description": "blink: how the lid closes (scale)."},
			"closed_scale": {"type": "number", "description": "blink scale: closed Y scale (0.05)."},
			"angle": {"type": "number", "description": "blink rotate: closing angle, deg (25)."},
			"blinks": {"type": "integer", "description": "blink: blinks per clip (1)."},
			"cycles": {"type": "integer", "description": "punch: punches per clip (2; odd ends mid-combo)."},
			"fps": {"type": "integer", "description": "bake_pose_sequence: samples/s (30)."},
			"source_animation": {"type": "string", "description": "bake_pose_sequence: clip to sample."},
			"skeleton_path": {
				"type": "string",
				"description": "Skeleton3D/2D path (default: first one).",
			},
			"bones": {
				"type": "array",
				"items": {"type": ["string", "object"]},
				"description": "rig_chain: [{name, parent?, position?, rotation?, scale?, length?}]; else a bone filter.",
			},
			"node_path": {
				"type": "string",
				"description": "rig_chain: Node3D/Node2D subtree to become a skeleton (locals = rests).",
			},
			"kind": {
				"type": "string",
				"enum": ["3d", "2d", "two_bone", "ccdik", "fabrik", "jacobian", "spline"],
				"description": "rig_chain: 3d|2d. ik_setup: solver (two_bone|ccdik|fabrik|jacobian|spline; spline follows a Path3D).",
			},
			"chain": {
				"type": "array",
				"items": {"type": "string"},
				"description": "ik_setup: bones root -> effector (3 for two_bone, else root + end).",
			},
			"target_path": {"type": "string", "description": "ik_setup: target node (a Path3D for spline); created at the tip if omitted."},
			"target_name": {"type": "string", "description": "ik_setup: name of the created target (IKTarget)."},
			"pole_path": {"type": "string", "description": "ik_setup two_bone: pole node for the bend."},
			"use_virtual_end": {
				"type": "boolean",
				"description": "ik_setup two_bone: last chain bone = effector (off).",
			},
			"end_bone_length": {"type": "number", "description": "ik_setup: virtual end length (0.1)."},
			"active": {
				"type": "boolean",
				"description": "Modifier setups: enable now (off).",
			},
			"springs": {
				"type": "array",
				"items": {"type": "object"},
				"description": "spring_setup: [{root_bone, end_bone?, stiffness?, drag?, gravity?, radius?}]; end_bone = leaf.",
			},
			"mutable_bone_axes": {"type": "boolean", "description": "spring_setup: allow any-axis rotation (off)."},
			"bone": {"type": "string", "description": "look_at: bone that tracks the target."},
			"spine_chain": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Recipes: torso chain, hips first (auto-detected).",
			},
			"disperse": {
				"type": "object",
				"description": "twist_setup: {root_bone, end_bone?, mode? even|weighted, weight_position?, damping?, twist_from_rest?}; root/end default to the chain.",
			},
			"forward_axis": {"type": "string", "enum": ["+x", "-x", "+y", "-y", "+z", "-z"], "description": "look_at: look direction (+z)."},
			"origin_from": {"type": "string", "enum": ["self", "bone", "external_node"], "description": "look_at: look-direction source (self)."},
			"origin_bone": {"type": "string", "description": "look_at: origin bone (origin_from=bone)."},
			"origin_node": {"type": "string", "description": "look_at: origin node (with external_node)."},
			"origin_offset": {"description": "look_at: origin offset."},
			"origin_safe_margin": {"type": "number", "description": "look_at: origin dead zone."},
			"use_angle_limitation": {"type": "boolean", "description": "look_at: clamp the rotation (off)."},
			"primary_limit_angle": {"type": "number", "description": "look_at: primary limit, degrees."},
			"secondary_limit_angle": {"type": "number", "description": "look_at: secondary limit, degrees."},
			"use_secondary_rotation": {"type": "boolean", "description": "look_at: secondary axis rotation (off)."},
			"primary_axis": {"type": "string", "enum": ["x", "y", "z"], "description": "look_at: primary rotation axis (y)."},
			"relative": {"type": "boolean", "description": "look_at: relative to rest (off)."},
			"duration": {"type": "number", "description": "look_at: turn time, seconds (0 = instant)."},
			"profile": {
				"type": "string",
				"description": "retarget_setup: auto|humanoid|res:// path; recipes: saved rig profile.",
			},
			"position": {"type": "boolean", "description": "retarget_setup: bone positions (off)."},
			"rotation": {"type": "boolean", "default": true, "description": "retarget_setup: bone rotations (on)."},
			"scale": {"type": "boolean", "description": "retarget_setup: bone scales (off)."},
			"use_global_pose": {"type": "boolean", "description": "retarget_setup: global poses (off; length match)."},
			"move_target": {"type": "boolean", "description": "retarget_setup: move target under modifier (on)."},
			"name": {
				"type": "string",
				"description": "Pose name under res://animation_toolkit/poses/.",
			},
			"path": {"type": "string", "description": "Explicit pose JSON path."},
			"pose": {"type": "object", "description": "Inline pose (as pose_save returns)."},
			"from": {"description": "pose_blend: first pose (inline|name)."},
			"to": {"description": "pose_blend: second pose (inline|name)."},
			"factor": {"type": "number", "description": "pose_blend: 0=from, 1=to (0.5)."},
			"mirror": {
				"type": "boolean",
				"description": "Mirror across X (off; swaps L/R).",
			},
			"blend": {
				"type": "number",
				"description": "pose_apply: 0-1 blend toward target (1).",
			},
			"reset_first": {
				"type": "boolean",
				"description": "pose_apply: reset poses first (off).",
			},
			"player_path": {"type": "string", "description": "pose_to_clip: AnimationPlayer for the clip."},
			"animation_name": {"type": "string", "description": "pose_to_clip: clip name (pose_clip)."},
			"keys": {
				"type": "array",
				"items": {"type": "object"},
				"description": "pose_to_clip: [{pose|name|path, time, transition?, mirror?, aim?}].",
			},
			"positions": {
				"type": "boolean",
				"description": "pose_to_clip: also key positions (off).",
			},
			"scales": {"type": "boolean", "description": "pose_to_clip: also key scales (off)."},
			"loop_mode": {
				"type": "string",
				"enum": ["none", "linear", "pingpong"],
				"description": "pose_to_clip: loop mode (none).",
			},
			"directory": {"type": "string", "description": "pose_list: directory to scan."},
			"pose_dir": {"type": "string", "description": "Directory for named pose files."},
			"include_pose": {
				"type": "boolean",
				"description": "rig_get: include pose deltas (on).",
			},
			"overwrite": {
				"type": "boolean",
				"description": "Replace an existing pose or clip (off).",
			},
			"dry_run": {
				"type": "boolean",
				"description": "Report without committing (off).",
			},
		},
		"required": ["op"],
	}


## A schema holding only the properties `ops` actually declare, taken from a
## bigger one. The rig family used to publish 73 properties for 19 ops and sat
## ~340 bytes under the server's 8192-byte cap; splitting the modifier ops out
## gives each half a schema sized to what it accepts, and keeps one list of
## property definitions as the single source of truth.
static func _schema_for(schema: Dictionary, ops: Array) -> Dictionary:
	var wanted := {"op": true}
	for entry in ops:
		for key in (entry as Dictionary).get("params", []):
			wanted[str(key)] = true
	var properties := {}
	for key in (schema.get("properties", {}) as Dictionary).keys():
		if wanted.has(str(key)):
			properties[key] = schema.properties[key]
	# Narrow the op enum to the ops this half owns. Copying the parent enum would
	# advertise the other half's ops, and a caller that picked one would get a
	# family that does not handle it.
	var op_property: Dictionary = (schema.get("properties", {}).get("op", {}) as Dictionary).duplicate()
	op_property["enum"] = []
	for entry in ops:
		op_property["enum"].append(str((entry as Dictionary).get("name", "")))
	properties["op"] = op_property
	var out := {"type": "object", "properties": properties}
	if schema.has("required"):
		out["required"] = (schema.get("required", []) as Array).duplicate()
	return out


static func _rig_ops() -> Array:
	return _with_dry_run([
		{
			"name": "pose_save",
			"summary": "Capture a skeleton's pose as portable rest-relative data (inline and/or a pose file).",
			"params": ["skeleton_path", "name", "path", "pose_dir", "bones", "overwrite"],
			"example": {"op": "pose_save", "skeleton_path": "/Main/Rig/Skeleton3D", "name": "wave_mid"},
		},
		{
			"name": "pose_apply",
			"summary": "Write a saved or inline pose onto a skeleton, with blend / mirror / reset options.",
			"params": ["skeleton_path", "name", "path", "pose_dir", "pose", "blend", "mirror", "reset_first", "bones"],
			"example": {"op": "pose_apply", "skeleton_path": "/Main/Rig/Skeleton3D", "name": "wave_mid", "blend": 0.5},
		},
		{
			"name": "pose_blend",
			"summary": "Blend two poses (slerp rotations, lerp positions) into a new pose.",
			"params": ["from", "to", "factor", "mirror", "name", "path", "pose_dir", "overwrite"],
			"example": {"op": "pose_blend", "from": "idle", "to": "wave_mid", "factor": 0.35, "name": "wave_low"},
		},
		{
			"name": "pose_to_clip",
			"summary": "Keyframe a pose sequence into an Animation clip; a key's `aim` solves a three-bone chain so the end bone's origin lands on a world `target`, bending into the `pole` half-plane (or the base pose's bend when `pole` is omitted). The skeleton pose is left untouched, so contact keys bake exact contact into the clip.",
			"params": ["player_path", "skeleton_path", "animation_name", "keys", "positions", "scales", "loop_mode", "pose_dir", "overwrite"],
			"example": {"op": "pose_to_clip", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "wave", "loop_mode": "linear", "keys": [{"name": "idle", "time": 0.0}, {"name": "wave_mid", "time": 0.5, "transition": "ease_in_out"}, {"name": "idle", "time": 1.0}]},
		},
		{
			"name": "pose_list",
			"summary": "List the pose files saved in the project's pose directory.",
			"params": ["directory"],
			"example": {"op": "pose_list"},
		},
		{
			"name": "rig_get",
			"summary": "Dump a skeleton's bones, rests, pose, modifiers and springs, plus issues.",
			"params": ["skeleton_path", "include_pose"],
			"example": {"op": "rig_get", "skeleton_path": "/Main/Rig/Skeleton3D"},
		},
		{
			"name": "rig_chain",
			"summary": "Build bones on a skeleton from a bone spec, or turn a Node3D/Node2D subtree into a skeleton.",
			"params": ["skeleton_path", "bones", "node_path", "kind", "name", "overwrite"],
			"example": {"op": "rig_chain", "skeleton_path": "/Main/Rig/Skeleton3D", "bones": [{"name": "spine", "position": [0, 0.2, 0]}, {"name": "chest", "parent": "spine", "position": [0, 0.3, 0]}]},
		},
		{
			"name": "walk_cycle",
			"summary": "Build a looping in-place walk cycle (legs, knees, counter-swinging arms, hip bob) from bone roles.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "stride", "knee_bend", "arm_swing", "arm_down", "bob", "swing_axis", "roles", "profile", "loop_mode", "overwrite"],
			"example": {"op": "walk_cycle", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "walk", "duration": 1.0, "loop_mode": "linear"},
		},
		{
			"name": "idle_breathing",
			"summary": "Build a subtle looping idle: the whole torso chain breathes (ramping from the lower spine to the chest), the head counter-moves, and an optional hip bob rides along.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "amplitude", "head_amplitude", "bob", "axis", "roles", "profile", "spine_chain", "loop_mode", "overwrite"],
			"example": {"op": "idle_breathing", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "idle", "duration": 3.0, "loop_mode": "linear"},
		},
		{
			"name": "blink",
			"summary": "Build a quick blink clip on the eye/eyelid bones, scale or rotate, optionally several blinks.",
			"params": ["player_path", "skeleton_path", "animation_name", "bones", "mode", "closed_scale", "angle", "axis", "blinks", "duration", "roles", "profile", "loop_mode", "overwrite"],
			"example": {"op": "blink", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "bones": ["eyelid.L", "eyelid.R"], "animation_name": "blink"},
		},
		{
			"name": "jumping_jack",
			"summary": "Build a looping jumping jack: arms swing down to overhead while the legs spread apart and back together, with a small rise.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "amplitude", "stride", "bob", "roles", "profile", "loop_mode", "overwrite"],
			"example": {"op": "jumping_jack", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "jack", "duration": 1.0, "loop_mode": "linear"},
		},
		{
			"name": "squat",
			"summary": "Build a looping squat with planted feet: the hips drop, the knees bend forward and the leg chains are solved to keep the ankles in place.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "bob", "amplitude", "roles", "profile", "loop_mode", "overwrite"],
			"example": {"op": "squat", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "squat", "duration": 2.0, "bob": 0.25, "loop_mode": "linear"},
		},
		{
			"name": "punch",
			"summary": "Build a looping boxing combo: guard, then alternating straight punches. `amplitude` is the *total* torso twist in degrees, spread up the spine chain (most of it in the upper chest); `cycles` punches fit in the clip.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "cycles", "amplitude", "bob", "roles", "profile", "spine_chain", "loop_mode", "overwrite"],
			"example": {"op": "punch", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "boxing", "duration": 0.8, "cycles": 2, "loop_mode": "linear"},
		},
		{
			"name": "bake_pose_sequence",
			"summary": "Sample a skeleton over time into a clip: seek the source clip, run the active modifiers (IK, springs, retarget), key the final pose.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "fps", "bones", "positions", "scales", "source_animation", "loop_mode", "overwrite"],
			"example": {"op": "bake_pose_sequence", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "walk_baked", "duration": 1.0, "loop_mode": "linear"},
		},
	])


# ============================================================================
# animation_rig_modifiers
# ============================================================================

## The five modifier setups, split out of `animation_rig` because the server
## promotes at most eight tools: with nine families in the catalog, this one
## stays reachable through custom_manage instead of crowding out a promoted
## tool. It is deliberately NOT promoted (see `families()`).
static func _rig_modifiers_ops() -> Array:
	return _with_dry_run([
		{
			"name": "ik_setup",
			"summary": "Attach a 3D IK modifier to a skeleton and wire it to a target node. kind=spline follows a Path3D (target_path) instead, because SplineIK3D solves against a path.",
			"params": ["skeleton_path", "kind", "chain", "target_path", "target_name", "pole_path", "use_virtual_end", "end_bone_length", "name", "active"],
			"example": {"op": "ik_setup", "skeleton_path": "/Main/Rig/Skeleton3D", "kind": "two_bone", "chain": ["B-upperArm.L", "B-forearm.L", "B-hand.L"], "target_name": "HandTarget"},
		},
		{
			"name": "spring_setup",
			"summary": "Attach spring bones (SpringBoneSimulator3D) to a skeleton, one spring setting per entry.",
			"params": ["skeleton_path", "springs", "name", "active", "mutable_bone_axes"],
			"example": {"op": "spring_setup", "skeleton_path": "/Main/Rig/Skeleton3D", "springs": [{"root_bone": "B-hair01", "stiffness": 0.3, "drag": 0.2, "gravity": 0.1, "radius": 0.05}]},
		},
		{
			"name": "look_at_setup",
			"summary": "Attach a look-at modifier so one bone tracks a target node (created in front of the bone when omitted).",
			"params": ["skeleton_path", "bone", "target_path", "target_name", "forward_axis", "origin_from", "origin_bone", "origin_node", "origin_offset", "origin_safe_margin", "use_angle_limitation", "primary_limit_angle", "secondary_limit_angle", "use_secondary_rotation", "primary_axis", "relative", "duration", "name", "active"],
			"example": {"op": "look_at_setup", "skeleton_path": "/Main/Rig/Skeleton3D", "bone": "B-head", "target_name": "HeadTarget", "forward_axis": "+z"},
		},
		{
			"name": "retarget_setup",
			"summary": "Retarget a source skeleton's poses onto a child target skeleton through a RetargetModifier3D and a bone-name profile.",
			"params": ["skeleton_path", "target_path", "profile", "position", "rotation", "scale", "use_global_pose", "move_target", "name", "active"],
			"example": {"op": "retarget_setup", "skeleton_path": "/Main/Source/Skeleton3D", "target_path": "/Main/Target/Skeleton3D", "profile": "auto"},
		},
		{
			"name": "twist_setup",
			"summary": "Attach a BoneTwistDisperser3D so a twist on one bone is spread over the bones above it: the root/end default to the detected spine chain and `mode` picks even or weighted distribution (`weight_position`/`damping` shape the falloff). Godot builds the per-joint list at runtime, so custom amounts live in the modifier's Inspector. Created inactive, like every modifier setup.",
			"params": ["skeleton_path", "disperse", "spine_chain", "name", "active"],
			"example": {"op": "twist_setup", "skeleton_path": "/Main/Rig/Skeleton3D", "disperse": {"root_bone": "B-hips", "end_bone": "B-chest", "mode": "even"}},
		},
	])


# ============================================================================
# animation_motion
# ============================================================================

static func _motion_description() -> String:
	return (
		"Procedural humanoid motion: walk_cycle, run_cycle, strafe_cycle, "
		+ "idle_cycle and a generic cycle build dense clips with two-bone IK leg "
		+ "solves (planted feet, toe roll), pelvis bob/sway/yaw/roll, "
		+ "counter-rotating torso and forward elbow follow-through; jump and "
		+ "turn_cycle are one-shots, walk_start/walk_stop blend in and out of a "
		+ "gait, and secondary_motion bakes spring bones. `speed` solves the "
		+ "stride from a target m/s; style/overrides tune the motion; root_motion "
		+ "keys and wires travel. character_setup builds idle+walk+run and the "
		+ "locomotion tree in one call."
	)


static func _motion_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"op": {
				"type": "string",
				"enum": ["walk_cycle", "run_cycle", "idle_cycle", "cycle", "jump", "turn_cycle", "strafe_cycle", "walk_start", "walk_stop", "character_setup", "secondary_motion"],
				"description": "Cycle/move to build, character_setup for the whole locomotion set, or secondary_motion to bake spring bones into an existing clip.",
			},
			"preset": {
				"type": "string",
				"enum": ["walk", "run", "idle"],
				"description": "cycle: which cycle to build (walk).",
			},
			"player_path": {
				"type": "string",
				"description": "Scene path to the AnimationPlayer that receives the clip.",
			},
			"skeleton_path": {
				"type": "string",
				"description": "Scene path to the Skeleton3D (default: the first one).",
			},
			"animation_name": {
				"type": "string",
				"description": "Clip name (default: the cycle name).",
			},
			"duration": {
				"type": "number",
				"description": "Clip length in seconds; one gait cycle fits in it.",
			},
			"style": {
				"type": "string",
				"enum": ["default", "relaxed", "heavy", "sneaky"],
				"description": "Motion style preset, applied before overrides.",
			},
			"overrides": {
				"type": "object",
				"description": "Deep tuning, e.g. {\"stride\": 18, \"lag\": 0.1}; walk/run keys: stride, knee_bend, arm_swing, arm_twist, bob, sway, hip_yaw, hip_roll, chest_yaw, twist_spread, lean, foot_lift, elbow, elbow_swing, lag, stance, crouch; idle keys: amplitude, head_amplitude, look, twist, bob, sway, shift, noise, lean, arm_sway, elbow, arm_twist, twist_spread.",
			},
			"samples": {
				"type": "number",
				"description": "Keys per second of clip (24; clamped to 4-120).",
			},
			"root_motion": {
				"type": "boolean",
				"description": "Also key the hips forward at the cycle's implied speed (off); wires player.root_motion_track unless set_root_motion=false.",
			},
			"set_root_motion": {
				"type": "boolean",
				"description": "root_motion: also set AnimationPlayer.root_motion_track in the same action (on).",
			},
			"speed": {
				"type": "number",
				"description": "Gait: target ground speed in m/s; solves the stride and warns when unreachable at this duration.",
			},
			"direction": {
				"type": "string",
				"enum": ["left", "right"],
				"description": "turn_cycle / strafe_cycle: which way to turn or step (left).",
			},
			"angle": {
				"type": "number",
				"description": "turn_cycle: turn angle in degrees (90).",
			},
			"steps": {
				"type": "integer",
				"description": "turn_cycle: pivot steps the turn is split into (1).",
			},
			"height": {
				"type": "number",
				"description": "jump: apex height in metres (0.5).",
			},
			"crouch": {
				"type": "number",
				"description": "jump: anticipation/landing crouch depth in metres (0.24).",
			},
			"distance": {
				"type": "number",
				"description": "jump: forward travel in metres over the clip (0 = in place).",
			},
			"phase": {
				"type": "number",
				"description": "walk_start/walk_stop: gait phase (0-1) the transition meets, e.g. 0 = left contact (0).",
			},
			"stride": {
				"type": "number",
				"description": "Gait: leg swing, degrees (walk 24, run 34).",
			},
			"knee_bend": {
				"type": "number",
				"description": "Gait: planted crouch, degrees (walk 30, run 55).",
			},
			"arm_swing": {
				"type": "number",
				"description": "Gait: arm counter-swing, degrees (walk 20, run 34).",
			},
			"arm_down": {
				"type": "number",
				"description": "Lower the arms this many degrees from the rest pose (T-pose rigs).",
			},
			"bob": {
				"type": "number",
				"description": "Pelvis bob, metres peak-to-peak (walk 0.05; idle 0.006).",
			},
			"sway": {
				"type": "number",
				"description": "Pelvis lateral sway, metres (walk 0.02; idle 0.012).",
			},
			"lean": {
				"type": "number",
				"description": "Forward lean, degrees (walk 3, run 9; idle slouch 1.5).",
			},
			"amplitude": {
				"type": "number",
				"description": "idle_cycle: breathing chest rotation, degrees (1.6).",
			},
			"head_amplitude": {
				"type": "number",
				"description": "idle_cycle: head nod/drift, degrees (0.8).",
			},
			"spine_chain": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Torso chain for twist/lean, hips first (auto-detected; must be one parent chain).",
			},
			"twist_spread": {
				"type": "number",
				"description": "0 keeps the twist on the hips, 1 spreads it over the whole chain (1; also an override key).",
			},
			"roles": {
				"type": "object",
				"description": "Bone roles, e.g. {\"thigh_l\": \"B-thigh.L\"}; missing ones auto-detect.",
			},
			"profile": {
				"type": "string",
				"description": "Saved rig profile (name or res:// path) from animation_inspect rig_profile; supplies the roles.",
			},
			"bones": {
				"type": "array",
				"items": {"type": "string"},
				"description": "secondary_motion: jiggle bones to bake (must be unkeyed in the clip).",
			},
			"stiffness": {
				"type": "number",
				"description": "secondary_motion: spring stiffness, 1/s^2 (120; hair ~120, heavy tail ~30).",
			},
			"damping": {
				"type": "number",
				"description": "secondary_motion: spring damping, 1/s (12; lower swings longer).",
			},
			"loop_mode": {
				"type": "string",
				"enum": ["none", "linear", "pingpong"],
				"description": "Loop mode (none; cycles use linear).",
			},
			"overwrite": {
				"type": "boolean",
				"description": "Replace an existing clip with the same name (off; character_setup defaults to on).",
			},
			"active": {
				"type": "boolean",
				"description": "character_setup: enable the AnimationTree right away (off; an active tree drives the scene while you edit).",
			},
			"tree_path": {
				"type": "string",
				"description": "character_setup: scene path for the AnimationTree (default: an existing tree wired to the player, else a new sibling).",
			},
			"idle_duration": {
				"type": "number",
				"description": "character_setup: idle clip length in seconds (3.0).",
			},
			"run_duration": {
				"type": "number",
				"description": "character_setup: run clip length in seconds (0.6).",
			},
			"run_speed": {
				"type": "number",
				"description": "character_setup: run speed in m/s, the blend space's max (4.0; must exceed speed).",
			},
			"include_jump": {
				"type": "boolean",
				"description": "character_setup: also build a jump clip and a one-shot layer with a request parameter (off).",
			},
			"include_turn": {
				"type": "boolean",
				"description": "character_setup: also build a turn_<direction> clip (off).",
			},
			"jump_duration": {
				"type": "number",
				"description": "character_setup: jump clip length in seconds (1.2).",
			},
			"turn_duration": {
				"type": "number",
				"description": "character_setup: turn clip length in seconds (0.7).",
			},
			"dry_run": {
				"type": "boolean",
				"description": "Report without committing (off).",
			},
		},
		"required": ["op"],
	}


static func _motion_ops() -> Array:
	var gait_params := [
		"player_path", "skeleton_path", "animation_name", "duration", "style",
		"overrides", "samples", "root_motion", "set_root_motion", "speed", "stride",
		"knee_bend", "arm_swing", "arm_down", "bob", "sway", "lean", "roles",
		"profile", "spine_chain", "twist_spread", "loop_mode", "overwrite",
	]
	var idle_params := [
		"player_path", "skeleton_path", "animation_name", "duration", "style",
		"overrides", "samples", "amplitude", "head_amplitude", "bob", "sway",
		"lean", "roles", "profile", "spine_chain", "twist_spread", "loop_mode",
		"overwrite",
	]
	return _with_dry_run([
		{
			"name": "walk_cycle",
			"summary": "Build a looping walk with planted feet: pelvis bob/sway/yaw/roll, counter-rotating torso, arm swing with elbow follow-through, head stabilisation.",
			"params": gait_params,
			"example": {"op": "walk_cycle", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "walk", "duration": 1.0, "loop_mode": "linear"},
		},
		{
			"name": "run_cycle",
			"summary": "Build a looping run: flight phase, forward lean, bigger stride and arm swing, bent elbows.",
			"params": gait_params,
			"example": {"op": "run_cycle", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "run", "duration": 0.6, "loop_mode": "linear"},
		},
		{
			"name": "idle_cycle",
			"summary": "Build a looping idle: a pronounced look-around and torso twist over subtle breathing, weight shift and seeded micro-motion.",
			"params": idle_params,
			"example": {"op": "idle_cycle", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "idle", "duration": 3.0, "loop_mode": "linear"},
		},
		{
			"name": "cycle",
			"summary": "Generic entry point: build the cycle named by `preset` (walk, run or idle) with the same parameters as the dedicated ops.",
			"params": ["preset"] + gait_params + ["amplitude", "head_amplitude"],
			"example": {"op": "cycle", "preset": "run", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "run", "duration": 0.6, "loop_mode": "linear"},
		},
		{
			"name": "character_setup",
			"summary": "One call, one undo: build idle + walk + run (optionally jump/turn), wire the locomotion AnimationTree and set the root-motion track; returns the speed parameter and a game-side snippet.",
			"params": ["player_path", "skeleton_path", "roles", "profile", "style", "samples", "speed", "run_speed", "duration", "run_duration", "idle_duration", "root_motion", "include_jump", "include_turn", "height", "crouch", "distance", "jump_duration", "angle", "direction", "turn_duration", "tree_path", "active", "overwrite"],
			"example": {"op": "character_setup", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "speed": 1.4, "run_speed": 4.0, "include_jump": true},
		},
		{
			"name": "secondary_motion",
			"summary": "Bake offline spring bones into an existing clip: hair/tail/cloth roots lag behind their animated parent, deterministically.",
			"params": ["player_path", "skeleton_path", "animation_name", "bones", "stiffness", "damping", "samples"],
			"example": {"op": "secondary_motion", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "walk", "bones": ["B-hair01", "B-hair02"], "stiffness": 120.0, "damping": 12.0},
		},
		{
			"name": "jump",
			"summary": "Build a one-shot jump: anticipation crouch, launch, air arc, landing absorb and recovery; feet planted before takeoff and after landing, and the lean is spread up `spine_chain`.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "height", "crouch", "distance", "style", "overrides", "samples", "roles", "profile", "spine_chain", "loop_mode", "overwrite"],
			"example": {"op": "jump", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "jump", "duration": 1.2, "height": 0.6, "crouch": 0.25},
		},
		{
			"name": "turn_cycle",
			"summary": "Build an in-place pivot turn with anticipation, a stepping foot and a settle; one-shot, direction left/right. `steps` splits a big turn into that many pivot steps (opposite foot each) so a 180-degree turn reads as weight shifts, not a spin; the torso lead is bounded per step and spread over `spine_chain`, so a long spine cannot corkscrew; re-base the root yaw between steps in your driver.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "angle", "direction", "steps", "style", "overrides", "samples", "roles", "profile", "spine_chain", "loop_mode", "overwrite"],
			"example": {"op": "turn_cycle", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "turn_left", "duration": 0.7, "angle": 90, "direction": "left"},
		},
		{
			"name": "strafe_cycle",
			"summary": "Build a looping sideways gait (leading foot steps out, trailing closes) with the knees still facing forward; speed-driven like the walk.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "direction", "speed", "stride", "style", "overrides", "samples", "root_motion", "set_root_motion", "roles", "profile", "loop_mode", "overwrite"],
			"example": {"op": "strafe_cycle", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "strafe_left", "duration": 0.9, "direction": "left", "speed": 0.8, "loop_mode": "linear"},
		},
		{
			"name": "walk_start",
			"summary": "Build a short blend into a gait: rest -> the walk pose at `phase`, so it matches the cycle frame-for-frame.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "phase", "style", "overrides", "samples", "roles", "profile", "loop_mode", "overwrite"],
			"example": {"op": "walk_start", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "walk_start", "duration": 0.35, "phase": 0.0},
		},
		{
			"name": "walk_stop",
			"summary": "Build a short blend out of a gait: the walk pose at `phase` -> rest with a settle.",
			"params": ["player_path", "skeleton_path", "animation_name", "duration", "phase", "style", "overrides", "samples", "roles", "profile", "loop_mode", "overwrite"],
			"example": {"op": "walk_stop", "player_path": "/Main/Rig/AnimationPlayer", "skeleton_path": "/Main/Rig/Skeleton3D", "animation_name": "walk_stop", "duration": 0.35, "phase": 0.5},
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
