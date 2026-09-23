@tool
extends "res://addons/godot_ai_animation/handlers/animation_tool_base.gd"

## In-place clip editing — the `animation_edit` tool.
##
## Every op loads the clip into a spec, transforms it with the pure modifiers,
## rebuilds an Animation, and swaps it in as ONE scene-pinned undo action. Clips
## the toolkit cannot represent (bezier / blend-shape / animation tracks) and
## compressed tracks are refused up front instead of being silently rewritten.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const SpecModifiers := preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")
const QualityModifiers := preload("res://addons/godot_ai_animation/spec/quality_modifiers.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const _LOOP_MODES := {
	"none": Animation.LOOP_NONE,
	"linear": Animation.LOOP_LINEAR,
	"pingpong": Animation.LOOP_PINGPONG,
}

const _INTERP_MODES := {
	"linear": Animation.INTERPOLATION_LINEAR,
	"nearest": Animation.INTERPOLATION_NEAREST,
	"cubic": Animation.INTERPOLATION_CUBIC,
}

const _RETARGET_MODES := ["node", "prefix", "exact"]
const _KEY_ACTIONS := ["add", "set", "remove", "move"]


## Rollup entry registered with the Godot AI tool registry.
func run(params: Dictionary, _ctx) -> Dictionary:
	_dry_run = bool(params.get("dry_run", false))
	var result := _dispatch(params)
	if _dry_run and result.has("data"):
		result.data["dry_run"] = true
		result.data["undoable"] = false
	return result


func _dispatch(params: Dictionary) -> Dictionary:
	var op: String = params.get("op", "")
	match op:
		"retime":
			return edit_retime(params)
		"retarget":
			return edit_retarget(params)
		"reverse":
			return edit_reverse(params)
		"mirror":
			return edit_mirror(params)
		"offset":
			return edit_offset(params)
		"ease_range":
			return edit_ease_range(params)
		"set_interp":
			return edit_set_interp(params)
		"trim":
			return edit_trim(params)
		"split_at":
			return edit_split_at(params)
		"merge":
			return edit_merge(params)
		"amplitude":
			return edit_amplitude(params)
		"loop":
			return edit_loop(params)
		"key_edit":
			return edit_key_edit(params)
		"cleanup":
			return edit_cleanup(params)
		"smooth":
			return edit_smooth(params)
		"resample":
			return edit_resample(params)
		"add_noise":
			return edit_add_noise(params)
		"overlap":
			return edit_overlap(params)
		"layer":
			return edit_layer(params)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
		"Unknown op '%s'. Valid: %s" % [op, ", ".join(OpRegistry.op_names(OpRegistry.FAMILY_EDIT))])


# ============================================================================
# Ops
# ============================================================================

## Scale the clip's timeline by `factor` or to `length`.
func edit_retime(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var factor := float(params.get("factor", 0.0))
	var target_length := float(params.get("length", 0.0))
	if factor <= 0.0 and target_length <= 0.0:
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"retime needs 'factor' (> 0) or 'length' (> 0)")
	if factor < 0.0 or target_length < 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'factor' and 'length' must be > 0")
	if target_length > 0.0 and float(loaded.spec.length) <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Cannot retime to a length: the clip is empty (length 0)")
	var keys_only := bool(params.get("keys_only", false))
	var out := SpecModifiers.retime(loaded.spec, factor, target_length, keys_only)
	var extra := {"keys_only": keys_only}
	if factor > 0.0:
		extra["factor"] = factor
	return _commit_edited(loaded, out, "MCP: Retime animation %s" % loaded.anim_name, extra)


## Rewrite track paths (single remap or a batch of `paths`).
func edit_retarget(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var remaps: Array = []
	if params.has("paths"):
		var raw_paths = params.get("paths")
		if not raw_paths is Array or (raw_paths as Array).is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'paths' must be a non-empty array of {from, to, mode}")
		remaps = raw_paths
	else:
		var from_path := str(params.get("from_path", ""))
		var to_path := str(params.get("to_path", ""))
		if from_path.is_empty() or to_path.is_empty():
			return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
				"retarget needs 'from_path' and 'to_path' (or a 'paths' array)")
		remaps = [{"from": from_path, "to": to_path, "mode": str(params.get("mode", "node"))}]
	for remap in remaps:
		var mode := str(remap.get("mode", "node"))
		if not _RETARGET_MODES.has(mode):
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Invalid retarget mode '%s'. Valid: %s" % [mode, ", ".join(_RETARGET_MODES)])
	var result := SpecModifiers.retarget(loaded.spec, remaps)
	if int(result.changed) == 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"No track path matched the retarget remaps. Tracks: %s" % _track_list(loaded.spec))
	return _commit_edited(loaded, result.spec, "MCP: Retarget animation %s" % loaded.anim_name, {
		"changed_tracks": int(result.changed),
	})


## Play the clip backwards.
func edit_reverse(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var out := SpecModifiers.reverse(loaded.spec)
	return _commit_edited(loaded, out, "MCP: Reverse animation %s" % loaded.anim_name, {})


## Mirror position/rotation (and optionally scale) across a plane.
func edit_mirror(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var axes := str(params.get("axis", "x")).to_lower()
	if axes.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "mirror needs 'axis' (e.g. \"x\" or \"xy\")")
	for i in axes.length():
		if not "xyz".contains(axes[i]):
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Invalid mirror axis '%s'. Use any of x, y, z (e.g. \"x\", \"xy\")" % axes)
	var pivot = _coerce_pivot(params.get("pivot"))
	if params.has("pivot") and pivot == null:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "'pivot' must be {x,y}, {x,y,z}, or an array")
	var include_scale := bool(params.get("include_scale", false))
	var result := SpecModifiers.mirror(loaded.spec, axes, pivot, include_scale)
	if int(result.changed) == 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Nothing to mirror: no position/rotation keys on axis '%s'. Tracks: %s" % [axes, _track_list(loaded.spec)])
	return _commit_edited(loaded, result.spec, "MCP: Mirror animation %s" % loaded.anim_name, {
		"changed_keys": int(result.changed),
		"axis": axes,
	})


## Shift every key in time.
func edit_offset(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	if not params.has("delta"):
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "offset needs 'delta' (seconds)")
	var delta := float(params.get("delta", 0.0))
	var wrap := bool(params.get("wrap", false))
	if wrap and float(loaded.spec.length) <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "Cannot wrap an empty clip (length 0)")
	var out := SpecModifiers.offset(loaded.spec, delta, wrap)
	return _commit_edited(loaded, out, "MCP: Offset animation %s" % loaded.anim_name, {
		"delta": delta,
		"wrap": wrap,
	})


## Set per-key transitions inside a time range.
func edit_ease_range(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var length := float(loaded.spec.length)
	var from := float(params.get("from", 0.0))
	var to := float(params.get("to", length))
	if from < 0.0 or to < from:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"'from' must be >= 0 and <= 'to' (got %s..%s)" % [from, to])
	var transition := ValueCodec.parse_transition(params.get("transition", "linear"))
	var result := SpecModifiers.ease_range(loaded.spec, from, to, transition)
	if int(result.changed) == 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"No keys between %s and %s. Clip length is %s" % [from, to, length])
	return _commit_edited(loaded, result.spec, "MCP: Ease animation %s" % loaded.anim_name, {
		"changed_keys": int(result.changed),
		"transition": ValueCodec.parse_transition(params.get("transition", "linear")),
	})


## Set track-level interpolation.
func edit_set_interp(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var mode := str(params.get("interpolation", ""))
	if not _INTERP_MODES.has(mode):
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"set_interp needs 'interpolation': %s" % ", ".join(_INTERP_MODES.keys()))
	var track_path := str(params.get("track_path", ""))
	if not track_path.is_empty() and ClipSpec.find_track_index(loaded.spec, track_path) < 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"No track '%s'. Tracks: %s" % [track_path, _track_list(loaded.spec)])
	if mode == "cubic":
		for track in loaded.spec.tracks:
			if not track_path.is_empty() and str(track.path) != track_path:
				continue
			if int(track.type) == Animation.TYPE_VALUE:
				return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
					"'cubic' is only supported for position/rotation/scale 3D tracks (track '%s' is a value track)" % str(track.path))
	var result := SpecModifiers.set_interp(loaded.spec, _INTERP_MODES[mode], track_path)
	if int(result.changed) == 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"No value tracks matched. Tracks: %s" % _track_list(loaded.spec))
	return _commit_edited(loaded, result.spec, "MCP: Set interpolation on %s" % loaded.anim_name, {
		"interpolation": mode,
		"changed_tracks": int(result.changed),
	})


## Keep only a time range, shifted to 0.
func edit_trim(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var length := float(loaded.spec.length)
	var from := float(params.get("from", 0.0))
	var to := minf(float(params.get("to", length)), length)
	if from < 0.0 or to <= from:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"'from' must be >= 0 and < 'to' (got %s..%s, clip length %s)" % [from, to, length])
	var keep_bounds := bool(params.get("keep_bounds", true))
	var out := SpecModifiers.trim(loaded.spec, from, to, keep_bounds)
	if (out.tracks as Array).is_empty():
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Trimming %s..%s would leave no keys" % [from, to])
	return _commit_edited(loaded, out, "MCP: Trim animation %s" % loaded.anim_name, {
		"from": from,
		"to": to,
		"keep_bounds": keep_bounds,
	})


## Cut one clip into two at a time.
func edit_split_at(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	if not params.has("time"):
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "split_at needs 'time' (seconds)")
	var time := float(params.get("time", 0.0))
	var length := float(loaded.spec.length)
	if time <= 0.0 or time >= length:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"'time' must be inside the clip (0 < time < %s, got %s)" % [length, time])
	var head_name := str(params.get("head_name", ""))
	if head_name.is_empty():
		head_name = "%s_a" % loaded.anim_name
	if head_name == loaded.anim_name:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'head_name' must differ from 'animation_name'")
	var overwrite := bool(params.get("overwrite", false))
	var existing := _existing_animation(loaded.library, head_name, overwrite)
	if existing.has("error"):
		return existing.error
	var parts := SpecModifiers.split(loaded.spec, time)
	var head_anim := SpecBuilder.to_animation(parts.head)
	var tail_anim := SpecBuilder.to_animation(parts.tail)
	var removed := {loaded.anim_name: loaded.anim}
	var added := {loaded.anim_name: tail_anim, head_name: head_anim}
	_commit_animation_changes("MCP: Split animation %s" % loaded.anim_name,
		loaded.player, loaded.library, false, removed, added)
	var data := _base_data(loaded, parts.tail, {
		"head_name": head_name,
		"tail_name": loaded.anim_name,
		"time": time,
	})
	data["head_length"] = float(parts.head.length)
	data["tail_length"] = float(parts.tail.length)
	data["keys_before"] = ClipSpec.total_key_count(loaded.spec)
	data["keys_after"] = ClipSpec.total_key_count(parts.head) + ClipSpec.total_key_count(parts.tail)
	return {"data": data}


## Concatenate clips into one.
func edit_merge(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved := _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	if library == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"AnimationPlayer at %s has no default animation library" % player_path)
	var sources = params.get("sources")
	if not sources is Array or (sources as Array).is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"merge needs 'sources': a non-empty array of {animation_name, player_path?}")
	var specs: Array = []
	var source_names: Array = []
	for i in (sources as Array).size():
		var raw_source = sources[i]
		if not raw_source is Dictionary:
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"sources[%d] must be an object like {\"animation_name\": \"walk\"}" % i)
		var source: Dictionary = raw_source
		var source_name := str(source.get("animation_name", ""))
		if source_name.is_empty():
			return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
				"sources[%d] is missing 'animation_name'" % i)
		var source_player: AnimationPlayer = player
		var source_library: AnimationLibrary = library
		var source_player_path := str(source.get("player_path", player_path))
		if source_player_path != player_path:
			var source_resolved := _resolve_player(source_player_path)
			if source_resolved.has("error"):
				return source_resolved
			source_player = source_resolved.player
			source_library = source_resolved.library
			if source_library == null:
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"AnimationPlayer at %s has no default animation library" % source_player_path)
		if not source_library.has_animation(source_name):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Animation '%s' not found on %s. Available: %s"
				% [source_name, source_player_path, _available_names(source_library)])
		var source_anim := source_library.get_animation(source_name)
		var unsupported := SpecIO.unsupported_tracks(source_anim)
		if not unsupported.is_empty():
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"Animation '%s' has tracks this toolkit cannot edit: %s"
				% [source_name, SpecIO.describe_unsupported(source_anim)])
		specs.append(SpecIO.from_animation(source_anim))
		source_names.append(source_name)
	var anim_name := str(params.get("animation_name", ""))
	var new_name := str(params.get("new_name", ""))
	if new_name.is_empty():
		if anim_name.is_empty():
			return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
				"merge needs 'new_name' (or 'animation_name' as the name base)")
		new_name = "%s_merged" % anim_name
	var overwrite := bool(params.get("overwrite", false))
	var existing := _existing_animation(library, new_name, overwrite)
	if existing.has("error"):
		return existing.error
	var gap := maxf(0.0, float(params.get("gap", 0.0)))
	var merged := SpecModifiers.merge(specs, gap)
	var merged_anim := SpecBuilder.to_animation(merged)
	var removed := {}
	if existing.old_anim != null:
		removed[new_name] = existing.old_anim
	_commit_animation_changes("MCP: Merge animation %s" % new_name,
		player, library, false, removed, {new_name: merged_anim})
	return {"data": {
		"player_path": player_path,
		"animation_name": new_name,
		"new_name": new_name,
		"sources": source_names,
		"gap": gap,
		"length": float(merged.length),
		"loop_mode": ValueCodec.loop_mode_to_string(int(merged.loop_mode)),
		"track_count": (merged.tracks as Array).size(),
		"key_count": ClipSpec.total_key_count(merged),
		"overwritten": existing.old_anim != null,
		"undoable": true,
	}}


## Scale key deltas about a baseline.
func edit_amplitude(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	if not params.has("factor"):
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "amplitude needs 'factor'")
	var factor := float(params.get("factor", 1.0))
	var has_baseline := params.has("baseline")
	var baseline = _coerce_baseline(loaded, params.get("baseline")) if has_baseline else null
	if has_baseline and baseline == null:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"'baseline' must be a number or {x,y[,z]} matching the clip's values")
	var out := SpecModifiers.amplitude(loaded.spec, factor, baseline, has_baseline)
	return _commit_edited(loaded, out, "MCP: Scale amplitude of %s" % loaded.anim_name, {
		"factor": factor,
		"baseline": ValueCodec.serialize(baseline) if has_baseline else null,
	})


## Set the loop mode (optionally making a linear loop seamless).
func edit_loop(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var mode := str(params.get("loop_mode", ""))
	if not _LOOP_MODES.has(mode):
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"loop needs 'loop_mode': %s" % ", ".join(_LOOP_MODES.keys()))
	var make_seamless := bool(params.get("make_seamless", false))
	if make_seamless and float(loaded.spec.length) <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "Cannot make an empty clip (length 0) seamless")
	var out := SpecModifiers.set_loop(loaded.spec, _LOOP_MODES[mode], make_seamless)
	return _commit_edited(loaded, out, "MCP: Set loop mode on %s" % loaded.anim_name, {
		"loop_mode": mode,
		"make_seamless": make_seamless,
	})


## Add / set / remove / move one key.
func edit_key_edit(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var action := str(params.get("action", ""))
	if not _KEY_ACTIONS.has(action):
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"key_edit needs 'action': %s" % ", ".join(_KEY_ACTIONS))
	var track_index := _resolve_track_index(loaded, params)
	if track_index < 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"No track matched. Pass 'track_path' (e.g. \"Sprite:position\") or 'track_index'. Tracks: %s"
			% _track_list(loaded.spec))
	if not params.has("time"):
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "key_edit needs 'time' (seconds)")
	var time := float(params.get("time", 0.0))
	var tolerance := float(params.get("tolerance", 0.001))
	if tolerance <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'tolerance' must be > 0")
	var track: Dictionary = loaded.spec.tracks[track_index]
	var transition := ValueCodec.parse_transition(params.get("transition", "linear"))
	var value: Variant = null
	if action == "add" or action == "set":
		if not params.has("value"):
			return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
				"key_edit '%s' needs 'value'" % action)
		var coerced := _coerce_key_value(loaded, track, params.get("value"))
		if coerced.has("error"):
			return coerced
		value = coerced.ok
	var new_time := float(params.get("new_time", time))
	var result := SpecModifiers.key_edit(
		loaded.spec, track_index, action, time, value, transition, new_time, tolerance,
	)
	if int(result.key_index) < 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"No key within %s s of %s on track '%s'" % [tolerance, time, str(track.path)])
	return _commit_edited(loaded, result.spec, "MCP: Edit key on %s" % loaded.anim_name, {
		"action": action,
		"track_path": str(track.path),
		"track_index": track_index,
		"key_index": int(result.key_index),
		"time": time,
		"new_time": new_time if action == "move" else time,
	})


## Drop redundant keys and empty tracks.
func edit_cleanup(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var tolerance := float(params.get("tolerance", 0.0001))
	var min_gap := float(params.get("min_gap", 0.0))
	if tolerance < 0.0 or min_gap < 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'tolerance' and 'min_gap' must be >= 0")
	var drop_empty := bool(params.get("drop_empty_tracks", true))
	var result := SpecModifiers.cleanup(loaded.spec, tolerance, min_gap, drop_empty)
	if (result.spec.tracks as Array).is_empty():
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Cleanup would remove every track (all keys were duplicates). Use min_gap=0 / tolerance=0 to keep more.")
	return _commit_edited(loaded, result.spec, "MCP: Cleanup animation %s" % loaded.anim_name, {
		"removed_keys": int(result.removed),
		"min_gap": min_gap,
	})


## Soften key values toward their neighbours: follow-through cleanup for noisy
## captures. `strength` 0-1, `passes` >= 1, optional `track_path`.
func edit_smooth(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var strength := float(params.get("strength", 0.5))
	if strength <= 0.0 or strength > 1.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'strength' must be in (0, 1]")
	var passes := int(params.get("passes", 1))
	if passes < 1 or passes > 50:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'passes' must be 1-50")
	var track_path := str(params.get("track_path", ""))
	var result := QualityModifiers.smooth(loaded.spec, strength, passes, track_path)
	if int(result.changed) == 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Nothing to smooth: need value tracks with 3+ keys (matched %d)" % int(result.changed))
	return _commit_edited(loaded, result.spec, "MCP: Smooth %s" % loaded.anim_name, {
		"strength": strength,
		"passes": passes,
		"track_path": track_path,
		"smoothed_keys": int(result.changed),
	})


## Rebuild value tracks at a fixed sample rate using the engine's own
## interpolator, so transitions and cubic keys survive densifying.
func edit_resample(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var fps := float(params.get("fps", 30.0))
	if fps <= 0.0 or fps > 120.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'fps' must be in (0, 120]")
	var interp_name := str(params.get("interpolation", "linear"))
	if not _INTERP_MODES.has(interp_name):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid interpolation '%s'. Valid: %s" % [interp_name, ", ".join(_INTERP_MODES.keys())])
	var track_path := str(params.get("track_path", ""))
	var result := QualityModifiers.resample(loaded.spec, fps, _INTERP_MODES[interp_name], track_path)
	if int(result.changed) == 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "Nothing to resample: no value tracks matched")
	return _commit_edited(loaded, result.spec, "MCP: Resample %s" % loaded.anim_name, {
		"fps": fps,
		"interpolation": interp_name,
		"track_path": track_path,
		"resampled_keys": int(result.changed),
	})


## Add seeded, smooth micro-motion to value keys (breathing, tremor, life).
func edit_add_noise(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var amount := float(params.get("amount", 2.0))
	if amount <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'amount' must be > 0")
	var frequency := float(params.get("frequency", 3.0))
	if frequency <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'frequency' must be > 0")
	var seed_value := int(params.get("seed", 0))
	var track_path := str(params.get("track_path", ""))
	var result := QualityModifiers.add_noise(loaded.spec, amount, frequency, seed_value, track_path)
	if int(result.changed) == 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "Nothing to animate: no value keys matched")
	return _commit_edited(loaded, result.spec, "MCP: Add noise to %s" % loaded.anim_name, {
		"amount": amount,
		"frequency": frequency,
		"seed": seed_value,
		"track_path": track_path,
		"noised_keys": int(result.changed),
	})


## Delay one limb/prop subtree by `delay` seconds - instant follow-through.
func edit_overlap(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var track_path := str(params.get("track_path", ""))
	if track_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "overlap needs 'track_path'")
	var delay := float(params.get("delay", 0.0))
	if is_zero_approx(delay):
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "overlap needs 'delay' (seconds, non-zero)")
	var wrap := bool(params.get("wrap", false))
	var result := QualityModifiers.overlap(loaded.spec, track_path, delay, wrap)
	if int(result.changed) == 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"No tracks match '%s'. Pass an exact track path, a node path, or a subtree prefix." % track_path)
	return _commit_edited(loaded, result.spec, "MCP: Overlap %s" % loaded.anim_name, {
		"track_path": track_path,
		"delay": delay,
		"wrap": wrap,
		"shifted_keys": int(result.changed),
	})


## Combine another clip onto this one: "mix" blends toward the source, "add"
## layers its delta from its first key (breathing/jiggle onto a base).
func edit_layer(params: Dictionary) -> Dictionary:
	var loaded := _load_clip(params)
	if loaded.has("error"):
		return loaded
	var source_name := str(params.get("source_animation", ""))
	if source_name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "layer needs 'source_animation'")
	var layer_mode := str(params.get("layer_mode", "mix"))
	if layer_mode != "add" and layer_mode != "mix":
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid layer_mode '%s'. Valid: add, mix" % layer_mode)
	var weight := clampf(float(params.get("weight", 1.0)), 0.0, 1.0)
	var remap_node := str(params.get("remap_node", ""))
	var overlay_anim: Animation = null
	var source_player_path := str(params.get("source_player_path", ""))
	if source_player_path.is_empty() or source_player_path == str(loaded.player_path):
		if not loaded.library.has_animation(source_name):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Animation '%s' not found on %s. Available: %s"
				% [source_name, str(loaded.player_path), _available_names(loaded.library)])
		overlay_anim = loaded.library.get_animation(source_name)
	else:
		var resolved_source := _resolve_player(source_player_path)
		if resolved_source.has("error"):
			return resolved_source
		var source_library: AnimationLibrary = resolved_source.library
		if source_library == null or not source_library.has_animation(source_name):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Animation '%s' not found on %s" % [source_name, source_player_path])
		overlay_anim = source_library.get_animation(source_name)
	var unsupported := SpecIO.unsupported_tracks(overlay_anim)
	if not unsupported.is_empty():
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Source animation '%s' has tracks this toolkit cannot layer: %s"
			% [source_name, SpecIO.describe_unsupported(overlay_anim)])
	var result := QualityModifiers.layer(
		loaded.spec, SpecIO.from_animation(overlay_anim), weight, layer_mode, remap_node)
	if int(result.changed) == 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "The source clip has no value tracks to layer")
	return _commit_edited(loaded, result.spec, "MCP: Layer %s" % loaded.anim_name, {
		"source_animation": source_name,
		"source_player_path": source_player_path,
		"layer_mode": layer_mode,
		"weight": weight,
		"remap_node": remap_node,
		"layered_keys": int(result.changed),
		"tracks_created": int(result.tracks_created),
	})


# ============================================================================
# Helpers
# ============================================================================

## Resolve player + library + clip + spec, refusing clips the spec cannot
## represent. Returns `{player, library, anim_name, anim, spec}` or `{error}`.
func _load_clip(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	var anim_name := str(params.get("animation_name", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if anim_name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: animation_name")
	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved := _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	if library == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"AnimationPlayer at %s has no default animation library" % player_path)
	if not library.has_animation(anim_name):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Animation '%s' not found on %s. Available: %s"
			% [anim_name, player_path, _available_names(library)])
	var anim := library.get_animation(anim_name)
	var unsupported := SpecIO.unsupported_tracks(anim)
	if not unsupported.is_empty():
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Animation '%s' has tracks this toolkit cannot edit: %s. Edit them in the Godot animation editor."
			% [anim_name, SpecIO.describe_unsupported(anim)])
	var compressed := SpecIO.compressed_tracks(anim)
	if not compressed.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Animation '%s' has compressed tracks (%s). Compressed clips cannot be edited losslessly."
			% [anim_name, ", ".join(compressed)])
	return {
		"player": player,
		"player_path": player_path,
		"library": library,
		"anim_name": anim_name,
		"anim": anim,
		"spec": SpecIO.from_animation(anim),
	}


## Rebuild `spec` and swap it in for the loaded clip as one undo action.
func _commit_edited(loaded: Dictionary, spec: Dictionary, action_label: String, extra: Dictionary) -> Dictionary:
	var valid := SpecBuilder.validate(spec)
	if valid.has("error"):
		return valid
	var new_anim := SpecBuilder.to_animation(spec)
	_commit_animation_changes(action_label, loaded.player, loaded.library, false,
		{loaded.anim_name: loaded.anim}, {loaded.anim_name: new_anim})
	var data := _base_data(loaded, spec, extra)
	data["keys_before"] = ClipSpec.total_key_count(loaded.spec)
	data["keys_after"] = ClipSpec.total_key_count(spec)
	data["length_before"] = float(loaded.spec.length)
	data["length_after"] = float(spec.length)
	data["overwritten"] = true
	return {"data": data}


func _base_data(loaded: Dictionary, spec: Dictionary, extra: Dictionary) -> Dictionary:
	var data := {
		"player_path": str(loaded.get("player_path", "")),
		"animation_name": str(loaded.anim_name),
		"length": float(spec.length),
		"loop_mode": ValueCodec.loop_mode_to_string(int(spec.loop_mode)),
		"track_count": (spec.tracks as Array).size(),
		"key_count": ClipSpec.total_key_count(spec),
		"undoable": true,
	}
	data.merge(extra, true)
	return data


func _available_names(library: AnimationLibrary) -> String:
	var names: Array = []
	for name in library.get_animation_list():
		names.append(str(name))
	names.sort()
	return ", ".join(names) if not names.is_empty() else "(none)"


func _track_list(spec: Dictionary) -> String:
	var parts: Array = []
	for track in spec.get("tracks", []):
		parts.append(ClipSpec.track_label(track))
	return "; ".join(parts) if not parts.is_empty() else "(no tracks)"


func _resolve_track_index(loaded: Dictionary, params: Dictionary) -> int:
	if params.has("track_index"):
		var index := int(params.get("track_index", -1))
		if index >= 0 and index < (loaded.spec.tracks as Array).size():
			return index
		return -1
	var track_path := str(params.get("track_path", ""))
	if track_path.is_empty():
		return -1
	return ClipSpec.find_track_index(loaded.spec, track_path)


func _coerce_pivot(raw: Variant) -> Variant:
	if raw == null:
		return null
	if raw is Vector2 or raw is Vector3:
		return raw
	if raw is Array:
		var arr: Array = raw
		if arr.size() == 2:
			return Vector2(float(arr[0]), float(arr[1]))
		if arr.size() == 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		return null
	if raw is Dictionary:
		var dict: Dictionary = raw
		if dict.has("x") and dict.has("y") and dict.has("z"):
			return Vector3(float(dict.x), float(dict.y), float(dict.z))
		if dict.has("x") and dict.has("y"):
			return Vector2(float(dict.x), float(dict.y))
	return null


## Coerce a JSON value to the type the track stores: the target property's real
## type when the track's node resolves, else the first key's type.
func _coerce_key_value(loaded: Dictionary, track: Dictionary, raw: Variant) -> Dictionary:
	if int(track.get("type", -1)) == Animation.TYPE_METHOD:
		return {"ok": str(raw)}
	var root_node := ValueCodec.player_root_node(loaded.player)
	var node: Node = null
	if root_node != null:
		node = root_node.get_node_or_null(NodePath(str(track.path)))
	var property := ClipSpec.property_of(str(track.path))
	if node != null and not property.is_empty():
		var coerced := ValueCodec.coerce_for_property(raw, node, property)
		if not coerced.has("error"):
			return coerced
	var keys: Array = track.get("keys", [])
	if keys.is_empty():
		return {"ok": raw}
	var existing: Variant = keys[0].get("value")
	match ClipSpec.value_kind(existing):
		"float":
			if raw is int or raw is float:
				return {"ok": float(raw)}
		"vector2":
			var v2 := _coerce_pivot(raw)
			if v2 is Vector2:
				return {"ok": v2}
		"vector3":
			var v3 := _coerce_pivot(raw)
			if v3 is Vector3:
				return {"ok": v3}
			if v3 is Vector2:
				return {"ok": Vector3(v3.x, v3.y, 0.0)}
	return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
		"'value' does not match the track's type (%s) and the target property could not be resolved"
		% ClipSpec.value_kind(existing))


func _coerce_baseline(loaded: Dictionary, raw: Variant) -> Variant:
	if raw is int or raw is float:
		return float(raw)
	var pivot := _coerce_pivot(raw)
	return pivot
