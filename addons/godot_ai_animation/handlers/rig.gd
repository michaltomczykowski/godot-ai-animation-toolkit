@tool
extends "res://addons/godot_ai_animation/handlers/animation_tool_base.gd"

## Rig authoring — the `animation_rig` tool.
##
## Phase 6a: poses. Capture a skeleton's pose as portable rest-relative data,
## apply/blend/mirror poses, keyframe poses into clips, and inspect rigs. Bone
## clips are ordinary 3D transform tracks (`Skeleton3D:bone`) or 2D value tracks
## (`Skeleton2D/Bone:rotation`), so every existing toolkit op works on them.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const PoseMath := preload("res://addons/godot_ai_animation/spec/pose_math.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const POSE_DIR := "res://animation_toolkit/poses"
const _LOOP_MODES := {
	"none": Animation.LOOP_NONE,
	"linear": Animation.LOOP_LINEAR,
	"pingpong": Animation.LOOP_PINGPONG,
}


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
		"pose_save":
			return rig_pose_save(params)
		"pose_apply":
			return rig_pose_apply(params)
		"pose_blend":
			return rig_pose_blend(params)
		"pose_to_clip":
			return rig_pose_to_clip(params)
		"pose_list":
			return rig_pose_list(params)
		"rig_get":
			return rig_get(params)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
		"Unknown op '%s'. Valid: %s" % [op, ", ".join(OpRegistry.op_names(OpRegistry.FAMILY_RIG))])


# ============================================================================
# pose_save
# ============================================================================

## Capture the skeleton's current pose (rest-relative), inline and/or to a file.
func rig_pose_save(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	var bones_filter: Array = params.get("bones", [])
	var captured := _capture_pose(resolved, bones_filter)
	if captured.has("error"):
		return captured
	var pose: Dictionary = captured.pose
	var name := str(params.get("name", ""))
	var path := str(params.get("path", ""))
	var saved := ""
	if not path.is_empty() or not name.is_empty():
		if path.is_empty():
			path = "%s/%s.json" % [_pose_dir(params), name]
		var written := _write_pose_file(path, pose, bool(params.get("overwrite", true)))
		if written.has("error"):
			return written
		saved = path
	return {"data": {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"pose": PoseMath.to_json(pose),
		"bone_count": PoseMath.bone_count(pose),
		"saved_path": saved,
		"undoable": false,
		"note": "pose files are not part of the undo stack",
	}}


# ============================================================================
# pose_apply
# ============================================================================

## Write a pose onto a skeleton (optionally blended with the current pose).
func rig_pose_apply(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	var loaded := _resolve_pose(params)
	if loaded.has("error"):
		return loaded
	var pose: Dictionary = loaded.pose
	var mirror := bool(params.get("mirror", false))
	var unmapped: Array = []
	if mirror:
		var mirrored := PoseMath.mirror_pose(pose)
		pose = mirrored.pose
		unmapped = mirrored.unmapped
	var bones_filter: Array = params.get("bones", [])
	if not bones_filter.is_empty():
		var subset := PoseMath.subset(pose, bones_filter)
		pose = subset.pose
		if not (subset.missing as Array).is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"The pose has no bones: %s" % ", ".join(subset.missing))
	var blend := clampf(float(params.get("blend", 1.0)), 0.0, 1.0)
	var reset_first := bool(params.get("reset_first", false))
	var applied := _apply_pose(resolved, pose, blend, reset_first)
	if applied.has("error"):
		return applied
	return {"data": {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"pose_source": str(loaded.get("source", "")),
		"bone_count": int(applied.applied),
		"missing_bones": applied.missing,
		"unmapped_bones": unmapped,
		"blend": blend,
		"reset_first": reset_first,
		"undoable": true,
	}}


# ============================================================================
# pose_blend
# ============================================================================

## Blend two poses into a third (optionally mirrored / saved).
func rig_pose_blend(params: Dictionary) -> Dictionary:
	var from_loaded := _resolve_pose(params, "from")
	if from_loaded.has("error"):
		return from_loaded
	var to_loaded := _resolve_pose(params, "to")
	if to_loaded.has("error"):
		return to_loaded
	var factor := clampf(float(params.get("factor", 0.5)), 0.0, 1.0)
	var a: Dictionary = from_loaded.pose
	var b: Dictionary = to_loaded.pose
	if bool(params.get("mirror", false)):
		a = PoseMath.mirror_pose(a).pose
		b = PoseMath.mirror_pose(b).pose
	var blended := PoseMath.blend_pose(a, b, factor)
	var pose: Dictionary = blended.pose
	var saved := ""
	var name := str(params.get("name", ""))
	var path := str(params.get("path", ""))
	if not path.is_empty() or not name.is_empty():
		if path.is_empty():
			path = "%s/%s.json" % [_pose_dir(params), name]
		var written := _write_pose_file(path, pose, bool(params.get("overwrite", true)))
		if written.has("error"):
			return written
		saved = path
	return {"data": {
		"pose": PoseMath.to_json(pose),
		"bone_count": PoseMath.bone_count(pose),
		"factor": factor,
		"only_in_from": blended.only_a,
		"only_in_to": blended.only_b,
		"saved_path": saved,
		"undoable": false,
	}}


# ============================================================================
# pose_to_clip
# ============================================================================

## Keyframe a sequence of poses into a clip on an AnimationPlayer.
func rig_pose_to_clip(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "pose_to_clip needs 'player_path'")
	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved_player := _resolve_player(player_path)
	if resolved_player.has("error"):
		return resolved_player
	var player: AnimationPlayer = resolved_player.player
	var library: AnimationLibrary = resolved_player.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	var keys: Array = params.get("keys", [])
	if keys.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"pose_to_clip needs 'keys': [{pose|name|path, time, transition?}]")
	var loop_result := _loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var root_node := ValueCodec.player_root_node(player)
	if root_node == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"AnimationPlayer at %s has no resolvable root_node" % player_path)
	var track_root := str(root_node.get_path_to(resolved.node))
	if track_root.is_empty() or track_root == ".":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The skeleton must live under the player's root_node")
	# Resolve every key's pose first so a bad reference fails before any commit.
	var resolved_keys: Array = []
	var bones: Array = []
	var length := 0.0
	for index in keys.size():
		var key: Dictionary = keys[index]
		var key_params: Dictionary = key.duplicate()
		if not key_params.has("pose_dir"):
			key_params["pose_dir"] = params.get("pose_dir", "")
		var pose_loaded := _resolve_pose(key_params)
		if pose_loaded.has("error"):
			return ErrorCodes.make(pose_loaded.error.code,
				"keys[%d]: %s" % [index, str(pose_loaded.error.message)])
		var time := float(key.get("time", -1.0))
		if time < 0.0:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "keys[%d] needs 'time'" % index)
		var pose: Dictionary = pose_loaded.pose
		if bool(key.get("mirror", false)):
			pose = PoseMath.mirror_pose(pose).pose
		for bone in PoseMath.bone_names(pose):
			if not bones.has(bone):
				bones.append(bone)
		resolved_keys.append({
			"time": time,
			"pose": pose,
			"transition": ValueCodec.parse_transition(key.get("transition", "linear")),
		})
		length = maxf(length, time)
	if bones.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The poses contain no bones")
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "The keys need at least one time > 0")
	var include_positions := bool(params.get("positions", false))
	var include_scales := bool(params.get("scales", false))
	var anim_name := str(params.get("animation_name", "pose_clip"))
	var spec := ClipSpec.make(length, loop_result.ok)
	if resolved.kind == "3d":
		var skeleton: Skeleton3D = resolved.node
		for bone in bones:
			var rest := _bone_rest(skeleton, str(bone))
			if rest.has("error"):
				continue
			var rotation_keys: Array = []
			var position_keys: Array = []
			var scale_keys: Array = []
			var moves_rotation := false
			var moves_position := false
			var moves_scale := false
			for entry in resolved_keys:
				if not PoseMath.has_bone(entry.pose, str(bone)):
					continue
				var delta: Dictionary = entry.pose.bones[bone]
				var absolute := PoseMath.delta_to_pose(delta, rest.rotation, rest.position)
				rotation_keys.append({"time": entry.time, "value": absolute.rotation, "transition": entry.transition})
				position_keys.append({"time": entry.time, "value": absolute.position, "transition": entry.transition})
				scale_keys.append({"time": entry.time, "value": absolute.scale, "transition": entry.transition})
				var rotation_delta: Quaternion = delta.get("rotation", Quaternion.IDENTITY)
				if absf(rotation_delta.get_angle()) > 0.0001:
					moves_rotation = true
				if (delta.get("position", Vector3.ZERO) as Vector3).length() > 0.0001:
					moves_position = true
				if not (delta.get("scale", Vector3.ONE) as Vector3).is_equal_approx(Vector3.ONE):
					moves_scale = true
			if rotation_keys.is_empty():
				continue
			# Static bones stay out of the clip entirely, so a pose pair that only
			# moves an arm produces one track instead of one per bone.
			if not (moves_rotation or (include_positions and moves_position) or (include_scales and moves_scale)):
				continue
			if moves_rotation:
				ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone], rotation_keys,
					Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
			if include_positions and moves_position:
				ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone], position_keys,
					Animation.INTERPOLATION_LINEAR, Animation.TYPE_POSITION_3D)
			if include_scales and moves_scale:
				ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone], scale_keys,
					Animation.INTERPOLATION_LINEAR, Animation.TYPE_SCALE_3D)
	else:
		var skeleton_2d: Skeleton2D = resolved.node
		for bone in bones:
			var rest_2d := _bone_rest_2d(skeleton_2d, str(bone))
			if rest_2d.has("error"):
				continue
			var rotation_keys_2d: Array = []
			var moves_rotation_2d := false
			for entry in resolved_keys:
				if not PoseMath.has_bone(entry.pose, str(bone)):
					continue
				var delta_2d: Dictionary = entry.pose.bones[bone]
				var delta_angle: float = _quaternion_to_angle(delta_2d.get("rotation", Quaternion.IDENTITY))
				if absf(delta_angle) > 0.0001:
					moves_rotation_2d = true
				rotation_keys_2d.append({
					"time": entry.time,
					"value": rest_2d.angle + delta_angle,
					"transition": entry.transition,
				})
			if rotation_keys_2d.is_empty() or not moves_rotation_2d:
				continue
			ClipSpec.add_value_track(spec, "%s/%s:rotation" % [track_root, bone], rotation_keys_2d)
	var valid := SpecBuilder.validate(spec)
	if valid.has("error"):
		return valid
	var overwrite := bool(params.get("overwrite", false))
	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var anim := SpecBuilder.to_animation(spec)
	_commit_animation_add("MCP: Pose clip %s" % anim_name, player, library,
		created_library, anim_name, anim, existing.old_anim)
	return {"data": {
		"player_path": player_path,
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"animation_name": anim_name,
		"length": float(spec.length),
		"loop_mode": ValueCodec.loop_mode_to_string(int(spec.loop_mode)),
		"track_count": (spec.tracks as Array).size(),
		"key_count": ClipSpec.total_key_count(spec),
		"bone_count": bones.size(),
		"bones": bones,
		"positions": include_positions,
		"scales": include_scales,
		"library_created": created_library,
		"overwritten": existing.old_anim != null,
		"undoable": true,
	}}


# ============================================================================
# pose_list
# ============================================================================

## List the pose files saved in the project's pose directory.
func rig_pose_list(params: Dictionary) -> Dictionary:
	var directory := str(params.get("directory", _pose_dir(params)))
	var entries: Array = []
	var dir := DirAccess.open(directory)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var path := "%s/%s" % [directory, file_name]
				var raw := _read_json(path)
				var summary := {}
				if not raw.has("error"):
					var decoded := PoseMath.from_json(raw.data)
					if not decoded.has("error"):
						summary = PoseMath.summarize(decoded.pose)
				entries.append({
					"name": file_name.get_basename(),
					"path": path,
					"bone_count": int(summary.get("bone_count", 0)),
					"source": str(summary.get("source", "")),
				})
			file_name = dir.get_next()
		dir.list_dir_end()
	entries.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return {"data": {
		"directory": directory,
		"exists": dir != null,
		"pose_count": entries.size(),
		"poses": entries,
	}}


# ============================================================================
# rig_get
# ============================================================================

## Dump a skeleton's bones/rests/pose, modifiers, springs, plus issues.
func rig_get(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	var include_pose := bool(params.get("include_pose", true))
	var bones: Array = []
	var issues: Array = []
	if resolved.kind == "3d":
		var skeleton: Skeleton3D = resolved.node
		var captured := _capture_pose(resolved, [])
		var pose: Dictionary = captured.get("pose", PoseMath.make_pose())
		for index in skeleton.get_bone_count():
			var rest := skeleton.get_bone_rest(index)
			var entry := {
				"name": skeleton.get_bone_name(index),
				"index": index,
				"parent": skeleton.get_bone_parent(index),
				"rest_position": ValueCodec.serialize(rest.origin),
				"rest_scale": ValueCodec.serialize(rest.basis.get_scale()),
			}
			if include_pose and PoseMath.has_bone(pose, skeleton.get_bone_name(index)):
				var delta: Dictionary = pose.bones[skeleton.get_bone_name(index)]
				entry["pose_rotation"] = ValueCodec.serialize(delta.get("rotation", Quaternion.IDENTITY))
				entry["pose_position"] = ValueCodec.serialize(delta.get("position", Vector3.ZERO))
			bones.append(entry)
		if not skeleton.scale.is_equal_approx(Vector3.ONE):
			issues.append({"severity": "warning", "code": "scaled_skeleton",
				"message": "the Skeleton3D is scaled (%s); spring bones and IK assume unit scale" % str(skeleton.scale)})
	else:
		var skeleton_2d: Skeleton2D = resolved.node
		for index in skeleton_2d.get_bone_count():
			var bone := skeleton_2d.get_bone(index)
			bones.append({
				"name": str(bone.name),
				"index": index,
				"parent": str(bone.get_parent().name),
				"rest_position": ValueCodec.serialize(bone.rest.origin),
				"length": bone.get_length(),
			})
	var modifiers: Array = []
	for child in resolved.node.get_children():
		if child is SkeletonModifier3D:
			var modifier := child as SkeletonModifier3D
			modifiers.append({
				"name": str(modifier.name),
				"type": modifier.get_class(),
				"active": modifier.active,
				"influence": modifier.influence,
			})
	var springs: Array = []
	var stack_summary := {}
	if resolved.kind == "2d":
		var stack := (resolved.node as Skeleton2D).get_modification_stack()
		if stack != null:
			stack_summary = {
				"enabled": stack.enabled,
				"strength": stack.strength,
				"modification_count": stack.modification_count,
				"is_setup": stack.get_is_setup(),
			}
	var issues_found := _bone_track_issues(resolved)
	issues.append_array(issues_found)
	return {"data": {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"bone_count": bones.size(),
		"bones": bones,
		"modifiers": modifiers,
		"spring_settings": springs,
		"modification_stack": stack_summary,
		"issues": issues,
	}}


# ============================================================================
# Helpers
# ============================================================================

## Resolve the target skeleton: `skeleton_path` (scene-absolute or relative), or
## the first Skeleton3D / Skeleton2D in the edited scene.
func _resolve_skeleton(params: Dictionary) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No edited scene open")
	var path := str(params.get("skeleton_path", ""))
	var node: Node = null
	if not path.is_empty():
		node = ValueCodec.resolve_scene_path(path, scene_root)
		if node == null:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(path, scene_root))
	else:
		for candidate in scene_root.find_children("*", "Skeleton3D", true, false):
			node = candidate
			break
		if node == null:
			for candidate in scene_root.find_children("*", "Skeleton2D", true, false):
				node = candidate
				break
		if node == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"No skeleton found in the edited scene (pass skeleton_path)")
	if node is Skeleton3D:
		return {"node": node, "kind": "3d", "path": ValueCodec.from_node(node, scene_root)}
	if node is Skeleton2D:
		return {"node": node, "kind": "2d", "path": ValueCodec.from_node(node, scene_root)}
	return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
		"Node at %s is not a Skeleton3D or Skeleton2D (got %s)" % [path, node.get_class()])


## Capture a rest-relative pose. `bones_filter` empty captures every bone.
func _capture_pose(resolved: Dictionary, bones_filter: Array) -> Dictionary:
	var pose := PoseMath.make_pose(resolved.path)
	if resolved.kind == "3d":
		var skeleton: Skeleton3D = resolved.node
		for index in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(index)
			if not bones_filter.is_empty() and not bones_filter.has(name):
				continue
			var rest := skeleton.get_bone_rest(index)
			var delta := PoseMath.pose_to_delta(
				skeleton.get_bone_pose_rotation(index),
				skeleton.get_bone_pose_position(index),
				skeleton.get_bone_pose_scale(index),
				rest.basis.get_rotation_quaternion(),
				rest.origin,
			)
			PoseMath.set_bone(pose, name, delta.rotation, delta.position, delta.scale)
	else:
		var skeleton_2d: Skeleton2D = resolved.node
		for index in skeleton_2d.get_bone_count():
			var bone := skeleton_2d.get_bone(index)
			if not bones_filter.is_empty() and not bones_filter.has(str(bone.name)):
				continue
			var angle := bone.rotation - bone.rest.get_rotation()
			var offset := bone.position - bone.rest.get_origin()
			PoseMath.set_bone(pose, str(bone.name),
				Quaternion(Vector3(0, 0, 1), angle),
				Vector3(offset.x, offset.y, 0.0),
				Vector3(bone.scale.x, bone.scale.y, 1.0))
	if PoseMath.bone_count(pose) == 0:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The skeleton has no bones to capture")
	return {"pose": pose}


## Apply a pose as one undo action. `blend` lerps from the current pose.
func _apply_pose(resolved: Dictionary, pose: Dictionary, blend: float, reset_first: bool) -> Dictionary:
	var missing: Array = []
	var applied := 0
	_create_scene_pinned_action("MCP: Apply pose")
	var undo := ToolContext.undo_redo
	var skeleton: Node = resolved.node
	if resolved.kind == "3d":
		var skeleton_3d := skeleton as Skeleton3D
		if reset_first:
			for index in skeleton_3d.get_bone_count():
				undo.add_do_method(skeleton_3d, "reset_bone_pose", index)
				undo.add_undo_method(skeleton_3d, "set_bone_pose_rotation", index, skeleton_3d.get_bone_pose_rotation(index))
				undo.add_undo_method(skeleton_3d, "set_bone_pose_position", index, skeleton_3d.get_bone_pose_position(index))
				undo.add_undo_method(skeleton_3d, "set_bone_pose_scale", index, skeleton_3d.get_bone_pose_scale(index))
		for bone in PoseMath.bone_names(pose):
			var index := skeleton_3d.find_bone(str(bone))
			if index < 0:
				missing.append(str(bone))
				continue
			var rest := skeleton_3d.get_bone_rest(index)
			var delta: Dictionary = pose.bones[bone]
			var absolute := PoseMath.delta_to_pose(delta, rest.basis.get_rotation_quaternion(), rest.origin)
			var rotation: Quaternion = absolute.rotation
			var position: Vector3 = absolute.position
			var scale: Vector3 = absolute.scale
			if blend < 1.0:
				rotation = skeleton_3d.get_bone_pose_rotation(index).slerp(rotation, blend)
				position = skeleton_3d.get_bone_pose_position(index).lerp(position, blend)
				scale = skeleton_3d.get_bone_pose_scale(index).lerp(scale, blend)
			undo.add_do_method(skeleton_3d, "set_bone_pose_rotation", index, rotation)
			undo.add_do_method(skeleton_3d, "set_bone_pose_position", index, position)
			undo.add_do_method(skeleton_3d, "set_bone_pose_scale", index, scale)
			undo.add_undo_method(skeleton_3d, "set_bone_pose_rotation", index, skeleton_3d.get_bone_pose_rotation(index))
			undo.add_undo_method(skeleton_3d, "set_bone_pose_position", index, skeleton_3d.get_bone_pose_position(index))
			undo.add_undo_method(skeleton_3d, "set_bone_pose_scale", index, skeleton_3d.get_bone_pose_scale(index))
			applied += 1
	else:
		var skeleton_2d := skeleton as Skeleton2D
		for bone in PoseMath.bone_names(pose):
			var target: Bone2D = null
			for index in skeleton_2d.get_bone_count():
				if str(skeleton_2d.get_bone(index).name) == str(bone):
					target = skeleton_2d.get_bone(index)
					break
			if target == null:
				missing.append(str(bone))
				continue
			var delta_2d: Dictionary = pose.bones[bone]
			var angle := target.rest.get_rotation() + _quaternion_to_angle(delta_2d.get("rotation", Quaternion.IDENTITY))
			var offset: Vector3 = delta_2d.get("position", Vector3.ZERO)
			if blend < 1.0:
				angle = lerp_angle(target.rotation, angle, blend)
				offset = Vector3(target.position.x, target.position.y, 0.0).lerp(
					Vector3(target.rest.get_origin().x + offset.x, target.rest.get_origin().y + offset.y, 0.0), blend)
			else:
				offset = Vector3(target.rest.get_origin().x + offset.x, target.rest.get_origin().y + offset.y, 0.0)
			undo.add_do_method(target, "set_rotation", angle)
			undo.add_do_method(target, "set_position", Vector2(offset.x, offset.y))
			undo.add_undo_method(target, "set_rotation", target.rotation)
			undo.add_undo_method(target, "set_position", target.position)
			applied += 1
	undo.commit_action()
	return {"applied": applied, "missing": missing}


## Resolve a pose from `pose` (inline), `name` (pose dir) or `path`, with an
## optional key prefix ("from"/"to" for pose_blend).
func _resolve_pose(params: Dictionary, prefix: String = "") -> Dictionary:
	var key := prefix if prefix.is_empty() else prefix
	var inline = params.get("pose") if prefix.is_empty() else params.get("%s_pose" % key)
	var shorthand := ""
	if not prefix.is_empty():
		var bare = params.get(key)
		if bare is String:
			shorthand = str(bare)
		elif inline == null:
			inline = bare
	if inline is Dictionary and not (inline as Dictionary).is_empty():
		var decoded := PoseMath.from_json(inline)
		if decoded.has("error"):
			return decoded
		return {"pose": decoded.pose, "source": "inline"}
	var name := str(params.get("name", "")) if prefix.is_empty() else str(params.get("%s_name" % key, shorthand))
	var path := str(params.get("path", "")) if prefix.is_empty() else str(params.get("%s_path" % key, ""))
	if path.is_empty() and not name.is_empty():
		path = "%s/%s.json" % [_pose_dir(params), name]
	if path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"Pass a pose as 'pose' (inline), 'name' (saved pose) or 'path' (file)")
	if not FileAccess.file_exists(path):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Pose file not found: %s" % path)
	var raw := _read_json(path)
	if raw.has("error"):
		return raw
	var loaded := PoseMath.from_json(raw.data)
	if loaded.has("error"):
		return ErrorCodes.make(loaded.error.code, "%s: %s" % [path, str(loaded.error.message)])
	return {"pose": loaded.pose, "source": path}


## Pose files live in res://animation_toolkit/poses by default; `pose_dir`
## redirects them (tests use a scratch directory).
static func _pose_dir(params: Dictionary) -> String:
	var directory := str(params.get("pose_dir", POSE_DIR))
	return directory if not directory.is_empty() else POSE_DIR


func _write_pose_file(path: String, pose: Dictionary, overwrite: bool) -> Dictionary:
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
	file.store_string(JSON.stringify(PoseMath.to_json(pose), "  "))
	file.close()
	return {"ok": true}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "%s is not valid JSON" % path)
	return {"data": parsed}


func _bone_rest(skeleton: Skeleton3D, bone: String) -> Dictionary:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Bone '%s' not found" % bone)
	var rest := skeleton.get_bone_rest(index)
	return {"rotation": rest.basis.get_rotation_quaternion(), "position": rest.origin}


func _bone_rest_2d(skeleton: Skeleton2D, bone: String) -> Dictionary:
	for index in skeleton.get_bone_count():
		var candidate := skeleton.get_bone(index)
		if str(candidate.name) == bone:
			return {"angle": candidate.rest.get_rotation(), "position": candidate.rest.get_origin()}
	return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Bone '%s' not found" % bone)


## Track paths in the scene's clips that name bones this skeleton does not have.
func _bone_track_issues(resolved: Dictionary) -> Array:
	var issues: Array = []
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return issues
	var bone_names := {}
	if resolved.kind == "3d":
		var skeleton: Skeleton3D = resolved.node
		for index in skeleton.get_bone_count():
			bone_names[skeleton.get_bone_name(index)] = true
	else:
		var skeleton_2d: Skeleton2D = resolved.node
		for index in skeleton_2d.get_bone_count():
			bone_names[str(skeleton_2d.get_bone(index).name)] = true
	for player in scene_root.find_children("*", "AnimationPlayer", true, false):
		var animation_player := player as AnimationPlayer
		for library_name in animation_player.get_animation_library_list():
			var library := animation_player.get_animation_library(library_name)
			if library == null:
				continue
			for clip_name in library.get_animation_list():
				var anim: Animation = library.get_animation(clip_name)
				for index in anim.get_track_count():
					var path := str(anim.track_get_path(index))
					var node_part := ClipSpec.node_path_of(path)
					if not node_part.ends_with(str(resolved.node.name)):
						continue
					var bone := ClipSpec.property_of(path)
					if bone.is_empty() or bone_names.has(bone):
						continue
					issues.append({"severity": "warning", "code": "unknown_bone",
						"message": "clip '%s' animates bone '%s', which this skeleton does not have"
							% [clip_name, bone]})
	return issues


static func _quaternion_to_angle(q: Quaternion) -> float:
	return q.get_euler().z


static func _loop_mode(params: Dictionary) -> Dictionary:
	var mode := str(params.get("loop_mode", "none"))
	if not _LOOP_MODES.has(mode):
		return {"error": "Invalid loop_mode '%s'. Valid: %s" % [mode, ", ".join(_LOOP_MODES.keys())]}
	return {"ok": _LOOP_MODES[mode]}
