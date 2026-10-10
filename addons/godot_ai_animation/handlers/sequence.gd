@tool
extends "res://addons/godot_ai_animation/handlers/bone_animation.gd"

## Compose existing 3D clips and saved rig poses into one character-owned clip.

const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const SequenceSpecs := preload("res://addons/godot_ai_animation/spec/sequence_specs.gd")
const PoseMath := preload("res://addons/godot_ai_animation/spec/pose_math.gd")


func run(params: Dictionary, _ctx) -> Dictionary:
	_dry_run = bool(params.get("dry_run", false))
	if str(params.get("op", "")) != "compose":
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "Unknown op; valid: compose")
	if not _dry_run:
		var ready := _require_undo("animation_sequence compose")
		if ready.has("error"):
			return ready
	var resolved := _resolve_player(str(params.get("player_path", "")))
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var available := _idle_clip_destination(player)
	if available.has("error"): return available
	var skeleton_result := _resolve_skeleton(params)
	if skeleton_result.has("error"):
		return skeleton_result
	if skeleton_result.kind != "3d":
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "compose needs a Skeleton3D")
	var skeleton: Skeleton3D = skeleton_result.node
	var player_root := ValueCodec.player_root_node(player)
	if player_root == null or not player_root.is_ancestor_of(skeleton):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The skeleton must be below the AnimationPlayer root_node")
	var name := str(params.get("animation_name", "sequence"))
	if name.is_empty() or name.contains("/"):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "animation_name must be a plain clip name")
	var library: AnimationLibrary = resolved.library
	var created_library := library == null
	if created_library: library = AnimationLibrary.new()
	var existing := _existing_animation(library, name, bool(params.get("overwrite", false)))
	if existing.has("error"): return existing.error
	var baseline := {}
	var source_segments = params.get("segments", [])
	if not source_segments is Array or source_segments.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "compose needs non-empty segments")
	var prepared: Array = []
	for index in source_segments.size():
		var raw = source_segments[index]
		if not raw is Dictionary:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "segments[%d] must be an object" % index)
		var segment: Dictionary = raw.duplicate(true)
		for field in ["start", "duration", "source_start", "source_end", "fade_in"]:
			if segment.has(field) and not (segment[field] is float or segment[field] is int): return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "segments[%d].%s must be a number" % [index, field])
		segment["source_start"] = float(segment.get("source_start", 0.0))
		segment["fade_in"] = float(segment.get("fade_in", 0.0))
		var source_name := str(segment.get("source_animation", ""))
		var pose_name := str(segment.get("pose_name", ""))
		var source_count := int(not source_name.is_empty()) + int(not pose_name.is_empty()) \
			+ int(segment.has("pose"))
		if source_count != 1:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"segments[%d] needs one source_animation or pose_name/pose" % index)
		if not source_name.is_empty():
			if not player.has_animation(source_name):
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"segments[%d] animation '%s' is missing" % [index, source_name])
			var anim := player.get_animation(source_name)
			if anim.get_script() != null: return ErrorCodes.make(ErrorCodes.OPERATION_UNAVAILABLE, "Scripted sequence source animations cannot be duplicated")
			# Refuse side-effect/value tracks before duplication can construct a
			# scripted resource stored in a key, including disabled tracks.
			for track in anim.get_track_count():
				if not anim.track_get_type(track) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
					return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "compose accepts only native 3D transform source tracks")
			if not SpecIO.unsupported_tracks(anim).is_empty() or not SpecIO.compressed_tracks(anim).is_empty():
				return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
					"segments[%d] contains unsupported or compressed tracks" % index)
			segment["spec"] = SpecIO.from_animation(anim)
			segment["_native_animation"] = anim.duplicate(true)
			segment._native_animation.loop_mode = Animation.LOOP_NONE
			segment["source_end"] = float(segment.get("source_end", anim.length))
			var source_start := float(segment.source_start)
			var source_end := float(segment.source_end)
			if not is_finite(source_start) or not is_finite(source_end) \
					or source_start < 0.0 or source_end > anim.length + 0.00001 \
					or source_end <= source_start:
				return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
					"segments[%d] source range must be within animation '%s' (0..%.3fs)" \
					% [index, source_name, anim.length])
		else:
			var posed := _pose_spec(segment, skeleton, str(player_root.get_path_to(skeleton)))
			if posed.has("error"):
				return ErrorCodes.make(str(posed.error.code),
					"segments[%d]: %s" % [index, str(posed.error.message)])
			segment["spec"] = posed.spec
			segment["source_start"] = 0.0
			segment["source_end"] = 1.0
		if not segment.has("duration"):
			segment["duration"] = float(segment.source_end) - float(segment.get("source_start", 0.0))
		var valid_source := SpecBuilder.validate(segment.spec)
		if valid_source.has("error"): return valid_source
		var enabled: Array = []
		for track in (segment.spec as Dictionary).get("tracks", []):
			if not bool(track.get("enabled", true)): continue
			var node := player_root.get_node_or_null(NodePath(ClipSpec.node_path_of(str(track.path))))
			var bone := ClipSpec.property_of(str(track.path))
			if node == null or (node is Skeleton3D and (node != skeleton or skeleton.find_bone(bone) < 0)) \
					or (not node is Skeleton3D and not node is Node3D):
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"segments[%d] has an unresolved 3D track: %s" % [index, str(track.path)])
			var kind := int(track.type)
			if not kind in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]: return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "compose accepts only native 3D transform tracks")
			var value: Variant
			if node is Skeleton3D:
				var bone_index := skeleton.find_bone(bone)
				value = skeleton.get_bone_pose_position(bone_index) if kind == Animation.TYPE_POSITION_3D else skeleton.get_bone_pose_rotation(bone_index) if kind == Animation.TYPE_ROTATION_3D else skeleton.get_bone_pose_scale(bone_index)
			else:
				var expected_channel: String = {Animation.TYPE_POSITION_3D: "position", Animation.TYPE_ROTATION_3D: "rotation", Animation.TYPE_SCALE_3D: "scale"}[kind]
				if not bone.is_empty() and bone != expected_channel: return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Invalid native transform channel: " + str(track.path))
				value = node.position if kind == Animation.TYPE_POSITION_3D else node.quaternion if kind == Animation.TYPE_ROTATION_3D else node.scale
			var label := "%d|%s" % [kind, str(track.path)]
			baseline[label] = value
			if str(track.path) == str(player.root_motion_track) and kind != Animation.TYPE_POSITION_3D: return ErrorCodes.make(ErrorCodes.OPERATION_UNAVAILABLE, "compose currently supports translation extraction only; use an in-place source or normalize root motion with baking")
			enabled.append(track)
		segment.spec.tracks = enabled
		prepared.append(segment)
	for field in ["duration", "samples"]:
		if params.has(field) and not (params[field] is float or params[field] is int): return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, field + " must be a number")
		if params.has(field) and not is_finite(float(params[field])): return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, field + " must be finite")
	var length := float(params.get("duration", 0.0))
	var built := SequenceSpecs.compose(prepared, length, int(params.get("samples", 30)),
		str(player.root_motion_track), baseline)
	if built.has("error"):
		return built
	var spec: Dictionary = built.spec
	var capture_duration := float(spec.length)
	var hold := preserve_translation_endpoint(spec, str(player.root_motion_track))
	if hold > 0.0 and int(built.sample_count) >= 1200: return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "Terminal root hold would exceed 1200 output keys per track")
	length = float(spec.length)
	var valid := SpecBuilder.validate(spec)
	if valid.has("error"):
		return valid
	_commit_animation_add("MCP: Compose %s" % name, player, library, created_library,
		name, SpecBuilder.to_animation(spec), existing.old_anim, _bone_pose_history_props(skeleton))
	return {"data": {
		"player_path": str(params.get("player_path", "")), "animation_name": name,
		"duration": length, "segments": prepared.size(),
		"capture_duration": capture_duration, "root_motion_terminal_hold": hold,
		"track_count": (spec.tracks as Array).size(),
		"key_count": ClipSpec.total_key_count(spec),
		"contact_markers": (spec.markers as Array).size(),
		"sample_count": int(built.sample_count) + int(hold > 0.0), "dry_run": _dry_run,
		"undoable": not _dry_run,
	}}


func _pose_spec(segment: Dictionary, skeleton: Skeleton3D, track_root: String) -> Dictionary:
	var json_pose = segment.get("pose")
	if json_pose == null:
		var pose_name := str(segment.get("pose_name", ""))
		if pose_name.is_empty() or pose_name.begins_with(".") \
				or pose_name.get_file() != pose_name or pose_name.contains("\\"):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "pose_name must be a plain name")
		var path := "res://animation_toolkit/poses/%s.json" % pose_name
		if not FileAccess.file_exists(path):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Pose file not found: %s" % path)
		json_pose = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not json_pose is Dictionary:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "pose must be a saved or inline pose object")
	var decoded := PoseMath.from_json(json_pose)
	if decoded.has("error"):
		return decoded
	var pose: Dictionary = decoded.pose
	var spec := ClipSpec.make(1.0)
	for bone in PoseMath.bone_names(pose):
		var index := skeleton.find_bone(str(bone))
		if index < 0:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, "Pose bone '%s' is absent" % bone)
		var rest := skeleton.get_bone_rest(index)
		var absolute := PoseMath.delta_to_pose(pose.bones[bone],
			rest.basis.get_rotation_quaternion(), rest.origin)
		var path := "%s:%s" % [track_root, bone]
		for entry in [
			{"type": Animation.TYPE_ROTATION_3D, "value": absolute.rotation},
			{"type": Animation.TYPE_POSITION_3D, "value": absolute.position},
			{"type": Animation.TYPE_SCALE_3D, "value": absolute.scale},
		]:
			ClipSpec.add_value_track(spec, path, [
				{"time": 0.0, "value": entry.value, "transition": 1.0},
				{"time": 1.0, "value": entry.value, "transition": 1.0},
			], Animation.INTERPOLATION_LINEAR, int(entry.type))
	return {"spec": spec}
