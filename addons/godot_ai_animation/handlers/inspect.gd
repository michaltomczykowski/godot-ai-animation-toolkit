@tool
extends "res://addons/godot_ai_animation/handlers/animation_tool_base.gd"

## Read-only inspection — the `animation_inspect` tool.
##
## Nothing here mutates the scene or the undo stack, so an agent can reason about
## a project's animation state (and dry-run any generate/edit call) before
## touching it. Findings carry a `fix` hint naming the op that resolves them.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const GenerateHandler := preload("res://addons/godot_ai_animation/handlers/generate.gd")
const EditHandler := preload("res://addons/godot_ai_animation/handlers/edit.gd")

const _SEVERITIES := ["all", "error", "warning", "info"]
const _CONSTANT_TOLERANCE := 0.0001

## Godot clamps Animation.length to 0.001, so anything at or below that is empty.
const _MIN_LENGTH := 0.0011


## Rollup entry registered with the Godot AI tool registry.
func run(params: Dictionary, _ctx) -> Dictionary:
	var op: String = params.get("op", "")
	match op:
		"describe":
			return inspect_describe(params)
		"timeline":
			return inspect_timeline(params)
		"audit":
			return inspect_audit(params)
		"compare":
			return inspect_compare(params)
		"stats":
			return inspect_stats(params)
		"dry_run":
			return inspect_dry_run(params)
		"help":
			return inspect_help(params)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
		"Unknown op '%s'. Valid: %s" % [op, ", ".join(OpRegistry.op_names(OpRegistry.FAMILY_INSPECT))])


# ============================================================================
# describe
# ============================================================================

## Human-readable summary of one clip, or of every clip on a player.
func inspect_describe(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	var resolved := _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var max_tracks := maxi(1, int(params.get("max_tracks", 64)))
	var anim_name := str(params.get("animation_name", ""))
	var clips: Array = []
	if anim_name.is_empty():
		clips = _clips_of(player)
		if clips.is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"AnimationPlayer at %s has no clips" % player_path)
	else:
		var found := _find_clip(player, anim_name)
		if found.has("error"):
			return found
		clips = [found]
	var out: Array = []
	for entry in clips:
		out.append(_describe_clip(player, entry, max_tracks))
	return {"data": {
		"player_path": player_path,
		"clip_count": out.size(),
		"clips": out,
	}}


func _describe_clip(player: AnimationPlayer, entry: Dictionary, max_tracks: int) -> Dictionary:
	var anim: Animation = entry.anim
	var tracks: Array = []
	var key_total := 0
	var broken := 0
	for index in anim.get_track_count():
		var type := anim.track_get_type(index)
		var count := anim.track_get_key_count(index)
		key_total += count
		if tracks.size() >= max_tracks:
			continue
		var track := {
			"path": str(anim.track_get_path(index)),
			"type": ClipSpec.type_name(type),
			"keys": count,
			"enabled": anim.track_is_enabled(index),
			"node_resolved": _track_node(player, str(anim.track_get_path(index))) != null,
		}
		if not track.node_resolved:
			broken += 1
		if count > 0:
			track["first_time"] = anim.track_get_key_time(index, 0)
			track["last_time"] = anim.track_get_key_time(index, count - 1)
			if ClipSpec.is_value_type(type):
				track["first_value"] = ValueCodec.serialize(anim.track_get_key_value(index, 0))
				track["last_value"] = ValueCodec.serialize(anim.track_get_key_value(index, count - 1))
		tracks.append(track)
	var summary := "%s: %d track%s, %d key%s, %.2fs, loop %s" % [
		str(entry.name),
		anim.get_track_count(), "" if anim.get_track_count() == 1 else "s",
		key_total, "" if key_total == 1 else "s",
		anim.length, ValueCodec.loop_mode_to_string(anim.loop_mode),
	]
	if str(player.autoplay) == str(entry.name):
		summary += ", autoplay"
	if broken > 0:
		summary += ", %d broken track path%s" % [broken, "" if broken == 1 else "s"]
	return {
		"name": str(entry.name),
		"library": str(entry.get("library_name", "")),
		"length": anim.length,
		"loop_mode": ValueCodec.loop_mode_to_string(anim.loop_mode),
		"track_count": anim.get_track_count(),
		"key_count": key_total,
		"autoplay": str(player.autoplay) == str(entry.name),
		"summary": summary,
		"tracks": tracks,
		"tracks_truncated": anim.get_track_count() > tracks.size(),
	}


# ============================================================================
# timeline
# ============================================================================

## Machine-readable key table for one clip.
func inspect_timeline(params: Dictionary) -> Dictionary:
	var loaded := _load_readable_clip(params)
	if loaded.has("error"):
		return loaded
	var anim: Animation = loaded.anim
	var track_filter := str(params.get("track_path", ""))
	var include_values := bool(params.get("include_values", true))
	var max_keys := maxi(1, int(params.get("max_keys", 200)))
	var tracks: Array = []
	var key_total := 0
	var returned := 0
	var truncated := false
	for index in anim.get_track_count():
		var type := anim.track_get_type(index)
		var path := str(anim.track_get_path(index))
		if not track_filter.is_empty() and path != track_filter:
			continue
		var count := anim.track_get_key_count(index)
		key_total += count
		var keys: Array = []
		for key_index in count:
			if returned >= max_keys:
				truncated = true
				break
			returned += 1
			var key := {"time": anim.track_get_key_time(index, key_index)}
			match type:
				Animation.TYPE_METHOD:
					key["method"] = String(anim.method_track_get_name(index, key_index))
					key["args"] = anim.method_track_get_params(index, key_index)
				Animation.TYPE_AUDIO:
					key["stream"] = _resource_label(anim.audio_track_get_key_stream(index, key_index))
					key["start_offset"] = anim.audio_track_get_key_start_offset(index, key_index)
					key["end_offset"] = anim.audio_track_get_key_end_offset(index, key_index)
				_:
					if include_values:
						key["value"] = ValueCodec.serialize(anim.track_get_key_value(index, key_index))
					if type == Animation.TYPE_VALUE:
						key["transition"] = anim.track_get_key_transition(index, key_index)
			keys.append(key)
		tracks.append({
			"path": path,
			"type": ClipSpec.type_name(type),
			"interp": _interp_label(anim.track_get_interpolation_type(index)),
			"key_count": count,
			"keys": keys,
		})
		if truncated:
			break
	if tracks.is_empty():
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"No track matched '%s'. Tracks: %s" % [track_filter, _track_list(anim)])
	return {"data": {
		"player_path": loaded.player_path,
		"animation_name": loaded.anim_name,
		"length": anim.length,
		"loop_mode": ValueCodec.loop_mode_to_string(anim.loop_mode),
		"track_count": tracks.size(),
		"key_count": key_total,
		"returned_keys": returned,
		"truncated": truncated,
		"tracks": tracks,
	}}


# ============================================================================
# audit
# ============================================================================

## Scene- or player-wide animation health check.
func inspect_audit(params: Dictionary) -> Dictionary:
	var severity := str(params.get("severity", "all"))
	if not _SEVERITIES.has(severity):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid severity '%s'. Valid: %s" % [severity, ", ".join(_SEVERITIES)])
	var include_info := bool(params.get("include_info", true))
	var player_path := str(params.get("player_path", ""))
	var players: Array = []
	if player_path.is_empty():
		players = _scene_players()
		if players.is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"No AnimationPlayer found in the edited scene")
	else:
		var resolved := _resolve_player(player_path)
		if resolved.has("error"):
			return resolved
		players = [resolved.player]
	var scene_root := EditorInterface.get_edited_scene_root()
	var findings: Array = []
	var clips_scanned := 0
	var autoplay_paths := {}
	for player in players:
		var player_label := ValueCodec.from_node(player, scene_root)
		var autoplay := str(player.autoplay)
		var clips := _clips_of(player)
		var clip_names: Array = []
		for entry in clips:
			clip_names.append(str(entry.name))
		if not autoplay.is_empty() and not clip_names.has(autoplay):
			findings.append(_finding("error", "autoplay_missing", player_label, autoplay, "",
				"autoplay names a clip that does not exist on this player",
				"clear autoplay or create the clip"))
		var tree_refs := _tree_animation_refs(player)
		var autoplay_entry := _find_clip(player, autoplay) if not autoplay.is_empty() else {}
		for entry in clips:
			clips_scanned += 1
			_audit_clip(player, player_label, entry, tree_refs, autoplay, findings)
		if not autoplay_entry.is_empty() and not autoplay_entry.has("error"):
			var autoplay_anim: Animation = autoplay_entry.anim
			for index in autoplay_anim.get_track_count():
				var path := str(autoplay_anim.track_get_path(index))
				if not autoplay_paths.has(path):
					autoplay_paths[path] = []
				if not (autoplay_paths[path] as Array).has(player_label):
					autoplay_paths[path].append(player_label)
	for path in autoplay_paths:
		var owners: Array = autoplay_paths[path]
		if owners.size() < 2:
			continue
		findings.append(_finding("warning", "autoplay_conflict", ", ".join(owners), "", str(path),
			"%d autoplaying players write the same track path" % owners.size(),
			"keep one of them autoplaying, or scope the players to different nodes"))
	var filtered: Array = []
	for finding in findings:
		if severity != "all" and str(finding.severity) != severity:
			continue
		if not include_info and str(finding.severity) == "info":
			continue
		filtered.append(finding)
	filtered.sort_custom(func(a, b):
		if int(a.severity_rank) != int(b.severity_rank):
			return int(a.severity_rank) < int(b.severity_rank)
		if str(a.player_path) != str(b.player_path):
			return str(a.player_path) < str(b.player_path)
		if str(a.animation_name) != str(b.animation_name):
			return str(a.animation_name) < str(b.animation_name)
		return str(a.track_path) < str(b.track_path))
	var counts := {"error": 0, "warning": 0, "info": 0}
	for finding in filtered:
		counts[str(finding.severity)] += 1
	return {"data": {
		"players_scanned": players.size(),
		"clips_scanned": clips_scanned,
		"finding_count": filtered.size(),
		"summary": counts,
		"findings": filtered,
	}}


func _audit_clip(
	player: AnimationPlayer, player_label: String, entry: Dictionary,
	tree_refs: Dictionary, autoplay: String, findings: Array,
) -> void:
	var anim: Animation = entry.anim
	var clip_name := str(entry.name)
	if anim.length <= _MIN_LENGTH:
		findings.append(_finding("error", "zero_length", player_label, clip_name, "",
			"the clip has no length (%.4fs) and will not play" % anim.length,
			"rebuild the clip with a duration"))
	if clip_name != autoplay and not tree_refs.has(clip_name):
		findings.append(_finding("info", "unused_clip", player_label, clip_name, "",
			"no autoplay and no AnimationTree node references this clip",
			"info only - the clip may be played from script"))
	for index in anim.get_track_count():
		var type := anim.track_get_type(index)
		var path := str(anim.track_get_path(index))
		var count := anim.track_get_key_count(index)
		if anim.track_is_compressed(index):
			findings.append(_finding("warning", "compressed_track", player_label, clip_name, path,
				"the track is compressed; edit ops refuse it",
				"re-save the clip uncompressed to edit it"))
		if count == 0:
			findings.append(_finding("warning", "no_keys", player_label, clip_name, path,
				"the track has no keys", "remove the track or add keys"))
			continue
		if _track_node(player, path) == null:
			findings.append(_finding("error", "broken_path", player_label, clip_name, path,
				"the track path does not resolve against the player's root node",
				"animation_edit retarget (mode=node or prefix) to point it at an existing node"))
		if count == 1:
			findings.append(_finding("info", "single_key", player_label, clip_name, path,
				"a single key holds a constant value",
				"info only - cleanup can drop redundant keys"))
		for key_index in count - 1:
			if is_equal_approx(anim.track_get_key_time(index, key_index), anim.track_get_key_time(index, key_index + 1)):
				findings.append(_finding("warning", "duplicate_keys", player_label, clip_name, path,
					"two keys share the same time (%.3fs)" % anim.track_get_key_time(index, key_index),
					"animation_edit key_edit remove to drop one"))
				break
		if not ClipSpec.is_value_type(type):
			continue
		var first: Variant = anim.track_get_key_value(index, 0)
		var constant := count > 1
		for key_index in count:
			if not ClipSpec.values_equal(anim.track_get_key_value(index, key_index), first, _CONSTANT_TOLERANCE):
				constant = false
				break
		if constant:
			findings.append(_finding("info", "constant_track", player_label, clip_name, path,
				"every key holds the same value",
				"info only - cleanup can drop redundant keys"))
		if anim.loop_mode == Animation.LOOP_LINEAR and count > 1:
			var last: Variant = anim.track_get_key_value(index, count - 1)
			if not ClipSpec.values_equal(first, last, _CONSTANT_TOLERANCE):
				findings.append(_finding("warning", "loop_snap", player_label, clip_name, path,
					"a linear loop starts and ends on different values, so it pops at the seam",
					"animation_edit loop with make_seamless=true"))


# ============================================================================
# compare
# ============================================================================

## Diff two clips (same player by default).
func inspect_compare(params: Dictionary) -> Dictionary:
	var first := _load_readable_clip(params)
	if first.has("error"):
		return first
	var other_name := str(params.get("other_animation_name", ""))
	if other_name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "compare needs 'other_animation_name'")
	var other_player_path := str(params.get("other_player_path", first.player_path))
	var other_resolved := _resolve_player(other_player_path)
	if other_resolved.has("error"):
		return other_resolved
	var other_player: AnimationPlayer = other_resolved.player
	var other := _find_clip(other_player, other_name)
	if other.has("error"):
		return other
	var tolerance := maxf(0.0, float(params.get("tolerance", 0.0001)))
	var max_keys := maxi(1, int(params.get("max_keys", 200)))
	var anim: Animation = first.anim
	var other_anim: Animation = other.anim
	var only_first: Array = []
	var only_other: Array = []
	var changed: Array = []
	var same: Array = []
	for index in anim.get_track_count():
		var path := str(anim.track_get_path(index))
		var type := anim.track_get_type(index)
		var other_index := other_anim.find_track(NodePath(path), type)
		if other_index < 0:
			only_first.append("%s [%s]" % [path, ClipSpec.type_name(type)])
			continue
		var diff := _compare_tracks(anim, index, other_anim, other_index, tolerance, max_keys)
		if diff.changed_keys == 0 and diff.key_count_a == diff.key_count_b:
			same.append(path)
		else:
			diff["path"] = path
			diff["type"] = ClipSpec.type_name(type)
			changed.append(diff)
	for index in other_anim.get_track_count():
		var path := str(other_anim.track_get_path(index))
		var type := other_anim.track_get_type(index)
		if anim.find_track(NodePath(path), type) < 0:
			only_other.append("%s [%s]" % [path, ClipSpec.type_name(type)])
	var identical := (
		only_first.is_empty() and only_other.is_empty() and changed.is_empty()
		and is_equal_approx(anim.length, other_anim.length)
		and anim.loop_mode == other_anim.loop_mode
	)
	return {"data": {
		"player_path": first.player_path,
		"animation_name": first.anim_name,
		"other_player_path": other_player_path,
		"other_animation_name": other_name,
		"identical": identical,
		"length": {"a": anim.length, "b": other_anim.length, "delta": other_anim.length - anim.length},
		"loop_mode": {
			"a": ValueCodec.loop_mode_to_string(anim.loop_mode),
			"b": ValueCodec.loop_mode_to_string(other_anim.loop_mode),
		},
		"track_count": {"a": anim.get_track_count(), "b": other_anim.get_track_count()},
		"key_count": {
			"a": _key_count(anim), "b": _key_count(other_anim),
		},
		"only_a": only_first,
		"only_b": only_other,
		"changed_tracks": changed,
		"same_tracks": same,
	}}


func _compare_tracks(
	anim: Animation, index: int, other: Animation, other_index: int,
	tolerance: float, max_keys: int,
) -> Dictionary:
	var count_a := anim.track_get_key_count(index)
	var count_b := other.track_get_key_count(other_index)
	var changed_keys := 0
	var max_delta := 0.0
	var pairs := mini(count_a, count_b)
	for key_index in pairs:
		if key_index >= max_keys:
			break
		if not is_equal_approx(anim.track_get_key_time(index, key_index), other.track_get_key_time(other_index, key_index)):
			changed_keys += 1
			continue
		var type := anim.track_get_type(index)
		if not ClipSpec.is_value_type(type):
			if String(anim.method_track_get_name(index, key_index)) != String(other.method_track_get_name(other_index, key_index)):
				changed_keys += 1
			continue
		var a: Variant = anim.track_get_key_value(index, key_index)
		var b: Variant = other.track_get_key_value(other_index, key_index)
		if ClipSpec.values_equal(a, b, tolerance):
			continue
		changed_keys += 1
		max_delta = maxf(max_delta, _value_delta(a, b))
	return {
		"key_count_a": count_a,
		"key_count_b": count_b,
		"changed_keys": changed_keys + absi(count_a - count_b),
		"max_delta": max_delta,
	}


func _value_delta(a: Variant, b: Variant) -> float:
	if typeof(a) != typeof(b):
		return 0.0
	match typeof(a):
		TYPE_FLOAT, TYPE_INT:
			return absf(float(a) - float(b))
		TYPE_VECTOR2:
			return (a as Vector2).distance_to(b as Vector2)
		TYPE_VECTOR3:
			return (a as Vector3).distance_to(b as Vector3)
		TYPE_QUATERNION:
			return (a as Quaternion).angle_to(b as Quaternion)
	return 0.0


# ============================================================================
# stats
# ============================================================================

## Quick numbers for a player (or the whole scene).
func inspect_stats(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	var players: Array = []
	if player_path.is_empty():
		players = _scene_players()
		if players.is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"No AnimationPlayer found in the edited scene")
	else:
		var resolved := _resolve_player(player_path)
		if resolved.has("error"):
			return resolved
		players = [resolved.player]
	var scene_root := EditorInterface.get_edited_scene_root()
	var per_player: Array = []
	var totals := {"clip_count": 0, "track_count": 0, "key_count": 0, "total_length": 0.0}
	var type_histogram := {}
	var loop_histogram := {"none": 0, "linear": 0, "pingpong": 0}
	for player in players:
		var clips: Array = []
		var player_length := 0.0
		var player_keys := 0
		var player_tracks := 0
		var longest := ""
		var shortest := ""
		var longest_length := -1.0
		var shortest_length := INF
		for entry in _clips_of(player):
			var anim: Animation = entry.anim
			var keys := _key_count(anim)
			clips.append({
				"name": str(entry.name),
				"length": anim.length,
				"track_count": anim.get_track_count(),
				"key_count": keys,
				"loop_mode": ValueCodec.loop_mode_to_string(anim.loop_mode),
			})
			player_length += anim.length
			player_keys += keys
			player_tracks += anim.get_track_count()
			loop_histogram[ValueCodec.loop_mode_to_string(anim.loop_mode)] += 1
			if anim.length > longest_length:
				longest_length = anim.length
				longest = str(entry.name)
			if anim.length < shortest_length:
				shortest_length = anim.length
				shortest = str(entry.name)
			for index in anim.get_track_count():
				var label := ClipSpec.type_name(anim.track_get_type(index))
				type_histogram[label] = int(type_histogram.get(label, 0)) + 1
		clips.sort_custom(func(a, b): return str(a.name) < str(b.name))
		per_player.append({
			"player_path": ValueCodec.from_node(player, scene_root),
			"autoplay": str(player.autoplay),
			"clip_count": clips.size(),
			"track_count": player_tracks,
			"key_count": player_keys,
			"total_length": player_length,
			"longest": longest,
			"shortest": shortest,
			"clips": clips,
		})
		totals.clip_count += clips.size()
		totals.track_count += player_tracks
		totals.key_count += player_keys
		totals.total_length += player_length
	return {"data": {
		"player_count": players.size(),
		"totals": totals,
		"track_types": type_histogram,
		"loop_modes": loop_histogram,
		"players": per_player,
	}}


# ============================================================================
# dry_run
# ============================================================================

## Run any generate/edit op without committing: returns what it would produce.
func inspect_dry_run(params: Dictionary) -> Dictionary:
	var tool := str(params.get("tool", OpRegistry.FAMILY_EDIT))
	if OpRegistry.family(tool).is_empty():
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Unknown tool '%s'. Valid: %s" % [tool, ", ".join(OpRegistry.family_names())])
	var forward_op := str(params.get("forward_op", ""))
	if forward_op.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"dry_run needs 'forward_op': the %s op to run" % tool)
	var forwarded := params.duplicate(true)
	forwarded.erase("tool")
	forwarded.erase("forward_op")
	forwarded["op"] = forward_op
	forwarded["dry_run"] = true
	var handler
	if tool == OpRegistry.FAMILY_PRESETS:
		handler = GenerateHandler.new()
	elif tool == OpRegistry.FAMILY_EDIT:
		handler = EditHandler.new()
	else:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"dry_run supports %s and %s (inspect ops are already read-only)"
			% [OpRegistry.FAMILY_PRESETS, OpRegistry.FAMILY_EDIT])
	var result: Dictionary = handler.run(forwarded, null)
	if result.has("data"):
		result.data["dry_run"] = true
		result.data["tool"] = tool
		result.data["undoable"] = false
	return result


# ============================================================================
# help
# ============================================================================

## Op index from the registry: names, summaries, params and examples.
func inspect_help(params: Dictionary) -> Dictionary:
	var tool := str(params.get("tool", ""))
	var op := str(params.get("op_name", ""))
	if not tool.is_empty() and OpRegistry.family(tool).is_empty():
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Unknown tool '%s'. Valid: %s" % [tool, ", ".join(OpRegistry.family_names())])
	var family_names: Array = [tool] if not tool.is_empty() else OpRegistry.family_names()
	var tools: Array = []
	for family_name in family_names:
		var info: Dictionary = OpRegistry.family(family_name)
		var ops: Array = []
		var known: Array = []
		for descriptor in info.get("ops", []):
			known.append(str(descriptor.name))
			if not op.is_empty() and str(descriptor.name) != op:
				continue
			ops.append({
				"name": str(descriptor.name),
				"summary": str(descriptor.get("summary", "")),
				"params": descriptor.get("params", []),
				"example": descriptor.get("example", {}),
			})
		if not op.is_empty() and ops.is_empty():
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Unknown op '%s' for %s. Valid: %s" % [op, family_name, ", ".join(known)])
		tools.append({
			"tool": family_name,
			"summary": str(info.get("summary", "")),
			"description": str(info.get("description", "")),
			"required": info.get("schema", {}).get("required", []),
			"ops": ops,
		})
	return {"data": {"tool_count": tools.size(), "tools": tools}}


# ============================================================================
# Helpers
# ============================================================================

## Read-only clip resolution for timeline/compare: player + clip + raw Animation
## (unsupported track types are fine here, unlike the edit ops).
func _load_readable_clip(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	var anim_name := str(params.get("animation_name", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	if anim_name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: animation_name")
	var resolved := _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var found := _find_clip(player, anim_name)
	if found.has("error"):
		return found
	return {
		"player": player,
		"player_path": player_path,
		"anim_name": anim_name,
		"library": found.library,
		"anim": found.anim,
	}


## Every clip on a player, across all its animation libraries.
func _clips_of(player: AnimationPlayer) -> Array:
	var clips: Array = []
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		if library == null:
			continue
		for clip_name in library.get_animation_list():
			clips.append({
				"name": str(clip_name),
				"library": str(library_name),
				"anim": library.get_animation(clip_name),
			})
	return clips


## Find one clip by name across every library. Returns `{library, anim, name}`.
func _find_clip(player: AnimationPlayer, anim_name: String) -> Dictionary:
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		if library == null or not library.has_animation(anim_name):
			continue
		return {
			"name": anim_name,
			"library": library,
			"library_name": str(library_name),
			"anim": library.get_animation(anim_name),
		}
	if anim_name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: animation_name")
	var names: Array = []
	for entry in _clips_of(player):
		names.append(str(entry.name))
	names.sort()
	return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
		"Animation '%s' not found. Available: %s"
		% [anim_name, ", ".join(names) if not names.is_empty() else "(none)"])


func _scene_players() -> Array:
	var players: Array = []
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return players
	_collect_players(scene_root, players)
	return players


func _collect_players(node: Node, out: Array) -> void:
	if node is AnimationPlayer:
		out.append(node)
	for child in node.get_children():
		_collect_players(child, out)


## The node a track path targets, or null when the path is broken.
func _track_node(player: AnimationPlayer, track_path: String) -> Node:
	var root := ValueCodec.player_root_node(player)
	if root == null:
		return null
	return root.get_node_or_null(NodePath(ClipSpec.node_path_of(track_path)))


## Clip names referenced by AnimationTree nodes under `player`'s parent.
func _tree_animation_refs(player: AnimationPlayer) -> Dictionary:
	var refs := {}
	var search_root: Node = player.get_parent()
	if search_root == null:
		return refs
	for tree in search_root.find_children("*", "AnimationTree", true, false):
		_collect_tree_refs((tree as AnimationTree).tree_root, refs)
	return refs


func _collect_tree_refs(node: AnimationNode, refs: Dictionary) -> void:
	if node == null:
		return
	if node is AnimationNodeAnimation:
		refs[str((node as AnimationNodeAnimation).animation)] = true
	for index in node.get_child_count():
		_collect_tree_refs(node.get_child(index), refs)


func _finding(
	severity: String, code: String, player_path: String, animation_name: String,
	track_path: String, message: String, fix: String,
) -> Dictionary:
	var ranks := {"error": 0, "warning": 1, "info": 2}
	return {
		"severity": severity,
		"severity_rank": int(ranks.get(severity, 3)),
		"code": code,
		"player_path": player_path,
		"animation_name": animation_name,
		"track_path": track_path,
		"message": message,
		"fix": fix,
	}


func _key_count(anim: Animation) -> int:
	var count := 0
	for index in anim.get_track_count():
		count += anim.track_get_key_count(index)
	return count


func _interp_label(interp: int) -> String:
	match interp:
		Animation.INTERPOLATION_NEAREST:
			return "nearest"
		Animation.INTERPOLATION_CUBIC:
			return "cubic"
	return "linear"


func _resource_label(resource: Resource) -> String:
	if resource == null:
		return ""
	if not resource.resource_path.is_empty():
		return str(resource.resource_path)
	return str(resource.get_class())


func _track_list(anim: Animation) -> String:
	var parts: Array = []
	for index in anim.get_track_count():
		parts.append("%s [%s]" % [
			str(anim.track_get_path(index)),
			ClipSpec.type_name(anim.track_get_type(index)),
		])
	return "; ".join(parts) if not parts.is_empty() else "(no tracks)"
