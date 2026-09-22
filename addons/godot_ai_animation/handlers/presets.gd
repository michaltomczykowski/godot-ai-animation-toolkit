@tool
extends RefCounted

## One-call motion presets for the AnimationPlayer surface, exposed as the
## Godot AI custom tool `animation_presets` (op = pulse/bounce/orbit/sweep/drift).
##
## Each preset_* method:
##   1. Validates params + resolves the player (auto-creating its default lib).
##   2. Resolves the target node + classifies it as control / 2d / 3d.
##   3. Builds a single-track Animation with shape-appropriate keyframes.
##   4. Commits ONE scene-pinned undo action, so a single Ctrl-Z rolls back any
##      auto-created library + the animation (+ a recentered Control pivot).
##
## Self-contained by design: no core animation-handler internals are used, so
## the addon only depends on the Godot AI custom-tools registration API.


const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")

## Loop modes the continuous presets (pulse/orbit/sweep/drift) accept.
const _LOOP_MODES := {
	"none": Animation.LOOP_NONE,
	"linear": Animation.LOOP_LINEAR,
	"pingpong": Animation.LOOP_PINGPONG,
}

## Angular segments per orbit turn. Linear interpolation between keys is
## straight, so this is the circle approximation density.
const _ORBIT_SEGMENTS := 16


## Rollup entry registered with the Godot AI tool registry.
func run(params: Dictionary, _ctx) -> Dictionary:
	var op: String = params.get("op", "")
	match op:
		"pulse":
			return preset_pulse(params)
		"bounce":
			return preset_bounce(params)
		"orbit":
			return preset_orbit(params)
		"sweep":
			return preset_sweep(params)
		"drift":
			return preset_drift(params)
		"spin":
			return preset_spin(params)
		"float":
			return preset_float(params)
		"stagger":
			return preset_stagger(params)
		"showcase":
			return preset_showcase(params)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
		"Unknown op '%s'. Valid: pulse, bounce, orbit, sweep, drift, spin, float, stagger, showcase" % op)


## Every preset needs the editor undo manager (injected by the addon's
## EditorPlugin, or by the test suite).
func _context_error() -> Dictionary:
	if ToolContext.undo_redo == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY,
			"Godot AI Animation Toolkit is not initialized - enable the 'Godot AI Animation Toolkit' plugin")
	return {}


## Resolve the existing animation a preset would replace. Returns
## `{old_anim: Animation|null}` when the name is free or `overwrite` is set,
## or `{error: <error dict>}` when the name is taken and overwrite is off.
## One site for the duplicate-detection error keeps every preset consistent.
static func _existing_animation(library: AnimationLibrary, anim_name: String, overwrite: bool) -> Dictionary:
	if not library.has_animation(anim_name):
		return {"old_anim": null}
	if not overwrite:
		return {"error": ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Animation '%s' already exists. Pass overwrite=true or delete it first." % anim_name)}
	return {"old_anim": library.get_animation(anim_name)}


# ============================================================================
# animation_preset_pulse
# ============================================================================

func preset_pulse(params: Dictionary) -> Dictionary:
	var player_path: String = params.get("player_path", "")
	var target_path: String = params.get("target_path", "")
	var property: String = params.get("property", "scale")
	var from_scale: float = float(params.get("from_scale", 1.0))
	var to_scale: float = float(params.get("to_scale", 1.1))
	var duration: float = float(params.get("duration", 0.4))
	var anim_name: String = params.get("animation_name", "")
	var overwrite: bool = params.get("overwrite", false)

	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if target_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: target_path")
	if property.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: property")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	var loop_result := _resolve_loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var loop_mode: int = loop_result.ok

	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved: Dictionary = _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true

	var target_resolved := _resolve_preset_target(player, target_path)
	if target_resolved.has("error"):
		return target_resolved
	var target: Node = target_resolved.node
	var kind: String = target_resolved.kind
	var track_target: String = target_resolved.track_path_root
	var track_path := "%s:%s" % [track_target, property]

	## Two shapes: the original scale shortcut (from_scale/to_scale floats) and
	## the general form (property + from_value/to_value coerced against the
	## property's real type, so modulate:a breathes as floats and position
	## jitters as vectors).
	var from_vec: Variant
	var to_vec: Variant
	var used_scale_shortcut := false
	if property == "scale" and not params.has("from_value") and not params.has("to_value"):
		used_scale_shortcut = true
		if from_scale <= 0.0:
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'from_scale' must be > 0")
		if to_scale <= 0.0:
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'to_scale' must be > 0")
		if kind == "3d":
			from_vec = Vector3(from_scale, from_scale, from_scale)
			to_vec = Vector3(to_scale, to_scale, to_scale)
		else:
			from_vec = Vector2(from_scale, from_scale)
			to_vec = Vector2(to_scale, to_scale)
	else:
		if not (params.has("from_value") and params.has("to_value")):
			return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
				"'from_value' and 'to_value' are required when 'property' is not 'scale' (got '%s')" % property)
		var from_result := ValueCodec.coerce_for_property(params.get("from_value"), target, property)
		if from_result.has("error"):
			return from_result
		from_vec = from_result.ok
		var to_result := ValueCodec.coerce_for_property(params.get("to_value"), target, property)
		if to_result.has("error"):
			return to_result
		to_vec = to_result.ok

	if anim_name.is_empty():
		anim_name = "pulse"

	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var old_anim: Animation = existing.old_anim

	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = loop_mode

	_add_property_track(anim, track_path, build_pulse_keys(from_vec, to_vec, duration))

	_commit_animation_add(
		"MCP: Create animation %s" % anim_name,
		player, library, created_library, anim_name, anim, old_anim,
	)

	var data := {
		"player_path": player_path,
		"animation_name": anim_name,
		"property": property,
		"length": duration,
		"loop_mode": ValueCodec.loop_mode_to_string(loop_mode),
		"track_count": anim.get_track_count(),
		"library_created": created_library,
		"overwritten": old_anim != null,
		"undoable": true,
	}
	if used_scale_shortcut:
		data["from_scale"] = from_scale
		data["to_scale"] = to_scale
	else:
		data["from_value"] = ValueCodec.serialize(from_vec)
		data["to_value"] = ValueCodec.serialize(to_vec)
	return {"data": data}


# ============================================================================
# animation_preset_bounce
# ============================================================================

## Center-pivot scale overshoot with a settle-back — UI press feedback.
## Controls get `pivot_offset` recentered in the same undo action so the pop
## originates from the middle of the widget, not its top-left corner.
func preset_bounce(params: Dictionary) -> Dictionary:
	var player_path: String = params.get("player_path", "")
	var target_path: String = params.get("target_path", "")
	var intensity: float = float(params.get("intensity", 0.15))
	var duration: float = float(params.get("duration", 0.4))
	var anim_name: String = params.get("animation_name", "")
	var overwrite: bool = params.get("overwrite", false)

	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if target_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: target_path")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if intensity <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'intensity' must be > 0")

	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved: Dictionary = _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true

	var target_resolved := _resolve_preset_target(player, target_path)
	if target_resolved.has("error"):
		return target_resolved
	## Untyped: `scale` lives on Control/Node2D/Node3D, not on the Node base.
	var target = target_resolved.node
	var kind: String = target_resolved.kind
	var track_target: String = target_resolved.track_path_root

	if anim_name.is_empty():
		anim_name = "bounce"

	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var old_anim: Animation = existing.old_anim

	## Pop from the target's current scale, not identity: a widget that is
	## already scaled must not snap to 1.0 when the animation starts.
	var at_rest: Variant = target.scale

	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_NONE

	var track_path := "%s:scale" % track_target
	_add_property_track(anim, track_path, build_bounce_keys(at_rest, kind, intensity, duration))

	var extra_props := _control_pivot_props(target)
	_commit_animation_add(
		"MCP: Create animation %s" % anim_name,
		player, library, created_library, anim_name, anim, old_anim,
		extra_props,
	)

	return {
		"data": {
			"player_path": player_path,
			"animation_name": anim_name,
			"intensity": intensity,
			"length": duration,
			"keyframe_count": 4,
			"pivot_recentered": not extra_props.is_empty(),
			"track_count": anim.get_track_count(),
			"library_created": created_library,
			"overwritten": old_anim != null,
			"undoable": true,
		}
	}


# ============================================================================
# animation_preset_orbit
# ============================================================================

## Position traversing a circle around the target's current position —
## orbiting markers and HUD satellites. 3D orbits in the XZ plane; 2D and
## Controls orbit in screen space. The clip is seamless (last key == first),
## so loop_mode="linear" keeps it going.
func preset_orbit(params: Dictionary) -> Dictionary:
	var player_path: String = params.get("player_path", "")
	var target_path: String = params.get("target_path", "")
	var clockwise: bool = params.get("clockwise", true)
	var duration: float = float(params.get("duration", 2.0))
	var anim_name: String = params.get("animation_name", "")
	var overwrite: bool = params.get("overwrite", false)

	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if target_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: target_path")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	var loop_result := _resolve_loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var loop_mode: int = loop_result.ok

	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved: Dictionary = _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true

	var target_resolved := _resolve_preset_target(player, target_path)
	if target_resolved.has("error"):
		return target_resolved
	var target: Node = target_resolved.node
	var kind: String = target_resolved.kind
	var track_target: String = target_resolved.track_path_root

	var default_radius: float = 1.0 if kind == "3d" else 100.0
	var radius: float = float(params.get("radius", default_radius))
	if radius <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'radius' must be > 0")

	if anim_name.is_empty():
		anim_name = "orbit"

	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var old_anim: Animation = existing.old_anim

	var center: Variant = target.position
	var keyframes := build_orbit_keys(center, kind, radius, clockwise, duration)

	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = loop_mode

	var track_path := "%s:position" % track_target
	_add_property_track(anim, track_path, keyframes)

	_commit_animation_add(
		"MCP: Create animation %s" % anim_name,
		player, library, created_library, anim_name, anim, old_anim,
	)

	return {
		"data": {
			"player_path": player_path,
			"animation_name": anim_name,
			"radius": radius,
			"clockwise": clockwise,
			"length": duration,
			"loop_mode": ValueCodec.loop_mode_to_string(loop_mode),
			"keyframe_count": keyframes.size(),
			"track_count": anim.get_track_count(),
			"library_created": created_library,
			"overwritten": old_anim != null,
			"undoable": true,
		}
	}


# ============================================================================
# animation_preset_sweep
# ============================================================================

## A full-turn rotation sweep — radar scans, cooldown-ring accents. Controls
## get `pivot_offset` recentered in the same undo action so the sweep rotates
## around the widget's middle. The clip is seamless, so loop_mode="linear"
## turns it into a continuous sweep.
func preset_sweep(params: Dictionary) -> Dictionary:
	var player_path: String = params.get("player_path", "")
	var target_path: String = params.get("target_path", "")
	var clockwise: bool = params.get("clockwise", true)
	var turns: float = float(params.get("turns", 1.0))
	var duration: float = float(params.get("duration", 1.0))
	var anim_name: String = params.get("animation_name", "")
	var overwrite: bool = params.get("overwrite", false)

	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if target_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: target_path")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if turns <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'turns' must be > 0")
	var loop_result := _resolve_loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var loop_mode: int = loop_result.ok

	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved: Dictionary = _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true

	var target_resolved := _resolve_preset_target(player, target_path)
	if target_resolved.has("error"):
		return target_resolved
	## Untyped: `rotation` lives on Control/Node2D/Node3D, not on the Node base.
	var target = target_resolved.node
	var kind: String = target_resolved.kind
	var track_target: String = target_resolved.track_path_root

	if anim_name.is_empty():
		anim_name = "sweep"

	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var old_anim: Animation = existing.old_anim

	## Sweep from the target's current orientation instead of snapping it to 0.
	var start_rotation: float = float(target.rotation.y) if kind == "3d" else float(target.rotation)

	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = loop_mode

	## 3D nodes rotate around their local Y axis; Control/Node2D have a single
	## `rotation` property.
	var track_path := "%s:rotation:y" % track_target if kind == "3d" else "%s:rotation" % track_target
	_add_property_track(anim, track_path, build_sweep_keys(start_rotation, turns, clockwise, duration))

	var extra_props := _control_pivot_props(target)
	_commit_animation_add(
		"MCP: Create animation %s" % anim_name,
		player, library, created_library, anim_name, anim, old_anim,
		extra_props,
	)

	return {
		"data": {
			"player_path": player_path,
			"animation_name": anim_name,
			"clockwise": clockwise,
			"turns": turns,
			"start_rotation": start_rotation,
			"length": duration,
			"loop_mode": ValueCodec.loop_mode_to_string(loop_mode),
			"pivot_recentered": not extra_props.is_empty(),
			"track_count": anim.get_track_count(),
			"library_created": created_library,
			"overwritten": old_anim != null,
			"undoable": true,
		}
	}


# ============================================================================
# animation_preset_drift
# ============================================================================

## A one-axis position offset over the clip — scanlines, marquee text,
## conveyor motion. The clip ends at a net offset from its start, so
## loop_mode="linear" would snap the target back each cycle; use "pingpong"
## (back and forth) or "none" (play once).
func preset_drift(params: Dictionary) -> Dictionary:
	var player_path: String = params.get("player_path", "")
	var target_path: String = params.get("target_path", "")
	var axis: String = params.get("axis", "x")
	var duration: float = float(params.get("duration", 1.0))
	var anim_name: String = params.get("animation_name", "")
	var overwrite: bool = params.get("overwrite", false)

	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if target_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: target_path")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	var loop_result := _resolve_loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var loop_mode: int = loop_result.ok
	if loop_mode == Animation.LOOP_LINEAR:
		return ErrorCodes.make(
			ErrorCodes.VALUE_OUT_OF_RANGE,
			(
				"preset_drift ends at a net offset from its start, so loop_mode 'linear' "
				+ "would snap the target back each cycle — use 'pingpong' or 'none'"
			),
		)

	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved: Dictionary = _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true

	var target_resolved := _resolve_preset_target(player, target_path)
	if target_resolved.has("error"):
		return target_resolved
	var target: Node = target_resolved.node
	var kind: String = target_resolved.kind
	var track_target: String = target_resolved.track_path_root

	var default_distance: float = 1.0 if kind == "3d" else 100.0
	var distance: float = float(params.get("distance", default_distance))
	if distance == 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'distance' must be non-zero")

	var offset: Variant
	if kind == "3d":
		match axis:
			"x": offset = Vector3(distance, 0.0, 0.0)
			"y": offset = Vector3(0.0, distance, 0.0)
			"z": offset = Vector3(0.0, 0.0, distance)
			_: return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Invalid axis '%s' for a 3D target. Valid: x, y, z" % axis)
	else:
		match axis:
			"x": offset = Vector2(distance, 0.0)
			"y": offset = Vector2(0.0, distance)
			_: return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Invalid axis '%s' for a 2D target. Valid: x, y" % axis)

	if anim_name.is_empty():
		anim_name = "drift"

	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var old_anim: Animation = existing.old_anim

	var start_pos: Variant = target.position
	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = loop_mode

	var track_path := "%s:position" % track_target
	_add_property_track(anim, track_path, build_drift_keys(start_pos, offset, duration))

	_commit_animation_add(
		"MCP: Create animation %s" % anim_name,
		player, library, created_library, anim_name, anim, old_anim,
	)

	return {
		"data": {
			"player_path": player_path,
			"animation_name": anim_name,
			"axis": axis,
			"distance": distance,
			"length": duration,
			"loop_mode": ValueCodec.loop_mode_to_string(loop_mode),
			"track_count": anim.get_track_count(),
			"library_created": created_library,
			"overwritten": old_anim != null,
			"undoable": true,
		}
	}


# ============================================================================
# Helpers — preset resolution
# ============================================================================

## Resolve a preset target node and classify its transform kind.
##
## Accepts two `target_path` shapes:
##   * Scene-absolute (starts with "/") — resolved through
##     `ValueCodec.resolve_scene_path`, matching the convention used by every
##     other scene-mutating tool. Targets
##     outside the player's `root_node` subtree are converted to `..`-prefixed
##     paths via `root_node.get_path_to(target)`, mirroring what the relative
##     form accepts and how Godot stores track paths.
##   * Relative — used as-is against the player's `root_node`, matching how
##     animation tracks themselves are stored.
##
## Returns `{node, kind, track_path_root}` where `track_path_root` is the path
## (relative to `root_node`) that callers should embed in the track path. For
## scene-absolute inputs this is the converted relative path; for relative
## inputs it equals the input. `kind` ∈ {"control", "2d", "3d"}.
##
## Uses the same root-node fallback (`root_node` when set, else the player's
## parent) that the core animation tooling uses, so tool inputs match how the
## track path resolves at playback.
func _resolve_preset_target(player: AnimationPlayer, target_path: String) -> Dictionary:
	var root_node := ValueCodec.player_root_node(player)
	if root_node == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"AnimationPlayer at %s has no resolvable root_node (is the scene open?)" % str(player.get_path()))

	var target: Node = null
	var track_path_root: String = target_path
	if target_path.begins_with("/"):
		var scene_root := EditorInterface.get_edited_scene_root()
		if scene_root == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Cannot resolve scene-absolute target_path '%s': no scene open" % target_path)
		target = ValueCodec.resolve_scene_path(target_path, scene_root)
		if target == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				ValueCodec.format_node_error(target_path, scene_root))
		# Convert to a root_node-relative path. For targets outside the
		# subtree this yields a `..`-prefixed path, matching what the
		# relative form already accepts (root_node.get_node_or_null
		# resolves `..` segments) and what Godot's animation engine
		# stores natively.
		track_path_root = str(root_node.get_path_to(target))
	else:
		target = root_node.get_node_or_null(target_path)
		if target == null:
			# root_node.get_path() leaks the editor's SubViewport-wrapped
			# path; use the clean scene-relative form so the hint is
			# actionable.
			var scene_root := EditorInterface.get_edited_scene_root()
			var root_hint := ValueCodec.from_node(root_node, scene_root) if scene_root != null else str(root_node.name)
			var abs_example := "/%s/path/to/target" % scene_root.name if scene_root != null else "/SceneRoot/path/to/target"
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				("Target node not found at '%s' (resolved relative to AnimationPlayer's root_node '%s'). "
				+ "Pass a path relative to root_node (e.g. \"path/to/target\") or a scene-absolute path (e.g. \"%s\").")
				% [target_path, root_hint, abs_example])

	var kind: String
	if target is Control:
		kind = "control"
	elif target is Node2D:
		kind = "2d"
	elif target is Node3D:
		kind = "3d"
	else:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Target '%s' must be a Control, Node2D, or Node3D (got %s)" % [target_path, target.get_class()])
	return {"node": target, "kind": kind, "track_path_root": track_path_root}


## Validate the optional `loop_mode` param the continuous presets accept.
## Returns `{ok: <Animation.LOOP_* int>}` or `{error: msg}`.
static func _resolve_loop_mode(params: Dictionary) -> Dictionary:
	var mode: String = params.get("loop_mode", "none")
	if not _LOOP_MODES.has(mode):
		return {"error": "Invalid loop_mode '%s'. Valid: %s" % [mode, ", ".join(_LOOP_MODES.keys())]}
	return {"ok": _LOOP_MODES[mode]}


## Bundle a Control's `pivot_offset` recenter into the preset's undo action so
## a scale/rotation pop originates from the widget's middle. Non-Controls and
## already-centered pivots return an empty list.
static func _control_pivot_props(target: Node) -> Array:
	if not target is Control:
		return []
	var control := target as Control
	var desired := control.size * 0.5
	if control.pivot_offset.is_equal_approx(desired):
		return []
	return [{"object": control, "property": "pivot_offset", "value": desired, "old": control.pivot_offset}]


# ============================================================================
# Helpers — player + commit
# ============================================================================

## Resolve an AnimationPlayer and its default library for a preset. Returns
## `{player, library}` (library null when the player has no default library
## yet) or an error dict. Unlike the core ops, presets require an existing
## player — they never auto-create one.
func _resolve_player(player_path: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No edited scene open")
	var node := ValueCodec.resolve_scene_path(player_path, scene_root)
	if node == null:
		return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(player_path, scene_root))
	if not node is AnimationPlayer:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Node at %s is not an AnimationPlayer (got %s)" % [player_path, node.get_class()])
	var player := node as AnimationPlayer
	var library: AnimationLibrary = null
	if player.has_animation_library(""):
		library = player.get_animation_library("")
	return {"player": player, "library": library}


## Add one linear value track built from `[{time, value, transition?}]`.
static func _add_property_track(anim: Animation, track_path: String, keyframes: Array) -> void:
	var index := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(index, NodePath(track_path))
	anim.track_set_interpolation_type(index, Animation.INTERPOLATION_LINEAR)
	for keyframe in keyframes:
		anim.track_insert_key(
			index,
			float(keyframe.get("time", 0.0)),
			keyframe.get("value"),
			ValueCodec.parse_transition(keyframe.get("transition", "linear")),
		)


## Commit one scene-pinned undo action: optional library creation, the clip
## (replacing the old one when overwriting), and any bundled property changes
## (Control pivot recentering) so a single Ctrl-Z reverts all of it.
func _commit_animation_add(
	action_label: String,
	player: AnimationPlayer,
	library: AnimationLibrary,
	created_library: bool,
	anim_name: String,
	anim: Animation,
	old_anim: Animation,
	extra_props: Array = [],
) -> void:
	_create_scene_pinned_action(action_label)
	var undo := ToolContext.undo_redo
	if created_library:
		undo.add_do_method(player, "add_animation_library", "", library)
		undo.add_undo_method(player, "remove_animation_library", "")
		undo.add_do_reference(library)
	if old_anim != null:
		undo.add_do_method(library, "remove_animation", anim_name)
	undo.add_do_method(library, "add_animation", anim_name, anim)
	if old_anim != null:
		undo.add_undo_method(library, "remove_animation", anim_name)
		undo.add_undo_method(library, "add_animation", anim_name, old_anim)
		undo.add_do_reference(old_anim)
	else:
		undo.add_undo_method(library, "remove_animation", anim_name)
	for entry in extra_props:
		undo.add_do_property(entry.object, entry.property, entry.value)
		undo.add_undo_property(entry.object, entry.property, entry.old)
	undo.add_do_reference(anim)
	undo.commit_action()


## Open an action pinned to the edited scene's history. The first do-targets
## are scene-owned (player/library/control), and the explicit context keeps the
## action out of GLOBAL_HISTORY so a scene undo finds it.
func _create_scene_pinned_action(action_label: String) -> void:
	ToolContext.undo_redo.create_action(
		action_label, UndoRedo.MERGE_DISABLE, EditorInterface.get_edited_scene_root(),
	)


# ============================================================================
# animation_presets spin — 3D quaternion turn
# ============================================================================

## Continuous local-Y turn for 3D targets (quarter-turn quaternion keys).
## Control/2D targets use `sweep` instead.
func preset_spin(params: Dictionary) -> Dictionary:
	var player_path: String = params.get("player_path", "")
	var target_path: String = params.get("target_path", "")
	var clockwise: bool = params.get("clockwise", true)
	var turns: float = float(params.get("turns", 1.0))
	var duration: float = float(params.get("duration", 3.0))
	var anim_name: String = params.get("animation_name", "")
	var overwrite: bool = params.get("overwrite", false)

	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if target_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: target_path")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if turns <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'turns' must be > 0")
	var loop_result := _resolve_loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var loop_mode: int = loop_result.ok

	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved: Dictionary = _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true

	var target_resolved := _resolve_preset_target(player, target_path)
	if target_resolved.has("error"):
		return target_resolved
	var kind: String = target_resolved.kind
	var track_target: String = target_resolved.track_path_root
	if kind != "3d":
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"spin rotates a Node3D around its local Y axis; use 'sweep' for Control/2D targets")

	if anim_name.is_empty():
		anim_name = "spin"

	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var old_anim: Animation = existing.old_anim

	var keyframes := build_spin_keys(turns, clockwise, duration)
	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = loop_mode
	_add_property_track(anim, "%s:quaternion" % track_target, keyframes)

	_commit_animation_add(
		"MCP: Create animation %s" % anim_name,
		player, library, created_library, anim_name, anim, old_anim,
	)

	return {
		"data": {
			"player_path": player_path,
			"animation_name": anim_name,
			"clockwise": clockwise,
			"turns": turns,
			"length": duration,
			"loop_mode": ValueCodec.loop_mode_to_string(loop_mode),
			"keyframe_count": keyframes.size(),
			"track_count": anim.get_track_count(),
			"library_created": created_library,
			"overwritten": old_anim != null,
			"undoable": true,
		}
	}


# ============================================================================
# animation_presets showcase — build a runnable demo scene
# ============================================================================

## Build a runnable demo of every preset as one undoable subtree: seven nodes,
## seven AnimationPlayers with autoplaying clips (bounce/orbit/sweep/drift/
## pulse/spin/float). Press F6 (Run Current Scene) to watch it.
func preset_showcase(params: Dictionary) -> Dictionary:
	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No edited scene open")
	var parent_path: String = params.get("parent_path", "")
	var parent: Node = scene_root
	if not parent_path.is_empty():
		parent = ValueCodec.resolve_scene_path(parent_path, scene_root)
		if parent == null:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(parent_path, scene_root))
	var root_name: String = params.get("name", "AnimationShowcase")
	if parent.has_node(NodePath(root_name)):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"%s already has a child named '%s'" % [parent.name, root_name])

	var showcase := Node2D.new()
	showcase.name = root_name

	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(40, 24)
	title.text = "Godot AI Animation Toolkit - presets"
	title.add_theme_font_size_override("font_size", 24)
	showcase.add_child(title)

	var bounce_button := Button.new()
	bounce_button.name = "BounceButton"
	bounce_button.position = Vector2(620, 110)
	bounce_button.size = Vector2(220, 64)
	bounce_button.pivot_offset = bounce_button.size * 0.5
	bounce_button.text = "BOUNCE"
	showcase.add_child(bounce_button)

	var orbit_dot := ColorRect.new()
	orbit_dot.name = "OrbitDot"
	orbit_dot.position = Vector2(892, 142)
	orbit_dot.size = Vector2(16, 16)
	orbit_dot.color = Color(0.35, 0.6, 1.0)
	showcase.add_child(orbit_dot)

	var sweep_pivot := Node2D.new()
	sweep_pivot.name = "SweepPivot"
	sweep_pivot.position = Vector2(700, 420)
	showcase.add_child(sweep_pivot)
	var sweep_bar := ColorRect.new()
	sweep_bar.name = "SweepBar"
	sweep_bar.position = Vector2(-6, -80)
	sweep_bar.size = Vector2(12, 80)
	sweep_bar.color = Color(0.13, 0.83, 0.93)
	sweep_pivot.add_child(sweep_bar)

	var drift_line := ColorRect.new()
	drift_line.name = "DriftLine"
	drift_line.position = Vector2(620, 560)
	drift_line.size = Vector2(300, 4)
	drift_line.color = Color(0.29, 0.87, 0.5)
	showcase.add_child(drift_line)

	var pulse_label := Label.new()
	pulse_label.name = "PulseLabel"
	pulse_label.position = Vector2(620, 300)
	pulse_label.text = "PRESETS"
	pulse_label.add_theme_font_size_override("font_size", 36)
	showcase.add_child(pulse_label)

	## A small 3D island so the typed Transform3D float preset is demoed too.
	var world := Node3D.new()
	world.name = "World3D"
	showcase.add_child(world)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.position = Vector3(0.0, 0.0, 6.0)
	cam.current = true
	world.add_child(cam)
	var light := DirectionalLight3D.new()
	light.name = "Light"
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	world.add_child(light)
	var float_cube := MeshInstance3D.new()
	float_cube.name = "FloatCube"
	float_cube.position = Vector3(-3.4, 0.0, 0.0)
	float_cube.mesh = BoxMesh.new()
	world.add_child(float_cube)
	var spin_cube := MeshInstance3D.new()
	spin_cube.name = "SpinCube"
	spin_cube.position = Vector3(-1.7, 0.0, 0.0)
	var spin_mesh := BoxMesh.new()
	spin_mesh.size = Vector3(1.4, 1.4, 1.4)
	spin_cube.mesh = spin_mesh
	world.add_child(spin_cube)

	var animations: Array[Animation] = []
	var players: Array[String] = []
	_add_showcase_player(showcase, "AnimBounce", "bounce", "BounceButton:scale",
		build_bounce_keys(Vector2.ONE, "control", 0.15, 0.4), Animation.LOOP_NONE, animations, players)
	_add_showcase_player(showcase, "AnimOrbit", "orbit", "OrbitDot:position",
		build_orbit_keys(Vector2(900, 150), "2d", 60.0, true, 3.0), Animation.LOOP_LINEAR, animations, players)
	_add_showcase_player(showcase, "AnimSweep", "sweep", "SweepPivot:rotation",
		build_sweep_keys(0.0, 1.0, true, 2.0), Animation.LOOP_LINEAR, animations, players)
	_add_showcase_player(showcase, "AnimDrift", "drift", "DriftLine:position:x",
		build_drift_keys(620.0, 480.0, 2.0), Animation.LOOP_PINGPONG, animations, players)
	_add_showcase_player(showcase, "AnimPulse", "pulse", "PulseLabel:modulate:a",
		build_pulse_keys(0.2, 1.0, 1.2), Animation.LOOP_PINGPONG, animations, players)
	_add_showcase_player(showcase, "AnimFloat", "float", "World3D/FloatCube:transform",
		build_float_keys(float_cube.transform, 0.7, 1.25, 0.5, 2.4), Animation.LOOP_PINGPONG, animations, players)
	_add_showcase_player(showcase, "AnimSpin", "spin", "World3D/SpinCube:quaternion",
		build_spin_keys(1.0, true, 3.0), Animation.LOOP_LINEAR, animations, players)

	_create_scene_pinned_action("MCP: Create animation showcase")
	var undo := ToolContext.undo_redo
	undo.add_do_method(parent, "add_child", showcase, true)
	undo.add_undo_method(parent, "remove_child", showcase)
	undo.add_do_reference(showcase)
	for anim in animations:
		undo.add_do_reference(anim)
	undo.commit_action()
	## Owners are set after the commit (redo re-adds the same node instances,
	## so the assignment persists) — a Callable bound to this lazily loaded
	## handler must not sit inside a long-lived undo action.
	_assign_owners(showcase, scene_root)

	return {
		"data": {
			"path": ValueCodec.from_node(showcase, scene_root),
			"players": players,
			"animations": animations.size(),
			"undoable": true,
		}
	}


func _add_showcase_player(
	showcase: Node2D, player_name: String, clip_name: String, track_path: String,
	keyframes: Array, loop_mode: int, animations: Array[Animation], players: Array[String],
) -> void:
	var anim := Animation.new()
	anim.length = _last_key_time(keyframes)
	anim.loop_mode = loop_mode
	_add_property_track(anim, track_path, keyframes)
	var player := AnimationPlayer.new()
	player.name = player_name
	var library := AnimationLibrary.new()
	library.add_animation(clip_name, anim)
	player.add_animation_library("", library)
	player.autoplay = clip_name
	showcase.add_child(player)
	animations.append(anim)
	players.append(player_name)


static func _last_key_time(keyframes: Array) -> float:
	var last := 0.0
	for keyframe in keyframes:
		last = maxf(last, float(keyframe.get("time", 0.0)))
	return last


## Owner every node in a freshly built subtree so the scene can save it.
static func _assign_owners(node: Node, owner: Node) -> void:
	node.set_owner(owner)
	for child in node.get_children():
		_assign_owners(child, owner)


# ============================================================================
# animation_presets float — 3D bob with a scale/turn flourish
# ============================================================================

## Vertical bob for 3D targets (hovering pickups, floating platforms). The clip
## ends at a net offset, so loop_mode "linear" is refused — use "pingpong" for
## a hover loop or "none" for a one-shot.
func preset_float(params: Dictionary) -> Dictionary:
	var player_path: String = params.get("player_path", "")
	var target_path: String = params.get("target_path", "")
	var height: float = float(params.get("height", 0.7))
	var scale_factor: float = float(params.get("scale", 1.25))
	var turns: float = float(params.get("turns", 0.0))
	var duration: float = float(params.get("duration", 2.4))
	var anim_name: String = params.get("animation_name", "")
	var overwrite: bool = params.get("overwrite", false)

	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if target_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: target_path")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if height == 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'height' must be non-zero")
	if scale_factor <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'scale' must be > 0")
	var loop_result := _resolve_loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var loop_mode: int = loop_result.ok
	if loop_mode == Animation.LOOP_LINEAR:
		return ErrorCodes.make(
			ErrorCodes.VALUE_OUT_OF_RANGE,
			(
				"float ends at a net offset from its start, so loop_mode 'linear' would "
				+ "snap the target back each cycle — use 'pingpong' or 'none'"
			),
		)

	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved: Dictionary = _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true

	var target_resolved := _resolve_preset_target(player, target_path)
	if target_resolved.has("error"):
		return target_resolved
	## Untyped: `transform` lives on Node3D, not on the Node base.
	var target = target_resolved.node
	var kind: String = target_resolved.kind
	var track_target: String = target_resolved.track_path_root
	if kind != "3d":
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"float bobs a Node3D through its transform; use 'pulse' or 'drift' for Control/2D targets")

	if anim_name.is_empty():
		anim_name = "float"

	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var old_anim: Animation = existing.old_anim

	var baseline: Transform3D = target.transform
	var keyframes := build_float_keys(baseline, height, scale_factor, turns, duration)
	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = loop_mode
	_add_property_track(anim, "%s:transform" % track_target, keyframes)

	_commit_animation_add(
		"MCP: Create animation %s" % anim_name,
		player, library, created_library, anim_name, anim, old_anim,
	)

	return {
		"data": {
			"player_path": player_path,
			"animation_name": anim_name,
			"height": height,
			"scale": scale_factor,
			"turns": turns,
			"length": duration,
			"loop_mode": ValueCodec.loop_mode_to_string(loop_mode),
			"keyframe_count": keyframes.size(),
			"track_count": anim.get_track_count(),
			"library_created": created_library,
			"overwritten": old_anim != null,
			"undoable": true,
		}
	}


# ============================================================================
# animation_presets stagger — reveal a list of targets in one clip
# ============================================================================

## Cap on targets per stagger call: one track each, built in a single frame.
const _STAGGER_MAX_TARGETS := 64

## Reveal many targets one after another in a single clip: one track per target,
## key times offset by `stagger`. Effects start from each target's baseline
## (fade_in: modulate:a 0 -> 1; slide_in: position offset -> baseline;
## pop_in: scale 0.6x -> baseline). One undo action; loop_mode is "none".
func preset_stagger(params: Dictionary) -> Dictionary:
	var player_path: String = params.get("player_path", "")
	var use_selection: bool = params.get("use_selection", false)
	var effect: String = params.get("effect", "fade_in")
	var stagger: float = float(params.get("stagger", 0.06))
	var duration: float = float(params.get("duration", 0.3))
	var direction: String = params.get("direction", "left")
	var distance_param = params.get("distance", null)
	var anim_name: String = params.get("animation_name", "")
	var overwrite: bool = params.get("overwrite", false)

	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if not ["fade_in", "slide_in", "pop_in"].has(effect):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid effect '%s'. Valid: fade_in, slide_in, pop_in" % effect)
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if stagger < 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'stagger' must be >= 0")
	if effect == "slide_in" and not ["left", "right", "up", "down"].has(direction):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid direction '%s'. Valid: left, right, up, down" % direction)

	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved: Dictionary = _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true

	var collected := _stagger_target_paths(player, params, use_selection)
	if collected.has("error"):
		return collected
	var target_paths: Array = collected.paths
	## Refuse a malformed list before any per-target work (a duplicate would
	## otherwise surface as whatever error the first target hits).
	var seen := {}
	for path in target_paths:
		if seen.has(path):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Duplicate stagger target '%s' — each target gets one track" % path)
		seen[path] = true

	if anim_name.is_empty():
		anim_name = "stagger"

	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var old_anim: Animation = existing.old_anim

	var anim := Animation.new()
	anim.length = stagger_length(target_paths.size(), stagger, duration)
	anim.loop_mode = Animation.LOOP_NONE

	for index in target_paths.size():
		var path: String = target_paths[index]
		var target_resolved := _resolve_preset_target(player, path)
		if target_resolved.has("error"):
			return target_resolved
		var built := _stagger_track(
			target_resolved.node, target_resolved.kind, target_resolved.track_path_root,
			effect, direction, distance_param, float(index) * stagger, duration,
		)
		if built.has("error"):
			return built
		_add_property_track(anim, built.track_path, built.keys)

	_commit_animation_add(
		"MCP: Create animation %s" % anim_name,
		player, library, created_library, anim_name, anim, old_anim,
	)

	return {
		"data": {
			"player_path": player_path,
			"animation_name": anim_name,
			"effect": effect,
			"target_count": target_paths.size(),
			"targets": target_paths,
			"stagger": stagger,
			"duration": duration,
			"length": anim.length,
			"track_count": anim.get_track_count(),
			"library_created": created_library,
			"overwritten": old_anim != null,
			"undoable": true,
		}
	}


## Ordered target paths for a stagger call: the explicit `target_paths` array,
## or the editor selection converted to root_node-relative paths.
func _stagger_target_paths(player: AnimationPlayer, params: Dictionary, use_selection: bool) -> Dictionary:
	if use_selection:
		var selected := EditorInterface.get_selection().get_selected_nodes()
		if selected.is_empty():
			return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
				"use_selection is true but nothing is selected in the editor")
		if selected.size() > _STAGGER_MAX_TARGETS:
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Too many selected nodes (%d); the limit is %d" % [selected.size(), _STAGGER_MAX_TARGETS])
		var root_node := ValueCodec.player_root_node(player)
		if root_node == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"AnimationPlayer at %s has no resolvable root_node (is the scene open?)" % str(player.get_path()))
		var selected_paths: Array = []
		for node in selected:
			if not node.is_inside_tree():
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"Selected node '%s' is not in the edited scene" % node.name)
			selected_paths.append(str(root_node.get_path_to(node)))
		return {"paths": selected_paths}

	var raw = params.get("target_paths", [])
	if typeof(raw) != TYPE_ARRAY or raw.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"Missing required param: target_paths (ordered list), or pass use_selection=true")
	if raw.size() > _STAGGER_MAX_TARGETS:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Too many targets (%d); the limit is %d" % [raw.size(), _STAGGER_MAX_TARGETS])
	var paths: Array = []
	for entry in raw:
		if typeof(entry) != TYPE_STRING or (entry as String).is_empty():
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"target_paths entries must be non-empty strings (got %s)" % type_string(typeof(entry)))
		paths.append(entry)
	return {"paths": paths}


## One track spec for a stagger target: {track_path, keys} or an error dict.
## `target` is untyped because `position`/`scale`/`modulate` live on subclasses.
func _stagger_track(
	target, kind: String, track_target: String, effect: String,
	direction: String, distance_param: Variant, start_time: float, duration: float,
) -> Dictionary:
	var end_time := start_time + duration
	match effect:
		"fade_in":
			if not target is CanvasItem:
				return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
					"fade_in needs a CanvasItem/Control target (got %s)" % target.get_class())
			var current_alpha: float = (target as CanvasItem).modulate.a
			return {
				"track_path": "%s:modulate:a" % track_target,
				"keys": [
					{"time": start_time, "value": 0.0, "transition": "ease_out"},
					{"time": end_time, "value": current_alpha, "transition": "linear"},
				],
			}
		"slide_in":
			var default_distance: float = 1.0 if kind == "3d" else 100.0
			var distance: float = float(distance_param) if distance_param != null else default_distance
			if distance == 0.0:
				return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'distance' must be non-zero")
			var offset: Variant = _direction_offset(kind, direction, distance)
			var baseline: Variant = target.position
			return {
				"track_path": "%s:position" % track_target,
				"keys": [
					{"time": start_time, "value": baseline + offset, "transition": "ease_out"},
					{"time": end_time, "value": baseline, "transition": "linear"},
				],
			}
		"pop_in":
			var baseline_scale: Variant = target.scale
			var start_scale: Variant
			if kind == "3d":
				start_scale = baseline_scale * Vector3(0.6, 0.6, 0.6)
			else:
				start_scale = baseline_scale * Vector2(0.6, 0.6)
			return {
				"track_path": "%s:scale" % track_target,
				"keys": [
					{"time": start_time, "value": start_scale, "transition": "ease_out"},
					{"time": end_time, "value": baseline_scale, "transition": "linear"},
				],
			}
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "Unknown effect '%s'" % effect)


## Build a directional offset for slide effects.
## Axis conventions:
##   Control + Node2D (screen-space, y-down): left/right = ∓x, up = -y, down = +y
##   Node3D (world-up): left/right = ∓x, up = +y, down = -y
static func _direction_offset(kind: String, direction: String, distance: float) -> Variant:
	if kind == "3d":
		match direction:
			"left": return Vector3(-distance, 0.0, 0.0)
			"right": return Vector3(distance, 0.0, 0.0)
			"up": return Vector3(0.0, distance, 0.0)
			"down": return Vector3(0.0, -distance, 0.0)
	else:
		match direction:
			"left": return Vector2(-distance, 0.0)
			"right": return Vector2(distance, 0.0)
			"up": return Vector2(0.0, -distance)
			"down": return Vector2(0.0, distance)
	return null


# ============================================================================
# Helpers — keyframe builders (shared by the presets and the showcase)
# ============================================================================

## Three keys: rest -> peak (midpoint) -> rest.
static func build_pulse_keys(from_vec: Variant, to_vec: Variant, duration: float) -> Array:
	return [
		{"time": 0.0, "value": from_vec, "transition": "linear"},
		{"time": duration * 0.5, "value": to_vec, "transition": "linear"},
		{"time": duration, "value": from_vec, "transition": "linear"},
	]


## Four keys: rest -> overshoot -> dip -> rest, from the target's baseline.
static func build_bounce_keys(at_rest: Variant, kind: String, intensity: float, duration: float) -> Array:
	var peak := 1.0 + intensity
	var dip := 1.0 - intensity * 0.25
	var at_peak: Variant
	var at_dip: Variant
	if kind == "3d":
		at_peak = at_rest * Vector3(peak, peak, peak)
		at_dip = at_rest * Vector3(dip, dip, dip)
	else:
		at_peak = at_rest * Vector2(peak, peak)
		at_dip = at_rest * Vector2(dip, dip)
	return [
		{"time": 0.0, "value": at_rest, "transition": "linear"},
		{"time": duration * 0.35, "value": at_peak, "transition": "ease_out"},
		{"time": duration * 0.65, "value": at_dip, "transition": "ease_in_out"},
		{"time": duration, "value": at_rest, "transition": "linear"},
	]


## Seamless circle: `_ORBIT_SEGMENTS` linear segments (chord error under ~2%).
static func build_orbit_keys(
	center: Variant, kind: String, radius: float, clockwise: bool, duration: float
) -> Array:
	var direction := 1.0 if clockwise else -1.0
	var keyframes: Array = []
	for step in range(_ORBIT_SEGMENTS + 1):
		var angle := direction * TAU * float(step) / float(_ORBIT_SEGMENTS)
		var offset: Variant
		if kind == "3d":
			offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		else:
			offset = Vector2(cos(angle) * radius, sin(angle) * radius)
		keyframes.append({
			"time": duration * float(step) / float(_ORBIT_SEGMENTS),
			"value": center + offset,
			"transition": "linear",
		})
	return keyframes


## Two keys: current rotation -> current rotation + turns * TAU.
static func build_sweep_keys(start_rotation: float, turns: float, clockwise: bool, duration: float) -> Array:
	var direction := 1.0 if clockwise else -1.0
	var total_radians := direction * TAU * turns
	return [
		{"time": 0.0, "value": start_rotation, "transition": "linear"},
		{"time": duration, "value": start_rotation + total_radians, "transition": "linear"},
	]


## Two keys: current position -> current position + one-axis offset.
static func build_drift_keys(start_pos: Variant, offset: Variant, duration: float) -> Array:
	return [
		{"time": 0.0, "value": start_pos, "transition": "linear"},
		{"time": duration, "value": start_pos + offset, "transition": "linear"},
	]


## Quarter-turn quaternion keys around local Y (3D spin).
static func build_spin_keys(turns: float, clockwise: bool, duration: float) -> Array:
	var direction := 1.0 if clockwise else -1.0
	var steps := maxi(4, int(round(turns * 4.0)))
	var keyframes: Array = []
	for step in range(steps + 1):
		var angle := direction * TAU * float(step) / float(steps)
		keyframes.append({
			"time": duration * float(step) / float(steps),
			"value": Quaternion(Vector3.UP, angle),
			"transition": "linear",
		})
	return keyframes


## Two Transform3D keys: baseline -> raised by `height`, scaled by
## `scale_factor` and turned `turns` full turns about local Y.
static func build_float_keys(
	baseline: Transform3D, height: float, scale_factor: float, turns: float, duration: float
) -> Array:
	var raised := Transform3D(
		Basis(Vector3.UP, turns * TAU)
			* baseline.basis.scaled(Vector3(scale_factor, scale_factor, scale_factor)),
		baseline.origin + Vector3.UP * height,
	)
	return [
		{"time": 0.0, "value": baseline, "transition": "linear"},
		{"time": duration, "value": raised, "transition": "linear"},
	]


## Per-index `[start, end]` key times for a stagger clip.
static func stagger_key_times(count: int, stagger: float, duration: float) -> Array:
	var times: Array = []
	for index in count:
		var start := float(index) * stagger
		times.append([start, start + duration])
	return times


## Total clip length for a stagger reveal of `count` targets.
static func stagger_length(count: int, stagger: float, duration: float) -> float:
	if count <= 0:
		return 0.0
	return float(count - 1) * stagger + duration
