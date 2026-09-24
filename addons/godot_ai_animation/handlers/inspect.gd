@tool
extends "res://addons/godot_ai_animation/handlers/bone_animation.gd"

## Read-only inspection — the `animation_inspect` tool.
##
## Nothing here mutates the scene or the undo stack, so an agent can reason about
## a project's animation state (and dry-run any generate/edit call) before
## touching it. Findings carry a `fix` hint naming the op that resolves them.

const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const QualityModifiers := preload("res://addons/godot_ai_animation/spec/quality_modifiers.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const GenerateHandler := preload("res://addons/godot_ai_animation/handlers/generate.gd")
const FxHandler := preload("res://addons/godot_ai_animation/handlers/fx.gd")
const GraphHandler := preload("res://addons/godot_ai_animation/handlers/graph.gd")
const LibraryHandler := preload("res://addons/godot_ai_animation/handlers/library.gd")
const RigHandler := preload("res://addons/godot_ai_animation/handlers/rig.gd")
const MotionHandler := preload("res://addons/godot_ai_animation/handlers/motion.gd")
const EditHandler := preload("res://addons/godot_ai_animation/handlers/edit.gd")

const _SEVERITIES := ["all", "error", "warning", "info"]
const _CONSTANT_TOLERANCE := 0.0001

## Godot clamps Animation.length to 0.001, so anything at or below that is empty.
const _MIN_LENGTH := 0.0011

## Default FK sample count and cap, and how many bones the default role set holds.
const _SAMPLE_DEFAULT := 24
const _SAMPLE_CAP := 240
const _SAMPLE_MAX_BONES := 64


## Rollup entry registered with the Godot AI tool registry.
func run(params: Dictionary, ctx) -> Dictionary:
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
		"motion_report":
			return inspect_motion_report(params)
		"rig_profile":
			return inspect_rig_profile(params)
		"sample":
			return inspect_sample(params)
		"preview":
			return inspect_preview(params, ctx)
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
# motion_report
# ============================================================================

## Per-track motion quality: key density, peak speed/acceleration, loop-seam
## pops, hemisphere flips and constant tracks, each finding with a fix hint.
func inspect_motion_report(params: Dictionary) -> Dictionary:
	var loaded := _load_readable_clip(params)
	if loaded.has("error"):
		return loaded
	var unsupported := SpecIO.unsupported_tracks(loaded.anim)
	if not unsupported.is_empty():
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Animation '%s' has tracks this report cannot analyse: %s"
			% [loaded.anim_name, SpecIO.describe_unsupported(loaded.anim)])
	var max_tracks := int(params.get("max_tracks", 20))
	var report := QualityModifiers.motion_report(SpecIO.from_animation(loaded.anim), max_tracks)
	var data := {
		"player_path": str(loaded.player_path),
		"animation_name": str(loaded.anim_name),
		"length": loaded.anim.length,
		"loop_mode": ValueCodec.loop_mode_to_string(loaded.anim.loop_mode),
	}
	data.merge(report, true)
	return {"data": data}


# ============================================================================
# rig_profile
# ============================================================================

## Understand a rig without touching it: roles (with candidates), T/A pose,
## limb lengths/reach, facing and lateral axes, capabilities and suggested next
## ops. `save=true` writes a reusable profile that rig/motion ops accept through
## their `profile` param, so detection is never guessed twice.
func inspect_rig_profile(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	var skeleton3d: Skeleton3D = resolved.node if resolved.kind == "3d" else null
	var skeleton2d: Skeleton2D = resolved.node if resolved.kind == "2d" else null
	var bone_names: Array = []
	if skeleton3d != null:
		for index in skeleton3d.get_bone_count():
			bone_names.append(skeleton3d.get_bone_name(index))
	else:
		for index in skeleton2d.get_bone_count():
			bone_names.append(str(skeleton2d.get_bone(index).name))
	var detected := RigAnalysis.detect_roles(bone_names)
	var roles: Dictionary = (detected.roles as Dictionary).duplicate()
	var profile_roles := {}
	if params.get("profile") != null:
		var loaded_profile := _profile_roles(params.get("profile"), bone_names)
		if loaded_profile.has("error"):
			return loaded_profile.error
		profile_roles = loaded_profile.roles
		for role in profile_roles:
			roles[str(role)] = str(profile_roles[role])
	var explicit_roles := {}
	var overrides = params.get("roles", {})
	if overrides is Dictionary:
		for role in overrides:
			explicit_roles[str(role)] = str((overrides as Dictionary)[role])
			roles[str(role)] = str((overrides as Dictionary)[role])
	var pose := {"pose": "unknown", "arm_angle_degrees": 0.0, "per_side": {}}
	var axes := {}
	var limbs := {}
	var warnings: Array = []
	if skeleton3d != null:
		pose = RigAnalysis.arm_pose(_arm_rest_directions(skeleton3d, roles))
		axes = _rig_axes(skeleton3d, roles)
		limbs = _limb_metrics(skeleton3d, roles)
		var scale_factor := _skeleton_scale(skeleton3d)
		if absf(scale_factor - 1.0) > 0.001:
			warnings.append({"code": "scaled_skeleton", "severity": "warning",
				"message": "the Skeleton3D (or a parent) is scaled by %.3f; IK and spring bones assume unit scale" % scale_factor})
		var zero_bones: Array = limbs.get("zero_length_bones", [])
		if not zero_bones.is_empty():
			warnings.append({"code": "zero_length_bones", "severity": "warning",
				"message": "%d bone(s) share their parent's origin (zero length): %s" % [zero_bones.size(), ", ".join(zero_bones.slice(0, 6))]})
		if pose.pose == "T":
			warnings.append({"code": "t_pose", "severity": "info",
				"message": "the arms rest horizontally (T-pose); the motion cycles lower them by default - pass arm_down to tune"})
		if not roles.has("arm_l") or not roles.has("arm_r"):
			warnings.append({"code": "no_arms", "severity": "warning",
				"message": "no upper-arm bones were detected, so arm swing is skipped"})
	var capabilities := RigAnalysis.capabilities(roles, bone_names.size())
	var missing := RigAnalysis.missing_roles(roles)
	var saved := ""
	if bool(params.get("save", false)):
		var path := _profile_path(params, str(resolved.node.name))
		if path.has("error"):
			return path
		var profile := {
			"format": RigAnalysis.PROFILE_FORMAT,
			"version": RigAnalysis.PROFILE_VERSION,
			"name": str(path.name),
			"skeleton": str(resolved.node.name),
			"bone_count": bone_names.size(),
			"roles": roles,
			"missing": missing,
			"pose": pose,
			"axes": axes,
			"limbs": limbs,
			"capabilities": capabilities,
		}
		var written := _write_profile(str(path.path), profile, bool(params.get("overwrite", true)))
		if written.has("error"):
			return written
		saved = str(path.path)
	return {"data": {
		"skeleton_path": str(resolved.path),
		"kind": str(resolved.kind),
		"bone_count": bone_names.size(),
		"roles": roles,
		"auto_roles": detected.roles,
		"profile_roles": profile_roles,
		"explicit_roles": explicit_roles,
		"candidates": detected.candidates,
		"unmatched_bones": detected.unmatched,
		"missing": missing,
		"pose": pose,
		"axes": axes,
		"limbs": limbs,
		"capabilities": capabilities,
		"warnings": warnings,
		"suggested_ops": RigAnalysis.suggestions(roles, capabilities),
		"saved": saved,
		"undoable": false,
	}}


## Validate the profile file name and return `{path, name}`.
func _profile_path(params: Dictionary, fallback_name: String) -> Dictionary:
	var profile_name := str(params.get("name", "")).strip_edges()
	if profile_name.is_empty():
		profile_name = fallback_name.strip_edges()
	if profile_name.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Cannot derive a profile name; pass 'name'")
	if profile_name.contains("/") or profile_name.contains("\\") or profile_name.contains(":") or profile_name.contains("."):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"'name' must be a plain file name without separators or extension (got '%s')" % profile_name)
	return {"path": "%s/%s.json" % [RigAnalysis.PROFILE_DIR, profile_name], "name": profile_name}


func _write_profile(path: String, profile: Dictionary, overwrite: bool) -> Dictionary:
	if not overwrite and FileAccess.file_exists(path):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"%s already exists. Pass overwrite=true to replace it." % path)
	var directory := path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var made := DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Cannot create %s (%s)" % [directory, error_string(made)])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
	file.store_string(JSON.stringify(profile, "  "))
	file.close()
	return {"ok": true}


## Skeleton-space upper-arm rest direction per side (Godot bones point along +Y).
func _arm_rest_directions(skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	var out := {}
	for side in ["l", "r"]:
		var arm := str(roles.get("arm_" + side, ""))
		if arm.is_empty():
			continue
		var index := skeleton.find_bone(arm)
		if index < 0:
			continue
		out[side] = (skeleton.get_bone_global_rest(index).basis * Vector3.UP).normalized()
	return out


## Facing (ankle -> toe), lateral (right thigh -> left) and up axes, in skeleton
## space; the motion recipes derive their travel from the same vectors.
func _rig_axes(skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	var forward := _forward_dir(skeleton, roles)
	var lateral := Vector3.ZERO
	var left := str(roles.get("thigh_l", ""))
	var right := str(roles.get("thigh_r", ""))
	if not left.is_empty() and not right.is_empty():
		var left_index := skeleton.find_bone(left)
		var right_index := skeleton.find_bone(right)
		if left_index >= 0 and right_index >= 0:
			lateral = skeleton.get_bone_global_rest(left_index).origin \
				- skeleton.get_bone_global_rest(right_index).origin
	lateral.y = 0.0
	if lateral.length_squared() > 0.000001:
		lateral = lateral.normalized()
	else:
		lateral = forward.cross(Vector3.UP).normalized()
	return {
		"forward": ValueCodec.serialize(forward),
		"lateral": ValueCodec.serialize(lateral),
		"up": ValueCodec.serialize(Vector3.UP),
		"facing_source": "ankle_to_toe" if roles.has("foot_l") and roles.has("toe_l") else "default",
	}


## Limb segments, total lengths/reach and zero-length bones.
func _limb_metrics(skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	var out := {"legs": {}, "arms": {}, "zero_length_bones": []}
	var zero_bones: Array = out.zero_length_bones
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		if parent < 0:
			continue
		var origin := skeleton.get_bone_global_rest(index).origin
		var parent_origin := skeleton.get_bone_global_rest(parent).origin
		if origin.distance_to(parent_origin) < 0.0001:
			zero_bones.append(skeleton.get_bone_name(index))
	for side in ["l", "r"]:
		var thigh := str(roles.get("thigh_" + side, ""))
		var shin := str(roles.get("shin_" + side, ""))
		var foot := str(roles.get("foot_" + side, ""))
		if not thigh.is_empty() and not shin.is_empty():
			var upper := _rest_distance(skeleton, thigh, shin)
			var lower := _rest_distance(skeleton, shin, foot) if not foot.is_empty() else 0.0
			out.legs[side] = {
				"thigh": thigh, "shin": shin, "foot": foot,
				"upper": _round(upper), "lower": _round(lower), "total": _round(upper + lower),
			}
		var arm := str(roles.get("arm_" + side, ""))
		var forearm := str(roles.get("forearm_" + side, ""))
		var hand := str(roles.get("hand_" + side, ""))
		if not arm.is_empty():
			var upper_arm := _rest_distance(skeleton, arm, forearm) if not forearm.is_empty() else 0.0
			var lower_arm := _rest_distance(skeleton, forearm, hand) if not forearm.is_empty() and not hand.is_empty() else 0.0
			out.arms[side] = {
				"upper_arm": arm, "forearm": forearm, "hand": hand,
				"upper": _round(upper_arm), "lower": _round(lower_arm), "total": _round(upper_arm + lower_arm),
			}
	if not out.legs.is_empty():
		var leg_total := 0.0
		for side in out.legs:
			leg_total = maxf(leg_total, float(out.legs[side].total))
		out["leg_length"] = _round(leg_total)
		out["hip_height"] = 0.0
		var hips := str(roles.get("hips", ""))
		var hips_index := skeleton.find_bone(hips) if not hips.is_empty() else -1
		if hips_index >= 0:
			out["hip_height"] = _round(skeleton.get_bone_global_rest(hips_index).origin.y)
	if not out.arms.is_empty():
		var arm_total := 0.0
		for side in out.arms:
			arm_total = maxf(arm_total, float(out.arms[side].total))
		out["arm_length"] = _round(arm_total)
		out["reach"] = _round(arm_total)
	return out


static func _rest_distance(skeleton: Skeleton3D, from_bone: String, to_bone: String) -> float:
	var from_index := skeleton.find_bone(from_bone)
	var to_index := skeleton.find_bone(to_bone)
	if from_index < 0 or to_index < 0:
		return 0.0
	return skeleton.get_bone_global_rest(from_index).origin.distance_to(
		skeleton.get_bone_global_rest(to_index).origin)


# ============================================================================
# sample
# ============================================================================

## FK probe: apply the clip to the skeleton in memory and report world positions
## (and optional euler rotations) of requested bones at N times - plus derived
## foot heights and contact windows. The skeleton's pose is restored afterwards;
## nothing is committed.
func inspect_sample(params: Dictionary) -> Dictionary:
	var loaded := _load_readable_clip(params)
	if loaded.has("error"):
		return loaded
	var unsupported := SpecIO.unsupported_tracks(loaded.anim)
	if not unsupported.is_empty():
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Animation '%s' has tracks FK sampling cannot use: %s"
			% [loaded.anim_name, SpecIO.describe_unsupported(loaded.anim)])
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "sample probes a Skeleton3D (3D FK)")
	var skeleton: Skeleton3D = resolved.node
	var length: float = loaded.anim.length
	var times: Array = []
	if params.has("times"):
		var given = params.get("times", [])
		if not (given is Array) or (given as Array).is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'times' must be a non-empty array of seconds")
		times = RigAnalysis.explicit_times(given, length, _SAMPLE_CAP)
	else:
		times = RigAnalysis.sample_times(length, int(params.get("samples", _SAMPLE_DEFAULT)))
	var roles: Dictionary = _resolve_roles(params, skeleton)
	if roles.has("_error"):
		return roles["_error"]
	var requested := _requested_bones(params, skeleton, roles)
	var bone_names: Array = requested.names
	if bone_names.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"No requested bone exists on this skeleton. Bones: %s" % _bone_name_list(skeleton))
	var include_rotation := bool(params.get("include_rotation", false))
	var threshold := maxf(0.0, float(params.get("contact_threshold", 0.02)))
	var spec := SpecIO.from_animation(loaded.anim)
	var snapshot := _pose_snapshot(skeleton)
	var bone_data := {}
	for bone_name in bone_names:
		var entry := {"positions": []}
		if include_rotation:
			entry["euler_degrees"] = []
		bone_data[bone_name] = entry
	var feet := {}
	for side in ["l", "r"]:
		var foot := str(roles.get("foot_" + side, ""))
		if not foot.is_empty() and skeleton.find_bone(foot) >= 0:
			feet[side] = {"bone": foot, "heights": []}
	var skeleton_xform := skeleton.global_transform
	for time in times:
		_apply_spec_at(skeleton, spec, float(time))
		for bone_name in bone_names:
			var index := skeleton.find_bone(bone_name)
			if index < 0:
				continue
			var global := skeleton_xform * skeleton.get_bone_global_pose(index)
			bone_data[bone_name].positions.append(_vec_array(global.origin))
			if include_rotation:
				bone_data[bone_name].euler_degrees.append(_euler_degrees(global.basis))
		for side in feet:
			var foot_index := skeleton.find_bone(str(feet[side].bone))
			if foot_index >= 0:
				feet[side].heights.append(_round((skeleton_xform * skeleton.get_bone_global_pose(foot_index)).origin.y))
	_pose_restore(skeleton, snapshot)
	for side in feet:
		var heights: Array = feet[side].heights
		var lowest := INF
		var highest := -INF
		for height in heights:
			lowest = minf(lowest, float(height))
			highest = maxf(highest, float(height))
		feet[side]["min_height"] = _round(lowest) if not heights.is_empty() else 0.0
		feet[side]["height_range"] = _round(highest - lowest) if not heights.is_empty() else 0.0
		feet[side]["contacts"] = RigAnalysis.contact_windows(times, heights, threshold)
	return {"data": {
		"player_path": str(loaded.player_path),
		"animation_name": str(loaded.anim_name),
		"skeleton_path": str(resolved.path),
		"length": length,
		"sample_count": times.size(),
		"times": times,
		"bones": bone_data,
		"missing_bones": requested.missing,
		"bones_truncated": requested.truncated,
		"feet": feet,
		"contact_threshold": threshold,
		"undoable": false,
	}}


## Requested bones (`bones`, `["*"]` for every bone) or the detected role set.
func _requested_bones(params: Dictionary, skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	var raw = params.get("bones", [])
	var names: Array = []
	var missing: Array = []
	if raw is Array and not (raw as Array).is_empty():
		for value in raw:
			var bone_name := str(value)
			if bone_name == "*":
				names.clear()
				for index in skeleton.get_bone_count():
					names.append(skeleton.get_bone_name(index))
				break
			if skeleton.find_bone(bone_name) >= 0:
				names.append(bone_name)
			else:
				missing.append(bone_name)
	else:
		var wanted: Array = [] + RigAnalysis.CORE_ROLES + ["foot_l", "foot_r"] + RigAnalysis.OPTIONAL_ROLES
		for role in wanted:
			var bone_name := str(roles.get(role, ""))
			if not bone_name.is_empty() and not names.has(bone_name):
				names.append(bone_name)
	var truncated := names.size() > _SAMPLE_MAX_BONES
	return {
		"names": names.slice(0, _SAMPLE_MAX_BONES),
		"missing": missing,
		"truncated": truncated,
	}


func _bone_name_list(skeleton: Skeleton3D, limit := 24) -> String:
	var names: Array = []
	for index in mini(skeleton.get_bone_count(), limit):
		names.append(skeleton.get_bone_name(index))
	if skeleton.get_bone_count() > limit:
		names.append("...")
	return ", ".join(names) if not names.is_empty() else "(none)"


static func _vec_array(value: Vector3) -> Array:
	return [_round(value.x), _round(value.y), _round(value.z)]


static func _euler_degrees(basis: Basis) -> Array:
	var euler := basis.get_euler()
	return [_round(rad_to_deg(euler.x), 2), _round(rad_to_deg(euler.y), 2), _round(rad_to_deg(euler.z), 2)]


static func _round(value: float, digits := 4) -> float:
	var factor := pow(10.0, digits)
	return roundf(value * factor) / factor


# ============================================================================
# preview
# ============================================================================

## Render the posed character offscreen at one or more clip times and save PNGs,
## so an agent can *see* a clip (contact, foot planting, follow-through) instead
## of only reading key values.
##
## The edited scene is never touched: the character subtree is duplicated into a
## private SubViewport with its own world, posed from the clip, framed by a
## camera, and freed again.
##
## The renderer only rasterises a viewport once per editor frame, which a
## synchronous tool call cannot reach, so this op is deferred: it returns
## `{"_deferred": true}` and pushes the real payload after one frame per image.
## Headless servers cannot rasterise at all and say so immediately.
func inspect_preview(params: Dictionary, ctx) -> Dictionary:
	var loaded := _load_readable_clip(params)
	if loaded.has("error"):
		return loaded
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "preview renders a Skeleton3D")
	var skeleton: Skeleton3D = resolved.node
	var unsupported := SpecIO.unsupported_tracks(loaded.anim)
	if not unsupported.is_empty():
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Animation '%s' has tracks preview cannot pose: %s"
			% [loaded.anim_name, SpecIO.describe_unsupported(loaded.anim)])
	var length: float = loaded.anim.length
	var times: Array = []
	if params.has("times"):
		var given = params.get("times", [])
		if not (given is Array) or (given as Array).is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'times' must be a non-empty array of seconds")
		times = RigAnalysis.explicit_times(given, length, _SAMPLE_CAP)
	else:
		times = RigAnalysis.sample_times(length, int(params.get("samples", 4)))
	var width := clampi(int(params.get("width", 480)), 64, 2048)
	var height := clampi(int(params.get("height", 270)), 64, 2048)
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"preview needs a rendering device; headless editors cannot rasterise frames")
	if ctx == null or not ctx.has_method("send_deferred"):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"preview renders on later editor frames: call it through the Godot AI tool, not dry_run or batch_execute")
	var spec := SpecIO.from_animation(loaded.anim)
	var output_dir := str(params.get("output_dir", "res://animation_toolkit/previews"))
	var basename := str(params.get("basename", loaded.anim_name))
	var overwrite := bool(params.get("overwrite", true))
	var source := _preview_source(params, resolved)
	if source == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"preview could not find the character node to copy")
	var margin := float(params.get("margin", 1.35))
	# Frame every frame identically: union the posed bone bounds over all times
	# (the live skeleton is posed and restored, never left modified).
	var snapshot := _pose_snapshot(skeleton)
	var bounds := AABB()
	var first_bounds := true
	for time in times:
		_apply_spec_at(skeleton, spec, float(time))
		var posed := _preview_bounds(skeleton)
		bounds = posed if first_bounds else bounds.merge(posed)
		first_bounds = false
	_pose_restore(skeleton, snapshot)
	if first_bounds or (bounds.end - bounds.position).length() < 0.001:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "preview needs bones to frame the camera")
	var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"preview could not create %s (error %d)" % [output_dir, dir_error])
	_render_preview_frames({
		"source": source,
		"spec": spec,
		"times": times,
		"bounds": bounds,
		"margin": margin,
		"width": width,
		"height": height,
		"background": str(params.get("background", "#2b2f36")),
		"yaw": float(params.get("yaw", 28.0)),
		"elevation": float(params.get("elevation", 8.0)),
		"output_dir": output_dir,
		"basename": basename,
		"overwrite": overwrite,
		"player_path": str(loaded.player_path),
		"animation_name": str(loaded.anim_name),
		"skeleton_path": str(resolved.path),
		"length": length,
	}, ctx)
	return {"_deferred": true}


## One image per editor frame: pose, wait for the renderer, read back, save.
func _render_preview_frames(state: Dictionary, ctx) -> void:
	var paths: Array = []
	var times: Array = state.times
	for index in times.size():
		var time := float(times[index])
		var viewport := _build_preview_viewport(int(state.width), int(state.height), str(state.background))
		if viewport == null:
			ctx.send_deferred(ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"preview could not create a render viewport"))
			return
		var character := (state.source as Node3D).duplicate() as Node3D
		viewport.add_child(character)
		var posed_skeleton := _find_skeleton(character) as Skeleton3D
		if posed_skeleton == null:
			viewport.queue_free()
			ctx.send_deferred(ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"preview could not duplicate the skeleton"))
			return
		_apply_spec_at(posed_skeleton, state.spec, time)
		var camera := _build_preview_camera(viewport, float(state.yaw), float(state.elevation))
		_frame_preview_camera(camera, state.bounds as AABB, float(state.margin))
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			viewport.queue_free()
			ctx.send_deferred(ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"preview could not read back a frame at t=%s" % str(time)))
			return
		var path := "%s/%s_%02d.png" % [str(state.output_dir).trim_suffix("/"), str(state.basename), index]
		if FileAccess.file_exists(path) and not bool(state.overwrite):
			viewport.queue_free()
			ctx.send_deferred(ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"preview file already exists: %s (pass overwrite=true)" % path))
			return
		var error := image.save_png(path)
		viewport.queue_free()
		if error != OK:
			ctx.send_deferred(ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"preview could not write %s (error %d)" % [path, error]))
			return
		paths.append(path)
	ctx.send_deferred({"data": {
		"player_path": str(state.player_path),
		"animation_name": str(state.animation_name),
		"skeleton_path": str(state.skeleton_path),
		"length": _round(float(state.length)),
		"times": times,
		"paths": paths,
		"width": int(state.width),
		"height": int(state.height),
		"bounds_center": _vec_array((state.bounds as AABB).get_center()),
		"bounds_extent": _vec_array((state.bounds as AABB).end - (state.bounds as AABB).position),
		"undoable": false,
		"note": "each frame rendered a private copy of the character; the edited scene is unchanged",
	}})


## Private SubViewport with its own world, a neutral background and two lights.
## It is parented to the editor's root window so it is inside the tree (a
## viewport outside the tree never rasterises) and freed by the caller.
func _build_preview_viewport(width: int, height: int, background: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "AnimationToolkitPreview"
	viewport.size = Vector2i(width, height)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		viewport.free()
		return null
	loop.root.add_child(viewport)
	var world := Node3D.new()
	world.name = "PreviewWorld"
	viewport.add_child(world)
	var color := Color(background) if background.is_valid_html_color() else Color(0.17, 0.18, 0.21)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.75, 0.82)
	environment.ambient_light_energy = 0.9
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	key_light.light_energy = 1.5
	world.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-15.0, 140.0, 0.0)
	fill_light.light_energy = 0.5
	world.add_child(fill_light)
	return viewport


## Camera parented to the viewport (not the world node) so it survives the free.
func _build_preview_camera(viewport: SubViewport, yaw: float, elevation: float) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.current = true
	viewport.add_child(camera)
	camera.set_meta("yaw", yaw)
	camera.set_meta("elevation", elevation)
	return camera


## Frame `camera` on the character's bone bounds from the requested angle.
func _frame_preview_camera(camera: Camera3D, bounds: AABB, margin: float) -> void:
	var center := bounds.get_center()
	var radius := maxf((bounds.end - bounds.position).length() * 0.5, 0.1)
	var yaw := deg_to_rad(float(camera.get_meta("yaw", 28.0)))
	var elevation := deg_to_rad(float(camera.get_meta("elevation", 8.0)))
	var offset := Vector3(
		sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
	var distance := radius * margin / tan(deg_to_rad(camera.fov) * 0.5)
	camera.look_at_from_position(center + offset.normalized() * distance, center, Vector3.UP)


## The node copied into the preview viewport: `character_path` when given, else
## the skeleton's outermost Node3D ancestor below the scene root (copying the
## whole character keeps skin bindings, meshes and props intact).
func _preview_source(params: Dictionary, resolved: Dictionary) -> Node:
	var scene_root := EditorInterface.get_edited_scene_root()
	var character_path := str(params.get("character_path", ""))
	if not character_path.is_empty():
		if scene_root == null:
			return null
		var found := ValueCodec.resolve_scene_path(character_path, scene_root)
		return found as Node3D
	var node: Node = resolved.node
	while node.get_parent() is Node3D and node.get_parent() != scene_root:
		node = node.get_parent()
	return node as Node3D


## World-space bounds of every bone origin plus a rough skin margin.
func _preview_bounds(skeleton: Skeleton3D) -> AABB:
	var bounds := AABB()
	var first := true
	var xform := skeleton.global_transform
	for index in skeleton.get_bone_count():
		var point: Vector3 = xform * skeleton.get_bone_global_pose(index).origin
		if first:
			bounds = AABB(point, Vector3.ZERO)
			first = false
		else:
			bounds = bounds.expand(point)
	return bounds.grow(0.12)


func _find_skeleton(node: Node) -> Node:
	if node is Skeleton3D or node is Skeleton2D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


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
	elif tool == OpRegistry.FAMILY_FX:
		handler = FxHandler.new()
	elif tool == OpRegistry.FAMILY_GRAPH:
		handler = GraphHandler.new()
	elif tool == OpRegistry.FAMILY_EDIT:
		handler = EditHandler.new()
	elif tool == OpRegistry.FAMILY_LIBRARY:
		handler = LibraryHandler.new()
	elif tool == OpRegistry.FAMILY_RIG:
		handler = RigHandler.new()
	elif tool == OpRegistry.FAMILY_MOTION:
		handler = MotionHandler.new()
	else:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"dry_run supports %s, %s, %s, %s, %s, %s and %s (inspect ops are already read-only)"
			% [OpRegistry.FAMILY_PRESETS, OpRegistry.FAMILY_FX, OpRegistry.FAMILY_GRAPH, OpRegistry.FAMILY_EDIT, OpRegistry.FAMILY_LIBRARY, OpRegistry.FAMILY_RIG, OpRegistry.FAMILY_MOTION])
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
