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
		"rig_chain":
			return rig_chain(params)
		"ik_setup":
			return ik_setup(params)
		"spring_setup":
			return spring_setup(params)
		"look_at_setup":
			return look_at_setup(params)
		"retarget_setup":
			return retarget_setup(params)
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
# rig_chain
# ============================================================================

const IK_3D_KINDS := {
	"two_bone": "TwoBoneIK3D",
	"ccdik": "CCDIK3D",
	"fabrik": "FABRIK3D",
	"jacobian": "JacobianIK3D",
	"spline": "SplineIK3D",
}

## Build bones on a skeleton: from a bone spec (`bones`), or by turning a
## Node3D / Node2D subtree into a skeleton (`node_path`).
func rig_chain(params: Dictionary) -> Dictionary:
	var from_node := str(params.get("node_path", ""))
	if not from_node.is_empty():
		return _rig_chain_from_subtree(params, from_node)
	return _rig_chain_from_spec(params)


## `rig_chain` from a bone spec. The skeleton is created at `skeleton_path`
## when nothing is there yet, otherwise the bones are appended to it.
func _rig_chain_from_spec(params: Dictionary) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No edited scene open")
	var spec: Array = params.get("bones", [])
	if spec.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"rig_chain needs 'bones': [{name, parent?, position?, rotation?, scale?, length?}]")
	var skeleton_path := str(params.get("skeleton_path", ""))
	if skeleton_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"rig_chain needs 'skeleton_path' (where the skeleton is, or should be)")
	var existing := ValueCodec.resolve_scene_path(skeleton_path, scene_root)
	var kind := str(params.get("kind", "3d"))
	if existing is Skeleton2D:
		kind = "2d"
	elif existing is Skeleton3D:
		kind = "3d"
	elif existing != null:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Node at %s is not a Skeleton3D or Skeleton2D (got %s)" % [skeleton_path, existing.get_class()])
	if kind != "2d" and kind != "3d":
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid kind '%s'. Valid: 3d, 2d" % kind)
	var holder: Node = null
	if existing == null:
		holder = ValueCodec.resolve_scene_path(skeleton_path.get_base_dir(), scene_root)
		if holder == null:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
				"Cannot create a skeleton at %s: its parent does not exist" % skeleton_path)
	return _build_chain(params, spec, kind, existing, holder,
		str(params.get("name", "Skeleton3D" if kind == "3d" else "Skeleton2D")), "spec", "")


## `rig_chain` from a Node3D / Node2D subtree: the subtree's local transforms
## become bone rests on a new skeleton placed under the subtree root.
func _rig_chain_from_subtree(params: Dictionary, from_node: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No edited scene open")
	var root := ValueCodec.resolve_scene_path(from_node, scene_root)
	if root == null:
		return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(from_node, scene_root))
	if not (root is Node3D) and not (root is Node2D):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Node at %s is not a Node3D or Node2D (got %s)" % [from_node, root.get_class()])
	var kind := "3d" if root is Node3D else "2d"
	var spec: Array = [{"name": str(root.name), "parent": ""}]
	var seen := {str(root.name): true}
	var duplicates: Array = []
	var queue: Array = []
	for child in root.get_children():
		queue.append({"node": child, "parent": str(root.name)})
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var node: Node = item.node
		if node is Node3D or node is Node2D:
			var name := str(node.name)
			if seen.has(name):
				duplicates.append(name)
			else:
				seen[name] = true
				spec.append({
					"name": name,
					"parent": str(item.parent),
					"position": _node_offset(node, kind),
					"rotation": _node_rotation(node, kind),
				})
		for child in node.get_children():
			queue.append({"node": child, "parent": str(node.name)})
	if not duplicates.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Duplicate node names cannot become bones: %s" % ", ".join(duplicates))
	return _build_chain(params, spec, kind, null, root,
		str(params.get("name", "%sSkeleton" % root.name)), "subtree",
		ValueCodec.from_node(root, scene_root))


## Shared chain build: append bones to `existing`, or create the skeleton under
## `holder` first. One undo action either way.
func _build_chain(
	params: Dictionary, spec: Array, kind: String, existing: Node, holder: Node,
	default_name: String, mode: String, source_path: String,
) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	var occupied := {}
	var offset := 0
	if existing is Skeleton3D:
		var skeleton_3d: Skeleton3D = existing
		offset = skeleton_3d.get_bone_count()
		for index in offset:
			occupied[skeleton_3d.get_bone_name(index)] = true
	elif existing is Skeleton2D:
		var skeleton_2d: Skeleton2D = existing
		offset = skeleton_2d.get_bone_count()
		for index in offset:
			occupied[str(skeleton_2d.get_bone(index).name)] = true
	var validated := _validate_bone_spec(spec, occupied)
	if validated.has("error"):
		return validated
	for bone in spec:
		var bone_name := str((bone as Dictionary).name)
		if occupied.has(bone_name):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Bone '%s' already exists on the skeleton" % bone_name)
	var skeleton_node: Node = existing
	var created := false
	if skeleton_node == null:
		skeleton_node = Skeleton3D.new() if kind == "3d" else Skeleton2D.new()
		skeleton_node.name = default_name
		created = true
	var warnings: Array = []
	var scale := _skeleton_scale(existing if existing != null else holder)
	if not is_equal_approx(scale, 1.0):
		warnings.append("the skeleton is scaled (%.2f): springs and IK assume unit scale" % scale)
	var label := "MCP: Rig chain (%d bones)" % spec.size()
	if kind == "3d":
		var skeleton_3d_new: Skeleton3D = skeleton_node
		var by_name := {}
		for index in spec.size():
			by_name[str((spec[index] as Dictionary).name)] = offset + index
		var calls: Array = []
		for index in spec.size():
			var bone: Dictionary = spec[index]
			var rest := _spec_rest_3d(bone)
			var bone_index := offset + index
			calls.append({"method": "add_bone", "args": [str(bone.name)]})
			calls.append({"method": "set_bone_rest", "args": [bone_index, rest]})
			calls.append({"method": "set_bone_pose_position", "args": [bone_index, rest.origin]})
			calls.append({"method": "set_bone_pose_rotation", "args": [bone_index, rest.basis.get_rotation_quaternion()]})
			calls.append({"method": "set_bone_pose_scale", "args": [bone_index, rest.basis.get_scale()]})
		for index in spec.size():
			var parent_name := str((spec[index] as Dictionary).get("parent", ""))
			if not parent_name.is_empty():
				var parent_index: int = by_name[parent_name] if by_name.has(parent_name) \
					else skeleton_3d_new.find_bone(parent_name)
				calls.append({"method": "set_bone_parent", "args": [offset + index, parent_index]})
		var entries: Array = []
		if created:
			entries.append({"parent": holder, "node": skeleton_3d_new, "setup": []})
		entries.append({"parent": skeleton_3d_new, "node": skeleton_3d_new,
			"existing": true, "setup": calls})
		_commit_node_add_many(label, entries)
	else:
		var entries_2d: Array = []
		if created:
			entries_2d.append({"parent": holder, "node": skeleton_node, "setup": []})
		var bone_nodes := {}
		for index in spec.size():
			var bone_node := Bone2D.new()
			bone_node.name = str((spec[index] as Dictionary).name)
			bone_nodes[str((spec[index] as Dictionary).name)] = bone_node
		for index in spec.size():
			var bone_spec: Dictionary = spec[index]
			var parent_name := str(bone_spec.get("parent", ""))
			var bone_holder: Node = skeleton_node if parent_name.is_empty() else bone_nodes[parent_name]
			entries_2d.append({"parent": bone_holder, "node": bone_nodes[str(bone_spec.name)],
				"setup": _bone_2d_setup(bone_spec)})
		_commit_node_add_many(label, entries_2d)
	var data := {
		"skeleton_path": ValueCodec.from_node(skeleton_node, scene_root),
		"kind": kind,
		"skeleton_created": created,
		"mode": mode,
		"bones_created": spec.size(),
		"bones": spec.map(func(entry): return str((entry as Dictionary).name)),
		"warnings": warnings,
		"undoable": true,
	}
	if not source_path.is_empty():
		data["source_path"] = source_path
		data["note"] = "bone rests mirror the subtree's local transforms"
	else:
		data["note"] = "pose these bones with pose_apply and key them with pose_to_clip, or drive them with ik_setup"
	return {"data": data}


# ============================================================================
# ik_setup
# ============================================================================

## Attach an IK modifier to a Skeleton3D and point it at a target node. The
## modifier is created inactive unless active=true.
func ik_setup(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"ik_setup supports Skeleton3D for now: the 2D skeleton modification stack is Experimental in Godot 4.7. Build 2D chains with rig_chain and pose them with pose_apply / pose_to_clip.")
	var kind := str(params.get("kind", "two_bone"))
	if not IK_3D_KINDS.has(kind):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid kind '%s'. Valid: %s" % [kind, ", ".join(IK_3D_KINDS.keys())])
	var chain: Array = params.get("chain", [])
	if chain.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"ik_setup needs 'chain': bone names from the chain root to the effector")
	var use_virtual_end := bool(params.get("use_virtual_end", false))
	if kind == "two_bone":
		if chain.size() < (2 if use_virtual_end else 3):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"two_bone IK needs chain [root, middle, end] (or [root, middle] with use_virtual_end=true)")
	elif chain.size() < 2:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"%s IK needs a chain with at least a root and an end bone" % kind)
	var scene_root := EditorInterface.get_edited_scene_root()
	var skeleton: Skeleton3D = resolved.node
	for bone_name in chain:
		if skeleton.find_bone(str(bone_name)) < 0:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Bone '%s' not found on %s" % [str(bone_name), resolved.path])
	var warnings: Array = []
	var scale := _skeleton_scale(skeleton)
	if not is_equal_approx(scale, 1.0):
		warnings.append("the skeleton is scaled (%.2f): IK assumes unit scale" % scale)
	var target_path := str(params.get("target_path", ""))
	var target: Node3D = null
	if not target_path.is_empty():
		var found := ValueCodec.resolve_scene_path(target_path, scene_root)
		if found == null:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(target_path, scene_root))
		if not (found is Node3D):
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"The IK target must be a Node3D (got %s)" % found.get_class())
		target = found
	var pole: Node3D = null
	var pole_path := str(params.get("pole_path", ""))
	if kind == "two_bone" and not pole_path.is_empty():
		var found_pole := ValueCodec.resolve_scene_path(pole_path, scene_root)
		if found_pole == null:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(pole_path, scene_root))
		if not (found_pole is Node3D):
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"The IK pole must be a Node3D (got %s)" % found_pole.get_class())
		pole = found_pole
	var end_index := skeleton.find_bone(str(chain[chain.size() - 1]))
	var tip := _bone_tip_3d(skeleton, end_index)
	if tip.get("warning") != null:
		warnings.append(str(tip.warning))
	var modifier: SkeletonModifier3D = ClassDB.instantiate(IK_3D_KINDS[kind])
	if modifier == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"%s is not available in this Godot build" % IK_3D_KINDS[kind])
	modifier.name = str(params.get("name", "IK%s" % kind.capitalize()))
	var active := bool(params.get("active", false))
	var entries: Array = []
	var target_created := false
	var target_node: Node3D = target
	if target_node == null:
		var marker := Marker3D.new()
		marker.name = str(params.get("target_name", "IKTarget"))
		entries.append({"parent": scene_root, "node": marker,
			"setup": [{"method": "set_global_position", "args": [tip.position]}]})
		target_node = marker
		target_created = true
	var setup: Array = [{"property": "active", "value": active}]
	var target_rel := str(skeleton.get_path_to(target_node))
	if target_rel.is_empty():
		target_rel = "."
	setup.append({"method": "set_setting_count", "args": [1]})
	setup.append({"method": "set_root_bone_name", "args": [0, str(chain[0])]})
	if kind == "two_bone":
		setup.append({"method": "set_middle_bone_name", "args": [0, str(chain[1])]})
		if chain.size() >= 3:
			setup.append({"method": "set_end_bone_name", "args": [0, str(chain[2])]})
		else:
			setup.append({"method": "set_use_virtual_end", "args": [0, true]})
			setup.append({"method": "set_extend_end_bone", "args": [0, true]})
			setup.append({"method": "set_end_bone_length", "args": [0, float(params.get("end_bone_length", 0.1))]})
		if pole != null:
			setup.append({"method": "set_pole_node", "args": [0, str(skeleton.get_path_to(pole))]})
	else:
		setup.append({"method": "set_end_bone_name", "args": [0, str(chain[chain.size() - 1])]})
	setup.append({"method": "set_target_node", "args": [0, NodePath(target_rel)]})
	entries.append({"parent": skeleton, "node": modifier, "setup": setup})
	_commit_node_add_many("MCP: IK setup (%s)" % kind, entries)
	var data := {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"ik_kind": kind,
		"modifier_class": IK_3D_KINDS[kind],
		"modifier_path": ValueCodec.from_node(modifier, scene_root),
		"target_path": ValueCodec.from_node(target_node, scene_root),
		"target_created": target_created,
		"chain": chain,
		"pole_path": "" if pole == null else ValueCodec.from_node(pole, scene_root),
		"active": active,
		"warnings": warnings,
		"undoable": true,
	}
	if not active:
		data["active_note"] = "inactive: an active IK modifier also drives the skeleton while you edit the scene - pass active=true (or enable the modifier) when it is ready"
	return {"data": data}


# ============================================================================
# spring_setup
# ============================================================================

## Attach a SpringBoneSimulator3D to a Skeleton3D, one spring setting per entry
## in `springs`. Created inactive unless active=true.
func spring_setup(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"spring_setup supports Skeleton3D (SpringBoneSimulator3D); 2D jiggle bones live on the Experimental SkeletonModificationStack2D and are not supported yet")
	var springs: Array = params.get("springs", [])
	if springs.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"spring_setup needs 'springs': [{root_bone, end_bone?, stiffness?, drag?, gravity?, radius?, rotation_axis?, collisions?}]")
	var scene_root := EditorInterface.get_edited_scene_root()
	var skeleton: Skeleton3D = resolved.node
	var warnings: Array = []
	var scale := _skeleton_scale(skeleton)
	if not is_equal_approx(scale, 1.0):
		warnings.append("the skeleton is scaled (%.2f): spring bones assume unit scale and may misbehave" % scale)
	var planned: Array = []
	for index in springs.size():
		if not (springs[index] is Dictionary):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "springs[%d] must be an object" % index)
		var spring: Dictionary = springs[index]
		var root_name := str(spring.get("root_bone", ""))
		if root_name.is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "springs[%d] needs 'root_bone'" % index)
		var root_index := skeleton.find_bone(root_name)
		if root_index < 0:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"springs[%d]: bone '%s' not found" % [index, root_name])
		var end_name := str(spring.get("end_bone", ""))
		if end_name.is_empty():
			end_name = _last_descendant(skeleton, root_index)
			warnings.append("springs[%d]: no end_bone, using the leaf '%s'" % [index, end_name])
		elif skeleton.find_bone(end_name) < 0:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"springs[%d]: end bone '%s' not found" % [index, end_name])
		if spring.has("rotation_axis"):
			var axis := _rotation_axis(str(spring.rotation_axis))
			if axis < 0:
				return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
					"springs[%d]: invalid rotation_axis '%s'. Valid: x, y, z, all, custom" % [index, str(spring.rotation_axis)])
		if spring.has("center_from"):
			var center := _spring_center_from(str(spring.center_from))
			if center < 0:
				return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
					"springs[%d]: invalid center_from '%s'. Valid: world_origin, node, bone" % [index, str(spring.center_from)])
		var collisions: Array = []
		for path in spring.get("collisions", []):
			var collider := ValueCodec.resolve_scene_path(str(path), scene_root)
			if collider == null:
				return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
					"springs[%d]: collision %s" % [index, ValueCodec.format_node_error(str(path), scene_root)])
			collisions.append(str(skeleton.get_path_to(collider)))
		var exclude: Array = []
		for path in spring.get("exclude_collisions", []):
			var excluded := ValueCodec.resolve_scene_path(str(path), scene_root)
			if excluded == null:
				return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
					"springs[%d]: exclude collision %s" % [index, ValueCodec.format_node_error(str(path), scene_root)])
			exclude.append(str(skeleton.get_path_to(excluded)))
		planned.append({
			"spec": spring, "root": root_name, "end": end_name,
			"collisions": collisions, "exclude": exclude,
		})
	var active := bool(params.get("active", false))
	var simulator := SpringBoneSimulator3D.new()
	simulator.name = str(params.get("name", "SpringBones"))
	var setup: Array = [{"property": "active", "value": active}]
	setup.append({"method": "set_setting_count", "args": [planned.size()]})
	if params.has("mutable_bone_axes"):
		setup.append({"method": "set_mutable_bone_axes", "args": [bool(params.mutable_bone_axes)]})
	for index in planned.size():
		var entry: Dictionary = planned[index]
		var spec: Dictionary = entry.spec
		setup.append({"method": "set_root_bone_name", "args": [index, str(entry.root)]})
		setup.append({"method": "set_end_bone_name", "args": [index, str(entry.end)]})
		if spec.has("stiffness"):
			setup.append({"method": "set_stiffness", "args": [index, float(spec.stiffness)]})
		if spec.has("drag"):
			setup.append({"method": "set_drag", "args": [index, float(spec.drag)]})
		if spec.has("gravity"):
			setup.append({"method": "set_gravity", "args": [index, float(spec.gravity)]})
		if spec.has("radius"):
			setup.append({"method": "set_radius", "args": [index, float(spec.radius)]})
		if spec.has("rotation_axis"):
			setup.append({"method": "set_rotation_axis", "args": [index, _rotation_axis(str(spec.rotation_axis))]})
		if spec.has("rotation_axis_vector"):
			setup.append({"method": "set_rotation_axis_vector", "args": [index, _spec_vector3(spec.rotation_axis_vector, Vector3.UP)]})
		if spec.has("gravity_direction"):
			setup.append({"method": "set_gravity_direction", "args": [index, _spec_vector3(spec.gravity_direction, Vector3.DOWN)]})
		if spec.has("center_from"):
			setup.append({"method": "set_center_from", "args": [index, _spring_center_from(str(spec.center_from))]})
		if spec.has("center_bone"):
			setup.append({"method": "set_center_bone_name", "args": [index, str(spec.center_bone)]})
		if spec.has("center_node"):
			var center_node := ValueCodec.resolve_scene_path(str(spec.center_node), scene_root)
			if center_node == null:
				return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
					"springs[%d]: center node %s" % [index, ValueCodec.format_node_error(str(spec.center_node), scene_root)])
			setup.append({"method": "set_center_node", "args": [index, NodePath(str(skeleton.get_path_to(center_node)))]})
		if spec.has("enable_all_child_collisions"):
			setup.append({"method": "set_enable_all_child_collisions", "args": [index, bool(spec.enable_all_child_collisions)]})
		if not entry.collisions.is_empty():
			setup.append({"method": "set_collision_count", "args": [index, (entry.collisions as Array).size()]})
			for collision_index in (entry.collisions as Array).size():
				setup.append({"method": "set_collision_path", "args": [index, collision_index, NodePath(str(entry.collisions[collision_index]))]})
		if not entry.exclude.is_empty():
			setup.append({"method": "set_exclude_collision_count", "args": [index, (entry.exclude as Array).size()]})
			for collision_index in (entry.exclude as Array).size():
				setup.append({"method": "set_exclude_collision_path", "args": [index, collision_index, NodePath(str(entry.exclude[collision_index]))]})
	_commit_node_add("MCP: Spring bones (%d)" % planned.size(), skeleton, simulator, setup)
	var data := {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"modifier_class": "SpringBoneSimulator3D",
		"modifier_path": ValueCodec.from_node(simulator, scene_root),
		"spring_count": planned.size(),
		"springs": planned.map(func(entry): return {"root_bone": str(entry.root), "end_bone": str(entry.end)}),
		"active": active,
		"warnings": warnings,
		"undoable": true,
	}
	if not active:
		data["active_note"] = "inactive: an active spring simulator also drives the skeleton while you edit the scene - pass active=true (or enable the modifier) when it is ready"
	return {"data": data}


# ============================================================================
# look_at_setup
# ============================================================================

## Attach a LookAtModifier3D to a Skeleton3D so one bone tracks a target node.
func look_at_setup(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"look_at_setup supports Skeleton3D (LookAtModifier3D); the 2D look-at modification lives on the Experimental SkeletonModificationStack2D and is not supported yet")
	var bone_name := str(params.get("bone", ""))
	if bone_name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"look_at_setup needs 'bone': the bone that should track the target")
	var scene_root := EditorInterface.get_edited_scene_root()
	var skeleton: Skeleton3D = resolved.node
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Bone '%s' not found on %s" % [bone_name, resolved.path])
	var forward_spec := str(params.get("forward_axis", "+z"))
	var forward := _bone_axis(forward_spec)
	if forward < 0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid forward_axis '%s'. Valid: +x, -x, +y, -y, +z, -z" % forward_spec)
	var warnings: Array = []
	var scale := _skeleton_scale(skeleton)
	if not is_equal_approx(scale, 1.0):
		warnings.append("the skeleton is scaled (%.2f): look-at assumes unit scale" % scale)
	var target_path := str(params.get("target_path", ""))
	var target: Node3D = null
	if not target_path.is_empty():
		var found := ValueCodec.resolve_scene_path(target_path, scene_root)
		if found == null:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(target_path, scene_root))
		if not (found is Node3D):
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"The look-at target must be a Node3D (got %s)" % found.get_class())
		target = found
	var bone_pose := skeleton.get_bone_global_pose(bone_index)
	var ahead := bone_pose.basis * _bone_axis_vector(forward) * 1.0
	var target_created := false
	var entries: Array = []
	var target_node: Node3D = target
	if target_node == null:
		var marker := Marker3D.new()
		marker.name = str(params.get("target_name", "LookAtTarget"))
		entries.append({"parent": scene_root, "node": marker,
			"setup": [{"method": "set_global_position", "args": [skeleton.global_transform * (bone_pose.origin + ahead)]}]})
		target_node = marker
		target_created = true
	var active := bool(params.get("active", false))
	var modifier := LookAtModifier3D.new()
	modifier.name = str(params.get("name", "LookAt"))
	var target_rel := str(skeleton.get_path_to(target_node))
	if target_rel.is_empty():
		target_rel = "."
	var setup: Array = [
		{"property": "active", "value": active},
		{"method": "set_bone_name", "args": [bone_name]},
		{"method": "set_target_node", "args": [NodePath(target_rel)]},
		{"method": "set_forward_axis", "args": [forward]},
	]
	if params.has("origin_from"):
		var origin_from := _look_at_origin_from(str(params.origin_from))
		if origin_from < 0:
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Invalid origin_from '%s'. Valid: self, bone, external_node" % str(params.origin_from))
		setup.append({"method": "set_origin_from", "args": [origin_from]})
	if params.has("origin_bone"):
		var origin_bone := str(params.origin_bone)
		if skeleton.find_bone(origin_bone) < 0:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"origin_bone '%s' not found on %s" % [origin_bone, resolved.path])
		setup.append({"method": "set_origin_bone_name", "args": [origin_bone]})
	if params.has("origin_node"):
		var origin_node := ValueCodec.resolve_scene_path(str(params.origin_node), scene_root)
		if origin_node == null:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
				"origin_node %s" % ValueCodec.format_node_error(str(params.origin_node), scene_root))
		setup.append({"method": "set_origin_external_node", "args": [NodePath(str(skeleton.get_path_to(origin_node)))]})
	if params.has("origin_offset"):
		setup.append({"method": "set_origin_offset", "args": [_spec_vector3(params.origin_offset)]})
	if params.has("origin_safe_margin"):
		setup.append({"method": "set_origin_safe_margin", "args": [float(params.origin_safe_margin)]})
	if bool(params.get("use_angle_limitation", false)):
		setup.append({"method": "set_use_angle_limitation", "args": [true]})
		if params.has("primary_limit_angle"):
			setup.append({"method": "set_primary_limit_angle", "args": [float(params.primary_limit_angle)]})
		if params.has("secondary_limit_angle"):
			setup.append({"method": "set_secondary_limit_angle", "args": [float(params.secondary_limit_angle)]})
	if bool(params.get("use_secondary_rotation", false)):
		setup.append({"method": "set_use_secondary_rotation", "args": [true]})
	if params.has("primary_axis"):
		var primary := _vector_axis(str(params.primary_axis))
		if primary < 0:
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Invalid primary_axis '%s'. Valid: x, y, z" % str(params.primary_axis))
		setup.append({"method": "set_primary_rotation_axis", "args": [primary]})
	if bool(params.get("relative", false)):
		setup.append({"method": "set_relative", "args": [true]})
	if params.has("duration"):
		setup.append({"method": "set_duration", "args": [float(params.duration)]})
	entries.append({"parent": skeleton, "node": modifier, "setup": setup})
	_commit_node_add_many("MCP: Look-at setup", entries)
	var data := {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"modifier_class": "LookAtModifier3D",
		"modifier_path": ValueCodec.from_node(modifier, scene_root),
		"bone": bone_name,
		"forward_axis": forward_spec,
		"target_path": ValueCodec.from_node(target_node, scene_root),
		"target_created": target_created,
		"active": active,
		"warnings": warnings,
		"undoable": true,
	}
	if not active:
		data["active_note"] = "inactive: an active look-at modifier also drives the skeleton while you edit the scene - pass active=true (or enable the modifier) when it is ready"
	return {"data": data}


# ============================================================================
# retarget_setup
# ============================================================================

## Attach a RetargetModifier3D under a source Skeleton3D so a child target
## skeleton follows its poses in model space (different rests are fine).
func retarget_setup(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"retarget_setup supports Skeleton3D (RetargetModifier3D)")
	var scene_root := EditorInterface.get_edited_scene_root()
	var source: Skeleton3D = resolved.node
	var target_path := str(params.get("target_path", ""))
	if target_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"retarget_setup needs 'target_path': the Skeleton3D that receives the poses")
	var found := ValueCodec.resolve_scene_path(target_path, scene_root)
	if found == null:
		return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(target_path, scene_root))
	if not (found is Skeleton3D):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"The retarget target must be a Skeleton3D (got %s)" % found.get_class())
	var target: Skeleton3D = found
	if target == source:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The target skeleton cannot be the source skeleton")
	if source.is_ancestor_of(target):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The target skeleton is already inside the source skeleton (%s)" % target_path)
	var resolved_profile := _resolve_retarget_profile(params, source, target)
	if resolved_profile.has("error"):
		return resolved_profile
	# The modifier lives under the source skeleton and the target moves under the
	# modifier, so both have to be scene-owned: inside a non-editable instance
	# the editor would drop the new nodes (and can free them again) on save/undo.
	var source_levels := _instance_levels(source)
	if not source_levels.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The source skeleton lives inside the instanced scene '%s' and that instance is not editable, so the retarget modifier would not survive the scene save - enable Editable Children on it, or use a skeleton that belongs to the edited scene" % str(source_levels[0].instance.scene_file_path))
	var profile: SkeletonProfile = resolved_profile.profile
	var warnings: Array = []
	if not (resolved_profile.unmapped as Array).is_empty():
		warnings.append("%d of %d profile bones are not in both skeletons and will not retarget: %s" % [
			(resolved_profile.unmapped as Array).size(), profile.get_bone_size(),
			", ".join((resolved_profile.unmapped as Array).slice(0, 8))])
	var scale := _skeleton_scale(source)
	if not is_equal_approx(scale, 1.0):
		warnings.append("the source skeleton is scaled (%.2f): retargeting assumes unit scale" % scale)
	var flags := 0
	if bool(params.get("position", false)):
		flags |= RetargetModifier3D.TRANSFORM_FLAG_POSITION
	if bool(params.get("rotation", true)):
		flags |= RetargetModifier3D.TRANSFORM_FLAG_ROTATION
	if bool(params.get("scale", false)):
		flags |= RetargetModifier3D.TRANSFORM_FLAG_SCALE
	if flags == 0:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Enable at least one of position/rotation/scale (rotation is on by default)")
	var active := bool(params.get("active", false))
	var move_target := bool(params.get("move_target", true))
	var already_under_modifier := target.get_parent() is RetargetModifier3D and source.is_ancestor_of(target)
	if not already_under_modifier and not move_target:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The target skeleton must be a child of the RetargetModifier3D. Pass move_target=true to move it there, or parent it under a RetargetModifier3D yourself.")
	if move_target and not already_under_modifier and not _instance_levels(target).is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The target skeleton lives inside an instanced scene, so moving it would not survive the scene save - move it into the edited scene first (or pass move_target=false and parent it yourself)")
	var modifier := RetargetModifier3D.new()
	modifier.name = str(params.get("name", "Retarget"))
	var setup: Array = [
		{"property": "active", "value": active},
		{"property": "profile", "value": profile},
		{"method": "set_enable_flags", "args": [flags]},
		{"method": "set_use_global_pose", "args": [bool(params.get("use_global_pose", false))]},
	]
	if not _dry_run:
		_create_scene_pinned_action("MCP: Retarget setup")
		var undo := ToolContext.undo_redo
		undo.add_do_method(source, "add_child", modifier, true)
		undo.add_do_method(modifier, "set_owner", scene_root)
		undo.add_do_reference(modifier)
		undo.add_do_reference(profile)
		for call in setup:
			if call.has("property"):
				undo.add_do_property(modifier, call.property, call.value)
			else:
				_add_do_call(undo, modifier, call.method, call.get("args", []))
		if move_target and not already_under_modifier:
			var old_parent := target.get_parent()
			undo.add_do_method(target, "reparent", modifier, true)
			# Undo methods run in registration order, so the target goes back to
			# its old parent before the modifier (its current parent) is removed.
			undo.add_undo_method(target, "reparent", old_parent, true)
			undo.add_undo_method(source, "remove_child", modifier)
		else:
			undo.add_undo_method(source, "remove_child", modifier)
		undo.commit_action()
	var data := {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"modifier_class": "RetargetModifier3D",
		"modifier_path": ValueCodec.from_node(modifier, scene_root),
		"target_path": ValueCodec.from_node(target, scene_root),
		"moved_target": move_target and not already_under_modifier,
		"profile_source": str(resolved_profile.source),
		"profile_bones": profile.get_bone_size(),
		"mapped_bones": (resolved_profile.mapped as Array).size(),
		"unmapped_bones": resolved_profile.unmapped,
		"enable_flags": flags,
		"use_global_pose": bool(params.get("use_global_pose", false)),
		"active": active,
		"warnings": warnings,
		"undoable": true,
	}
	if not active:
		data["active_note"] = "inactive: an active retarget modifier also drives the target while you edit the scene - pass active=true (or enable the modifier) when it is ready"
	return {"data": data}


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


# --- chain spec helpers -----------------------------------------------------

## Validate a bone spec: unique names, known parents (in the spec or already on
## the skeleton), no parent cycles.
static func _validate_bone_spec(spec: Array, existing_names: Dictionary = {}) -> Dictionary:
	var names: Array = []
	for index in spec.size():
		if not (spec[index] is Dictionary):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "bones[%d] must be an object" % index)
		var name := str((spec[index] as Dictionary).get("name", ""))
		if name.is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "bones[%d] needs a 'name'" % index)
		if names.has(name):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Duplicate bone name '%s'" % name)
		names.append(name)
	for index in spec.size():
		var bone: Dictionary = spec[index]
		var bone_name := str(bone.name)
		var parent_name := str(bone.get("parent", ""))
		if parent_name.is_empty():
			continue
		if not names.has(parent_name) and not existing_names.has(parent_name):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"bones[%d] ('%s') has unknown parent '%s'" % [index, bone_name, parent_name])
		var cursor := parent_name
		var hops := 0
		while not cursor.is_empty() and hops <= names.size():
			if cursor == bone_name:
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"bones[%d] ('%s') has a parent cycle" % [index, bone_name])
			if existing_names.has(cursor):
				break
			var entry := _spec_entry(spec, cursor)
			cursor = str(entry.get("parent", "")) if not entry.is_empty() else ""
			hops += 1
	return {"names": names}


static func _spec_entry(spec: Array, name: String) -> Dictionary:
	for entry in spec:
		if str((entry as Dictionary).get("name", "")) == name:
			return entry
	return {}


## Bone rest from a spec entry: position/scale as arrays or dicts, rotation in
## degrees (3D: XYZ euler, 2D: about Z).
static func _spec_rest_3d(bone: Dictionary) -> Transform3D:
	var origin := _spec_vector3(bone.get("position", null))
	var rotation := _spec_vector3(bone.get("rotation", null))
	var scale := _spec_vector3(bone.get("scale", null), Vector3.ONE)
	return Transform3D(Basis.from_euler(rotation * (PI / 180.0)).scaled(scale), origin)


static func _spec_rest_2d(bone: Dictionary) -> Transform2D:
	return Transform2D(deg_to_rad(_spec_rotation_2d(bone)), _spec_vector2(bone.get("position", null)))


static func _spec_rotation_2d(bone: Dictionary) -> float:
	var value = bone.get("rotation", null)
	if value == null:
		return 0.0
	if value is float or value is int:
		return float(value)
	return _spec_vector3(value).z


static func _spec_vector3(value, fallback := Vector3.ZERO) -> Vector3:
	if value == null:
		return fallback
	if value is Vector3:
		return value
	if value is Array:
		var parts: Array = value
		return Vector3(
			float(parts[0]) if parts.size() > 0 else fallback.x,
			float(parts[1]) if parts.size() > 1 else fallback.y,
			float(parts[2]) if parts.size() > 2 else fallback.z)
	if value is Dictionary:
		return Vector3(
			float((value as Dictionary).get("x", fallback.x)),
			float((value as Dictionary).get("y", fallback.y)),
			float((value as Dictionary).get("z", fallback.z)))
	return fallback


static func _spec_vector2(value, fallback := Vector2.ZERO) -> Vector2:
	if value == null:
		return fallback
	if value is Vector2:
		return value
	if value is Array:
		var parts: Array = value
		return Vector2(
			float(parts[0]) if parts.size() > 0 else fallback.x,
			float(parts[1]) if parts.size() > 1 else fallback.y)
	if value is Dictionary:
		return Vector2(
			float((value as Dictionary).get("x", fallback.x)),
			float((value as Dictionary).get("y", fallback.y)))
	return fallback


## Setup calls for one Bone2D: rest (and its pose), manual length.
static func _bone_2d_setup(bone: Dictionary) -> Array:
	var rest := _spec_rest_2d(bone)
	return [
		{"property": "rest", "value": rest},
		{"property": "position", "value": rest.get_origin()},
		{"property": "rotation", "value": rest.get_rotation()},
		{"method": "set_autocalculate_length_and_angle", "args": [false]},
		{"method": "set_length", "args": [float(bone.get("length", 32.0))]},
	]


## Local transform of a subtree node, in the shape the bone spec takes.
static func _node_offset(node: Node, kind: String) -> Variant:
	if kind == "2d" and node is Node2D:
		return (node as Node2D).position
	if node is Node3D:
		return (node as Node3D).position
	return Vector3.ZERO


static func _node_rotation(node: Node, kind: String) -> Variant:
	if kind == "2d" and node is Node2D:
		return (node as Node2D).rotation_degrees
	if node is Node3D:
		return (node as Node3D).rotation_degrees
	return Vector3.ZERO


## World position of a 3D chain's tip: the end bone's first child, or a 10 cm
## virtual tip along the bone when it has no child.
func _bone_tip_3d(skeleton: Skeleton3D, bone_index: int) -> Dictionary:
	var children := skeleton.get_bone_children(bone_index)
	if not children.is_empty():
		var child_pose := skeleton.get_bone_global_pose(children[0])
		return {"position": skeleton.global_transform * child_pose.origin, "warning": null}
	var pose := skeleton.get_bone_global_pose(bone_index)
	var tip := pose.origin + pose.basis.y.normalized() * 0.1
	return {
		"position": skeleton.global_transform * tip,
		"warning": "the end bone '%s' has no child bone, so the target uses a 10 cm virtual tip - move it where it belongs" % skeleton.get_bone_name(bone_index),
	}


# --- modifier enum helpers --------------------------------------------------

## "x" / "y" / "z" / "all" / "custom" -> SkeletonModifier3D.RotationAxis, or -1.
static func _rotation_axis(value: String) -> int:
	match value.to_lower():
		"x": return SkeletonModifier3D.ROTATION_AXIS_X
		"y": return SkeletonModifier3D.ROTATION_AXIS_Y
		"z": return SkeletonModifier3D.ROTATION_AXIS_Z
		"all": return SkeletonModifier3D.ROTATION_AXIS_ALL
		"custom": return SkeletonModifier3D.ROTATION_AXIS_CUSTOM
	return -1


## "world_origin" / "node" / "bone" -> SpringBoneSimulator3D.CenterFrom, or -1.
static func _spring_center_from(value: String) -> int:
	match value.to_lower():
		"world_origin": return SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN
		"node": return SpringBoneSimulator3D.CENTER_FROM_NODE
		"bone": return SpringBoneSimulator3D.CENTER_FROM_BONE
	return -1


## "+x" / "-y" ... -> SkeletonModifier3D.BoneAxis, or -1.
static func _bone_axis(value: String) -> int:
	match value.to_lower().replace(" ", ""):
		"+x": return SkeletonModifier3D.BONE_AXIS_PLUS_X
		"-x": return SkeletonModifier3D.BONE_AXIS_MINUS_X
		"+y": return SkeletonModifier3D.BONE_AXIS_PLUS_Y
		"-y": return SkeletonModifier3D.BONE_AXIS_MINUS_Y
		"+z": return SkeletonModifier3D.BONE_AXIS_PLUS_Z
		"-z": return SkeletonModifier3D.BONE_AXIS_MINUS_Z
	return -1


static func _bone_axis_vector(axis: int) -> Vector3:
	match axis:
		SkeletonModifier3D.BONE_AXIS_PLUS_X: return Vector3.RIGHT
		SkeletonModifier3D.BONE_AXIS_MINUS_X: return Vector3.LEFT
		SkeletonModifier3D.BONE_AXIS_PLUS_Y: return Vector3.UP
		SkeletonModifier3D.BONE_AXIS_MINUS_Y: return Vector3.DOWN
		SkeletonModifier3D.BONE_AXIS_PLUS_Z: return Vector3.BACK
		SkeletonModifier3D.BONE_AXIS_MINUS_Z: return Vector3.FORWARD
	return Vector3.BACK


## "self" / "bone" / "external_node" -> LookAtModifier3D.OriginFrom, or -1.
static func _look_at_origin_from(value: String) -> int:
	match value.to_lower():
		"self": return LookAtModifier3D.ORIGIN_FROM_SELF
		"bone": return LookAtModifier3D.ORIGIN_FROM_SPECIFIC_BONE
		"external_node": return LookAtModifier3D.ORIGIN_FROM_EXTERNAL_NODE
	return -1


## "x" / "y" / "z" -> Vector3.Axis, or -1.
static func _vector_axis(value: String) -> int:
	match value.to_lower():
		"x": return Vector3.AXIS_X
		"y": return Vector3.AXIS_Y
		"z": return Vector3.AXIS_Z
	return -1


## Deepest last child of a bone (the natural spring end when none is given).
static func _last_descendant(skeleton: Skeleton3D, bone_index: int) -> String:
	var current := bone_index
	while true:
		var children := skeleton.get_bone_children(current)
		if children.is_empty():
			break
		current = children[children.size() - 1]
	return skeleton.get_bone_name(current)


## Build or load the SkeletonProfile a retarget modifier matches bones by, and
## report which of its bones exist in both skeletons.
func _resolve_retarget_profile(params: Dictionary, source: Skeleton3D, target: Skeleton3D) -> Dictionary:
	var spec := str(params.get("profile", "auto"))
	var profile: SkeletonProfile = null
	var profile_source := spec
	if spec.is_empty() or spec == "auto":
		profile = SkeletonProfile.new()
		var count := source.get_bone_count()
		profile.set_bone_size(count)
		var root_name := ""
		for index in count:
			var bone_name := source.get_bone_name(index)
			profile.set_bone_name(index, bone_name)
			var parent_index := source.get_bone_parent(index)
			profile.set_bone_parent(index, "" if parent_index < 0 else source.get_bone_name(parent_index))
			if parent_index < 0 and root_name.is_empty():
				root_name = bone_name
		if not root_name.is_empty():
			profile.set_root_bone(root_name)
			profile.set_scale_base_bone(root_name)
		profile_source = "auto"
	elif spec == "humanoid":
		if not ClassDB.can_instantiate("SkeletonProfileHumanoid"):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"SkeletonProfileHumanoid is not available in this Godot build")
		profile = ClassDB.instantiate("SkeletonProfileHumanoid")
		profile_source = "humanoid"
	elif spec.begins_with("res://"):
		if not ResourceLoader.exists(spec):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Profile not found: %s" % spec)
		var loaded = load(spec)
		if not (loaded is SkeletonProfile):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "%s is not a SkeletonProfile" % spec)
		profile = loaded
	else:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid profile '%s'. Valid: auto, humanoid, or a res:// path to a SkeletonProfile" % spec)
	var mapped: Array = []
	var unmapped: Array = []
	for index in profile.get_bone_size():
		var bone_name := str(profile.get_bone_name(index))
		if source.find_bone(bone_name) >= 0 and target.find_bone(bone_name) >= 0:
			mapped.append(bone_name)
		else:
			unmapped.append(bone_name)
	return {"profile": profile, "source": profile_source, "mapped": mapped, "unmapped": unmapped}
