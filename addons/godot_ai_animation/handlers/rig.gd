@tool
extends "res://addons/godot_ai_animation/handlers/bone_animation.gd"

## Rig authoring — the `animation_rig` tool.
##
## Phase 6a: poses. Capture a skeleton's pose as portable rest-relative data,
## apply/blend/mirror poses, keyframe poses into clips, and inspect rigs. Bone
## clips are ordinary 3D transform tracks (`Skeleton3D:bone`) or 2D value tracks
## (`Skeleton2D/Bone:rotation`), so every existing toolkit op works on them.

const PoseMath := preload("res://addons/godot_ai_animation/spec/pose_math.gd")
const PoseSolver := preload("res://addons/godot_ai_animation/spec/pose_solver.gd")
const SpineTwist := preload("res://addons/godot_ai_animation/spec/spine_twist.gd")
const SpecJson := preload("res://addons/godot_ai_animation/spec/spec_json.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const POSE_DIR := "res://animation_toolkit/poses"
## bake_pose_sequence cost is duration * fps samples, each a full skeleton
## update; a runaway bake would sit past the tool timeout, so it is refused.
const MAX_BAKE_SAMPLES := 1200


## Rollup entry registered with the Godot AI tool registry.
func run(params: Dictionary, ctx) -> Dictionary:
	_dry_run = bool(params.get("dry_run", false))
	var result := _dispatch(params, ctx)
	if _dry_run and result.has("data"):
		result.data["dry_run"] = true
		result.data["undoable"] = false
	return result


func _dispatch(params: Dictionary, ctx = null) -> Dictionary:
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
		"twist_setup":
			return twist_setup(params, ctx)
		"walk_cycle":
			return walk_cycle(params)
		"idle_breathing":
			return idle_breathing(params)
		"blink":
			return blink(params)
		"jumping_jack":
			return jumping_jack(params)
		"squat":
			return squat(params)
		"punch":
			return punch(params)
		"bake_pose_sequence":
			return bake_pose_sequence(params)
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
	var contacts: Array = []
	var length := 0.0
	for index in keys.size():
		var key: Dictionary = keys[index]
		var key_params: Dictionary = key.duplicate()
		if not key_params.has("pose_dir"):
			key_params["pose_dir"] = params.get("pose_dir", "")
		# An aim-only key defaults to a rest pose over its chain bones.
		if key.get("aim", null) != null and not key_params.has("pose") \
				and not key_params.has("name") and not key_params.has("path"):
			var base := PoseMath.make_pose()
			for aim in key.aim:
				if not (aim is Dictionary):
					continue
				for bone in (aim as Dictionary).get("chain", []):
					PoseMath.set_bone(base, str(bone), Quaternion.IDENTITY, Vector3.ZERO, Vector3.ONE)
			if PoseMath.bone_count(base) > 0:
				key_params["pose"] = PoseMath.to_json(base)
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
		var aimed := _apply_aims(resolved, pose, key.get("aim", []))
		if aimed.has("error"):
			return ErrorCodes.make(aimed.error.code,
				"keys[%d]: %s" % [index, str(aimed.error.message)])
		pose = aimed.pose
		for contact in aimed.get("contacts", []):
			contact["time"] = time
			contacts.append(contact)
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
		"aim_contacts": contacts.size(),
		"aim_clamped": contacts.any(func(contact): return bool(contact.clamped)),
		"contacts": contacts,
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
	var twists: Array = []
	for child in resolved.node.get_children():
		if child is SkeletonModifier3D:
			var modifier := child as SkeletonModifier3D
			modifiers.append({
				"name": str(modifier.name),
				"type": modifier.get_class(),
				"active": modifier.active,
				"influence": modifier.influence,
			})
			# Godot builds a disperser's per-joint list on the frame after the
			# modifier enters the tree, so this is where the real list is read
			# back - twist_setup can only report the predicted one.
			if modifier is BoneTwistDisperser3D:
				var disperser := modifier as BoneTwistDisperser3D
				for setting in disperser.get_setting_count():
					var joints: Array = []
					for joint in disperser.get_joint_count(setting):
						joints.append(str(disperser.get_joint_bone_name(setting, joint)))
					twists.append({
						"modifier": str(disperser.name),
						"setting": setting,
						"root_bone": str(disperser.get_root_bone_name(setting)),
						"end_bone": str(disperser.get_end_bone_name(setting)),
						"mode": disperser.get_disperse_mode(setting),
						"joint_count": joints.size(),
						"joint_bones": joints,
						# Godot resolves the bone names into a joint list on a
						# deferred frame, so a freshly added disperser reports an
						# empty list until one has passed.
						"joints_pending": joints.is_empty(),
						"extend_end_bone": disperser.is_end_bone_extended(setting),
						"twist_from_rest": disperser.is_twist_from_rest(setting),
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
		"twist_settings": twists,
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
	var scene_root := EditorInterface.get_edited_scene_root()
	var skeleton: Skeleton3D = resolved.node
	var chain_error := _ik_chain_error(skeleton, chain, kind, use_virtual_end)
	if not chain_error.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, chain_error)
	if kind == "spline":
		return _ik_setup_spline(skeleton, scene_root, params, chain)
	var warnings: Array = []
	var scale := _skeleton_scale(skeleton)
	if not is_equal_approx(scale, 1.0):
		warnings.append("the skeleton is scaled (%.2f): IK assumes unit scale" % scale)
	var taken_names := {}
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
	var end_index := skeleton.find_bone(str(chain[chain.size() - 1]))
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
	var pole_created := false
	var pole_entries: Array = []
	var pole_direction := Vector3.ZERO
	if kind == "two_bone" and pole == null:
		# TwoBoneIK3D requires a pole target: without one it solves nothing.
		# Default it to a point behind the middle joint (Godot's humanoid
		# convention faces +Z), projected perpendicular to the chain.
		var root_index := skeleton.find_bone(str(chain[0]))
		var middle_index := skeleton.find_bone(str(chain[1]))
		var root_pose := skeleton.get_bone_global_rest(root_index)
		var middle_pose := skeleton.get_bone_global_rest(middle_index)
		var end_pose := skeleton.get_bone_global_rest(end_index)
		var chain_dir := end_pose.origin - root_pose.origin
		if chain_dir.length() < 0.001:
			chain_dir = middle_pose.basis.y
		chain_dir = chain_dir.normalized()
		var back := Vector3(0, 0, -1)
		var side := back - chain_dir * back.dot(chain_dir)
		if side.length() < 0.001:
			side = middle_pose.basis.x
		side = side.normalized()
		var pole_position := middle_pose.origin + side * 0.5
		pole_direction = (middle_pose.basis.inverse() * side).normalized()
		var marker := Marker3D.new()
		marker.name = _unique_child_name(scene_root, str(params.get("pole_name", "IKPole")), taken_names)
		pole_entries.append({"parent": scene_root, "node": marker,
			"setup": [{"method": "set_global_position", "args": [skeleton.global_transform * pole_position]}]})
		pole = marker
		pole_created = true
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
		marker.name = _unique_child_name(scene_root, str(params.get("target_name", "IKTarget")), taken_names)
		entries.append({"parent": scene_root, "node": marker,
			"setup": [{"method": "set_global_position", "args": [tip.position]}]})
		target_node = marker
		target_created = true
	var setup: Array = [{"property": "active", "value": active}]
	var target_rel := _modifier_target_path(skeleton, modifier, target_node, scene_root)
	setup.append({"method": "set_setting_count", "args": [1]})
	setup.append({"method": "set_root_bone_name", "args": [0, str(chain[0])]})
	if kind == "two_bone":
		setup.append({"method": "set_middle_bone_name", "args": [0, str(chain[1])]})
		if use_virtual_end:
			setup.append({"method": "set_use_virtual_end", "args": [0, true]})
			setup.append({"method": "set_extend_end_bone", "args": [0, true]})
			setup.append({"method": "set_end_bone_length", "args": [0, float(params.get("end_bone_length", 0.1))]})
		else:
			setup.append({"method": "set_end_bone_name", "args": [0, str(chain[2])]})
		if pole != null:
			setup.append({"method": "set_pole_node", "args": [0, _modifier_target_path(skeleton, modifier, pole, scene_root)]})
			if pole_created:
				setup.append({"method": "set_pole_direction", "args": [0, SkeletonModifier3D.SECONDARY_DIRECTION_CUSTOM]})
				setup.append({"method": "set_pole_direction_vector", "args": [0, pole_direction]})
	else:
		setup.append({"method": "set_end_bone_name", "args": [0, str(chain[chain.size() - 1])]})
	setup.append({"method": "set_target_node", "args": [0, target_rel]})
	var setup_error := _setup_calls_error(modifier, setup)
	if not setup_error.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, setup_error)
	# Markers first: the commit runs each entry's setup calls right after adding
	# it, so a pole wired before its Marker3D exists would make Godot warn
	# "Pole node not found" and leave the solver without a bend direction.
	entries.append_array(pole_entries)
	entries.append({"parent": skeleton, "node": modifier, "setup": setup})
	_commit_node_add_many("MCP: IK setup (%s)" % kind, entries)
	# Failsafe: the settings are readable once the action has run, so confirm the
	# modifier really points at the markers it was given.
	if not _dry_run:
		var wiring := _verify_setting_node(modifier, "get_target_node", [0], target_node)
		if wiring.is_empty() and pole != null:
			wiring = _verify_setting_node(modifier, "get_pole_node", [0], pole)
		if not wiring.is_empty():
			return _undo_and_fail(ErrorCodes.INVALID_PARAMS, wiring)
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
		"pole_created": pole_created,
		"active": active,
		"warnings": warnings,
		"undoable": true,
	}
	if not active:
		data["active_note"] = "inactive: an active IK modifier also drives the skeleton while you edit the scene - pass active=true (or enable the modifier) when it is ready"
	return {"data": data}


## ik_setup's chain contract: unique bone names that form the chain the solver
## will actually use. `two_bone` needs exactly three bones (or two with a
## virtual end) and each must be the direct parent of the next; the chain
## solvers take a root and an end and let Godot derive the joints between them,
## so those only have to be ancestor-ordered. "" means the chain is usable.
func _ik_chain_error(skeleton: Skeleton3D, chain: Array, kind: String, use_virtual_end: bool) -> String:
	var names: Array = []
	for bone_name in chain:
		var bone_str := str(bone_name)
		if names.has(bone_str):
			return "the chain repeats the bone '%s'" % bone_str
		if skeleton.find_bone(bone_str) < 0:
			return "bone '%s' not found on %s" % [bone_str, skeleton.get_path()]
		names.append(bone_str)
	if kind == "two_bone":
		var wanted := 2 if use_virtual_end else 3
		if names.size() != wanted:
			return ("two_bone IK needs exactly three bones [root, middle, end] (or two with "
				+ "use_virtual_end=true), got %d" % names.size())
		if not _is_bone_parent(skeleton, names[0], names[1]):
			return "'%s' is not the parent of '%s' - give the chain root to end" % [names[0], names[1]]
		if not use_virtual_end and not _is_bone_parent(skeleton, names[1], names[2]):
			return "'%s' is not the parent of '%s' - give the chain root to end" % [names[1], names[2]]
		return ""
	if names.size() < 2:
		return "%s IK needs a chain with at least a root and an end bone" % kind
	# Walk up from the end bone: the root has to be somewhere on its parent path.
	var root_str := str(names[0])
	var cursor := skeleton.find_bone(str(names[names.size() - 1]))
	while cursor >= 0 and skeleton.get_bone_name(cursor) != root_str:
		cursor = skeleton.get_bone_parent(cursor)
	if cursor < 0:
		return "'%s' is not a descendant of '%s' - give the chain root to end" % [str(names[names.size() - 1]), root_str]
	return ""


static func _is_bone_parent(skeleton: Skeleton3D, parent_name: String, child_name: String) -> bool:
	var child := skeleton.find_bone(child_name)
	return child >= 0 and skeleton.get_bone_parent(child) == skeleton.find_bone(parent_name)


## SplineIK3D is a ChainIK3D that follows a Path3D: its class chain
## (SplineIK3D -> ChainIK3D -> IKModifier3D) has no `set_target_node` at all, so
## the marker target the other solvers use would leave it unconfigured. It gets
## a path instead - the caller's `target_path`, or a straight two-point path
## created at the end bone so the modifier can solve straight away.
func _ik_setup_spline(skeleton: Skeleton3D, scene_root: Node, params: Dictionary, chain: Array) -> Dictionary:
	var warnings: Array = []
	var scale := _skeleton_scale(skeleton)
	if not is_equal_approx(scale, 1.0):
		warnings.append("the skeleton is scaled (%.2f): IK assumes unit scale" % scale)
	var taken_names := {}
	var entries: Array = []
	var path_node: Path3D = null
	var path_created := false
	var path_ref := str(params.get("target_path", ""))
	if not path_ref.is_empty():
		var found := ValueCodec.resolve_scene_path(path_ref, scene_root)
		if found == null:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(path_ref, scene_root))
		if not (found is Path3D):
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"spline IK follows a Path3D, not a %s - point target_path at a Path3D with a Curve3D" % found.get_class())
		# A path with no curve is a path the solver cannot follow, so refuse it
		# before anything is added to the scene.
		if (found as Path3D).curve == null or (found as Path3D).curve.point_count < 1:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"The Path3D '%s' has no curve points, so SplineIK3D would have nothing to follow - add points to its Curve3D first" % str(found.name))
		path_node = found
	if path_node == null:
		var tip := _bone_tip_3d(skeleton, skeleton.find_bone(str(chain[chain.size() - 1])))
		if tip.get("warning") != null:
			warnings.append(str(tip.warning))
		var root_pose: Transform3D = skeleton.get_bone_global_rest(skeleton.find_bone(str(chain[0])))
		var span: float = (tip.position - skeleton.global_transform * root_pose.origin).length()
		if span < 0.001:
			span = 0.1
		var curve := Curve3D.new()
		curve.add_point(Vector3.ZERO)
		curve.add_point(skeleton.global_transform.basis.z.normalized() * span)
		var created := Path3D.new()
		created.curve = curve
		created.name = _unique_child_name(scene_root, str(params.get("path_name", "IKPath")), taken_names)
		entries.append({"parent": scene_root, "node": created,
			"setup": [{"method": "set_global_position", "args": [tip.position]}]})
		path_node = created
		path_created = true
		warnings.append("created a straight path at the end bone - author a Curve3D on %s to steer the chain" % created.name)
	var modifier: SkeletonModifier3D = ClassDB.instantiate(IK_3D_KINDS["spline"])
	if modifier == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "SplineIK3D is not available in this Godot build")
	modifier.name = str(params.get("name", "IKSpline"))
	var active := bool(params.get("active", false))
	var setup: Array = [
		{"property": "active", "value": active},
		{"method": "set_setting_count", "args": [1]},
		{"method": "set_root_bone_name", "args": [0, str(chain[0])]},
		{"method": "set_end_bone_name", "args": [0, str(chain[chain.size() - 1])]},
		{"method": "set_path_3d", "args": [0, _modifier_target_path(skeleton, modifier, path_node, scene_root)]},
	]
	var setup_error := _setup_calls_error(modifier, setup)
	if not setup_error.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, setup_error)
	entries.append({"parent": skeleton, "node": modifier, "setup": setup})
	_commit_node_add_many("MCP: IK setup (spline)", entries)
	# Failsafe: a spline solver needs both a path it can resolve and a curve with
	# something in it, so confirm both instead of reporting an inert modifier.
	if not _dry_run:
		var wiring := _verify_setting_node(modifier, "get_path_3d", [0], path_node)
		if not wiring.is_empty():
			return _undo_and_fail(ErrorCodes.INVALID_PARAMS, wiring)
		if (path_node as Path3D).curve == null or (path_node as Path3D).curve.point_count < 1:
			return _undo_and_fail(ErrorCodes.INVALID_PARAMS,
				"The path '%s' has no curve points, so the spline solver has nothing to follow"
					% str(path_node.name))
	var data := {
		"skeleton_path": str(skeleton.get_path()),
		"kind": "3d",
		"ik_kind": "spline",
		"modifier_class": IK_3D_KINDS["spline"],
		"modifier_path": ValueCodec.from_node(modifier, scene_root),
		"path_path": ValueCodec.from_node(path_node, scene_root),
		"path_created": path_created,
		"target_path": "",
		"target_created": false,
		"chain": chain,
		"pole_path": "",
		"pole_created": false,
		"active": active,
		"warnings": warnings,
		"undoable": true,
		"spline_note": "spline IK solves against a Path3D (target_path), not a marker target - SplineIK3D has no target setting",
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
			collisions.append({"node": collider, "path": _spring_path_to(skeleton, collider)})
		var exclude: Array = []
		for path in spring.get("exclude_collisions", []):
			var excluded := ValueCodec.resolve_scene_path(str(path), scene_root)
			if excluded == null:
				return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
					"springs[%d]: exclude collision %s" % [index, ValueCodec.format_node_error(str(path), scene_root)])
			exclude.append({"node": excluded, "path": _spring_path_to(skeleton, excluded)})
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
			setup.append({"method": "set_center_node",
				"args": [index, NodePath(_spring_path_to(skeleton, center_node))]})
		if spec.has("enable_all_child_collisions"):
			setup.append({"method": "set_enable_all_child_collisions", "args": [index, bool(spec.enable_all_child_collisions)]})
		if not entry.collisions.is_empty():
			setup.append({"method": "set_collision_count", "args": [index, (entry.collisions as Array).size()]})
			for collision_index in (entry.collisions as Array).size():
				setup.append({"method": "set_collision_path",
					"args": [index, collision_index, NodePath((entry.collisions as Array)[collision_index].path)]})
		if not entry.exclude.is_empty():
			setup.append({"method": "set_exclude_collision_count", "args": [index, (entry.exclude as Array).size()]})
			for collision_index in (entry.exclude as Array).size():
				setup.append({"method": "set_exclude_collision_path",
					"args": [index, collision_index, NodePath((entry.exclude as Array)[collision_index].path)]})
	_commit_node_add("MCP: Spring bones (%d)" % planned.size(), skeleton, simulator, setup)
	# Godot only uses a collision that is a child of the simulator, and this one
	# was just created, so the supplied collisions are moved under it (undoably,
	# keeping their world transform) instead of being wired as dead references.
	var moved_collisions: Array = []
	var undo := ToolContext.undo_redo
	for entry: Dictionary in planned:
		for kind_key in ["collisions", "exclude"]:
			for collision in entry.get(kind_key, []):
				var collider: Node = (collision as Dictionary).node
				if collider.get_parent() == simulator:
					continue
				var collider_parent := collider.get_parent()
				if collider_parent == null or not _instance_levels(collider_parent).is_empty():
					return _undo_and_fail(ErrorCodes.INVALID_PARAMS,
						"Collision '%s' lives inside an instanced scene, so moving it under the new SpringBoneSimulator3D would not survive the save - move it into the edited scene first"
							% str(collider.name))
				if _dry_run or undo == null:
					continue
				undo.add_do_method(collider, "reparent", simulator, true)
				undo.add_undo_method(collider, "reparent", collider_parent, true)
				moved_collisions.append(ValueCodec.from_node(collider, scene_root))
	if not moved_collisions.is_empty() and undo != null and not _dry_run:
		undo.commit_action()
	var data := {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"modifier_class": "SpringBoneSimulator3D",
		"modifier_path": ValueCodec.from_node(simulator, scene_root),
		"spring_count": planned.size(),
		"springs": planned.map(func(entry): return {"root_bone": str(entry.root), "end_bone": str(entry.end)}),
		"collisions_moved": moved_collisions,
		"active": active,
		"warnings": warnings,
		"undoable": true,
	}
	if not moved_collisions.is_empty():
		data["collisions_note"] = "Godot only reads a collision that is a child of the simulator, so %d node(s) were moved under it (one undo puts them back)" % moved_collisions.size()
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
	var target_rel := _modifier_target_path(skeleton, modifier, target_node, scene_root)
	var setup: Array = [
		{"property": "active", "value": active},
		{"method": "set_bone_name", "args": [bone_name]},
		{"method": "set_target_node", "args": [target_rel]},
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
		# Godot documents these limits in radians; the op advertises degrees (the
		# unit an author thinks in), so the value is converted here rather than
		# forwarded - 45 degrees used to reach the modifier as 45 radians.
		if params.has("primary_limit_angle"):
			setup.append({"method": "set_primary_limit_angle",
				"args": [deg_to_rad(float(params.primary_limit_angle))]})
		if params.has("secondary_limit_angle"):
			setup.append({"method": "set_secondary_limit_angle",
				"args": [deg_to_rad(float(params.secondary_limit_angle))]})
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
# ============================================================================
# twist_setup
# ============================================================================

## Attach a BoneTwistDisperser3D to a Skeleton3D so a twist applied to one bone
## is spread over the bones above it. The root/end default to the detected
## (or explicit) spine chain, and the joint amounts default to the same
## distribution the motion recipes use, so the modifier and the clips agree.
func twist_setup(params: Dictionary, ctx = null) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"twist_setup supports Skeleton3D (BoneTwistDisperser3D)")
	var scene_root := EditorInterface.get_edited_scene_root()
	var skeleton: Skeleton3D = resolved.node
	var spec = params.get("disperse", {})
	if not (spec is Dictionary):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'disperse' must be an object")
	var spec_dict: Dictionary = spec
	var roles := _resolve_roles(params, skeleton)
	if roles.has("_error"):
		return roles["_error"]
	var chain := _torso_chain(params, skeleton, roles)
	if chain.has("error"):
		return chain
	var chain_bones: Array = chain.chain
	if chain_bones.size() < 2:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"twist_setup needs at least two torso bones; pass 'spine_chain': [hips, spine, chest]")
	var root_name := str(spec_dict.get("root_bone", ""))
	if root_name.is_empty():
		root_name = str(chain_bones[0])
	if skeleton.find_bone(root_name) < 0:
		return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
			"disperse.root_bone '%s' is not on this skeleton" % root_name)
	var end_name := str(spec_dict.get("end_bone", ""))
	if end_name.is_empty():
		end_name = str(chain_bones[chain_bones.size() - 1])
	if skeleton.find_bone(end_name) < 0:
		return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
			"disperse.end_bone '%s' is not on this skeleton" % end_name)
	# The joint list the modifier exposes is root -> end inclusive. Godot only
	# builds it once the modifier has been in the tree for a frame, and the
	# per-joint amounts are index-based, so `joints` is not accepted here: the
	# even/weighted modes do the distributing, and the Inspector owns custom.
	var joint_bones := _twist_joint_bones(skeleton, root_name, end_name)
	if joint_bones.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"disperse.end_bone '%s' is not a descendant of root_bone '%s'" % [end_name, root_name])
	var mode_name := str(spec_dict.get("mode", "weighted"))
	if spec_dict.has("joints"):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Godot builds a disperser's per-joint list at runtime, so twist_setup distributes for you: use disperse.mode even|weighted (or set custom amounts in the modifier's Inspector). Mode: %s, joints: %s" % [mode_name, ", ".join(joint_bones)])
	var mode := -1
	match mode_name:
		"even":
			mode = BoneTwistDisperser3D.DISPERSE_MODE_EVEN
		"weighted":
			mode = BoneTwistDisperser3D.DISPERSE_MODE_WEIGHTED
		"custom":
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"disperse.mode=custom needs per-joint amounts, which Godot builds at runtime - set them in the modifier's Inspector, or use even|weighted. Joints here: %s" % ", ".join(joint_bones))
		_:
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Unknown disperse.mode '%s'. Valid: even, weighted" % mode_name)
	var active := bool(params.get("active", false))
	var twist_from_rest := bool(spec_dict.get("twist_from_rest", true))
	if not twist_from_rest and not spec_dict.has("twist_from"):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"disperse.twist_from_rest=false needs disperse.twist_from: the quaternion the chain is measured against, otherwise Godot measures against identity and the disperser does nothing useful. Read one from pose_save on the reference pose, or drop twist_from_rest.")
	var disperser := BoneTwistDisperser3D.new()
	disperser.name = str(params.get("name", "TwistDisperser"))
	var setup: Array = [
		{"property": "active", "value": active},
		{"method": "set_setting_count", "args": [1]},
		{"method": "set_root_bone_name", "args": [0, root_name]},
		{"method": "set_end_bone_name", "args": [0, end_name]},
		{"method": "set_disperse_mode", "args": [0, mode]},
	]
	if spec_dict.has("weight_position"):
		if mode != BoneTwistDisperser3D.DISPERSE_MODE_WEIGHTED:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"disperse.weight_position only applies to mode=weighted (this is mode=%s)" % mode_name)
		setup.append({"method": "set_weight_position", "args": [0, clampf(float(spec_dict.weight_position), 0.0, 1.0)]})
	if spec_dict.has("damping"):
		# Damping curves are read in custom mode only; accepting it elsewhere
		# would queue a resource Godot never looks at.
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"disperse.damping only applies to mode=custom, and custom amounts are built by Godot at runtime - drop damping, or set the damping curve in the modifier's Inspector")
	if twist_from_rest:
		setup.append({"method": "set_twist_from_rest", "args": [0, true]})
	else:
		var reference: Dictionary = SpecJson.decode_value(spec_dict.twist_from)
		if reference.has("error"):
			return reference
		if not (reference.ok is Quaternion):
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"disperse.twist_from must be a quaternion value ({kind: quaternion, x, y, z, w})")
		setup.append({"method": "set_twist_from_rest", "args": [0, false]})
		setup.append({"method": "set_twist_from", "args": [0, reference.ok]})
	# A two-bone range has no joint between the ends, so there is nothing to
	# distribute across: extend past the end bone instead, which is what
	# extend_end_bone is for. Three or more joints distribute as asked.
	var extend_end := bool(spec_dict.get("extend_end_bone", joint_bones.size() < 3))
	setup.append({"method": "set_extend_end_bone", "args": [0, extend_end]})
	var warnings: Array = []
	if joint_bones.size() < 3:
		warnings.append("the range %s -> %s has %d joint(s), so the twist is applied whole rather than shared; pass a longer disperse.root_bone/end_bone pair to share it"
			% [root_name, end_name, joint_bones.size()])
	if params.has("mutable_bone_axes"):
		setup.append({"method": "set_mutable_bone_axes", "args": [bool(params.mutable_bone_axes)]})
	if params.has("influence"):
		setup.append({"property": "influence", "value": clampf(float(params.influence), 0.0, 1.0)})
	var setup_error := _setup_calls_error(disperser, setup)
	if not setup_error.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, setup_error)
	_commit_node_add("MCP: Twist disperser", skeleton, disperser, setup)
	var data := {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"modifier_class": "BoneTwistDisperser3D",
		"modifier_path": ValueCodec.from_node(disperser, scene_root),
		"root_bone": root_name,
		"end_bone": end_name,
		"mode": mode_name,
		"joint_bones": joint_bones,
		"joint_bones_predicted": true,
		"extend_end_bone": extend_end,
		"chain": chain_bones,
		"active": active,
		"warnings": warnings,
		"undoable": true,
		"note": "the modifier disperses root -> end inclusive (%s); Godot builds the per-joint list on the frame after it enters the tree, so read the real one back with rig_get's twist_settings" % ", ".join(joint_bones),
	}
	if not active:
		data["active_note"] = "inactive: an active disperser also rewrites the twist while you edit the scene - pass active=true (or enable the modifier) when it is ready"
	return {"data": data}


## True when at least one bone the profile names exists on the target: a profile
## whose bones are all missing would leave the modifier driving nothing.
static func _profile_bones_resolve(profile: SkeletonProfile, target: Skeleton3D) -> bool:
	for index in profile.get_bone_size():
		if target.find_bone(str(profile.get_bone_name(index))) >= 0:
			return true
	return false


## A `NodePath` to `node` as the SpringBoneSimulator3D - a child of the
## skeleton - will read it. Godot resolves `center_node` and the collision paths
## from the simulator, so a path measured from the skeleton points one level off
## (and silently resolves to the wrong node, or to nothing).
static func _spring_path_to(skeleton: Skeleton3D, node: Node) -> String:
	var from_skeleton := str(skeleton.get_path_to(node))
	if from_skeleton == ".":
		return ".."
	if from_skeleton.is_empty():
		return ""
	return "../" + from_skeleton


## The bones a disperser will expose as joints: the root, everything between it
## and the end, and the end, in that order. Empty when the end is not below the
## root.
func _twist_joint_bones(skeleton: Skeleton3D, root_name: String, end_name: String) -> Array:
	var root_index := skeleton.find_bone(root_name)
	var end_index := skeleton.find_bone(end_name)
	if root_index < 0 or end_index < 0:
		return []
	var bones: Array = []
	var current := end_index
	while current >= 0:
		bones.push_front(str(skeleton.get_bone_name(current)))
		if current == root_index:
			break
		current = skeleton.get_bone_parent(current)
	return bones if not bones.is_empty() and str(bones[0]) == root_name else []


## A damping curve from one 0-1 number: flat 1.0 at 1, easing to 0.4 at 0.
func _damping_curve(amount: float) -> Curve:
	var curve := Curve.new()
	var value := clampf(amount, 0.0, 1.0)
	curve.add_point(Vector2(0.0, lerpf(0.4, 1.0, value)))
	curve.add_point(Vector2(1.0, 1.0))
	return curve


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
	# A target that already hangs off a RetargetModifier3D on this source is being
	# re-targeted, not placed: it is legitimately inside the source subtree, and
	# any other target inside the source would be cyclic.
	var already_under_modifier := target.get_parent() is RetargetModifier3D and source.is_ancestor_of(target)
	if not already_under_modifier and source.is_ancestor_of(target):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The target skeleton is already inside the source skeleton (%s)" % target_path)
	if target.is_ancestor_of(source):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The target skeleton is an ancestor of the source, so moving the target under a retarget modifier would make a parent cycle (%s)" % target_path)
	var resolved_profile := _resolve_retarget_profile(params, source, target)
	if resolved_profile.has("error"):
		return resolved_profile
	# A map that matches nothing (or only the head) produces a modifier that
	# looks set up and moves nothing, so refuse it with the reason.
	var mapped_bones: Array = resolved_profile.mapped
	if mapped_bones.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The '%s' profile maps no bones: its %d bones are not named the same way in both skeletons. Use profile=auto for same-name rigs, or author a SkeletonProfile with the target rig's names - unmatched profile bones: %s"
				% [str(resolved_profile.source), (resolved_profile.profile as SkeletonProfile).get_bone_size(),
					", ".join((resolved_profile.unmapped as Array).slice(0, 6))])
	var missing_core := _retarget_missing_core(mapped_bones, source, target)
	if not missing_core.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The '%s' profile maps %d bone(s) but misses the body core (%s), so the target would not be posed. Rename/profile the missing bones, or retarget a rig whose names match."
				% [str(resolved_profile.source), mapped_bones.size(), ", ".join(missing_core)])
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
	if not (resolved_profile.topology as Array).is_empty():
		warnings.append("%d mapped bone(s) have different parents in the two skeletons, so the target pose will differ from the source: %s" % [
			(resolved_profile.topology as Array).size(),
			", ".join((resolved_profile.topology as Array).slice(0, 4))])
	var source_scale := _skeleton_scale(source)
	var target_scale := _skeleton_scale(target)
	if not is_equal_approx(source_scale, 1.0):
		warnings.append("the source skeleton is scaled (%.2f): retargeting assumes unit scale" % source_scale)
	if not is_equal_approx(target_scale, 1.0):
		warnings.append("the target skeleton is scaled (%.2f): retargeting assumes unit scale" % target_scale)
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
	# Move the target's scene root (its instance root when it comes from an
	# instanced scene) rather than the bare skeleton: a skinned mesh is bound to
	# its skeleton by a path inside its own scene, so pulling the skeleton out
	# would leave the mesh behind.
	var move_node: Node = target
	while move_node.scene_file_path.is_empty() and move_node.get_parent() != null \
			and move_node.get_parent() != scene_root:
		move_node = move_node.get_parent()
	# A RetargetModifier3D transfers to its child *Skeleton3D*, so moving a
	# wrapper (the usual instanced-character root) leaves the skeleton a
	# grandchild and the modifier drives nothing. Evidence (phase 15): a wrapped
	# target's pose never changed, while the op reported success. Refuse the
	# arrangement instead of returning an inert modifier. Only relevant when the
	# target is actually about to be moved - a target that already sits under the
	# modifier needs no move.
	if move_target and not already_under_modifier and move_node != target:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The target Skeleton3D is wrapped in '%s', and RetargetModifier3D only drives a Skeleton3D that is a direct child of the modifier - moving the wrapper would leave the skeleton outside its reach. Pass a target skeleton that is its own scene root, or reparent it next to the source skeleton first."
				% str(move_node.name))
	if not already_under_modifier and not move_target:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The target skeleton must be a child of the RetargetModifier3D. Pass move_target=true to move it there, or parent it under a RetargetModifier3D yourself.")
	if move_target and not already_under_modifier:
		var move_parent := move_node.get_parent()
		if move_parent == null or not _instance_levels(move_parent).is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"The target lives inside a nested instanced scene, so moving it would not survive the scene save - move it into the edited scene first (or pass move_target=false and parent it yourself)")
		if move_node.is_ancestor_of(source):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"The target's scene root is an ancestor of the source skeleton, so reparenting it under a retarget modifier would make a parent cycle")
	# A target that already sits under a RetargetModifier3D is reconfigured in
	# place: adding a second modifier under the source would do nothing, because
	# the modifier only drives its own children.
	var existing_modifier: RetargetModifier3D = null
	if already_under_modifier:
		existing_modifier = target.get_parent() as RetargetModifier3D
		if existing_modifier == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"The target's parent is not a RetargetModifier3D after all - re-run retarget_setup")
		# Reconfiguring in place only works for the source the modifier was built
		# for. Its profile's names come from one skeleton's bone list, so applying
		# another skeleton's map here reports success and silently retargets
		# against bones that do not exist.
		if existing_modifier.get_parent() != source:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"That RetargetModifier3D belongs to '%s', not '%s'. Each modifier is bound to the source it was built for - pass move_target=true with a target that is not already under a modifier, or re-run against the original source."
				% [existing_modifier.get_parent().name, source.name])
	var modifier: RetargetModifier3D = existing_modifier if existing_modifier != null else RetargetModifier3D.new()
	var modifier_created := existing_modifier == null
	if modifier_created:
		modifier.name = str(params.get("name", "Retarget"))
	var previous := {
		"active": modifier.active,
		"profile": modifier.profile,
		"enable_flags": modifier.get_enable_flags(),
		"use_global_pose": modifier.use_global_pose,
	}
	var use_global_pose := bool(params.get("use_global_pose", false))
	var setup: Array = [
		{"property": "active", "value": active, "previous": previous.active},
		{"property": "profile", "value": profile, "previous": previous.profile},
		{"method": "set_enable_flags", "args": [flags],
			"previous_args": [previous.enable_flags]},
		{"method": "set_use_global_pose", "args": [use_global_pose],
			"previous_args": [previous.use_global_pose]},
	]
	if use_global_pose:
		# In global mode Godot retargets the whole pose, so the per-transform
		# enable flags are ignored - say so rather than echoing a lie.
		warnings.append("use_global_pose=true retargets the whole pose: position/rotation/scale enable flags are ignored in that mode")
	var setup_error := _setup_calls_error(modifier, setup)
	if not setup_error.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, setup_error)
	if not _dry_run:
		_create_scene_pinned_action("MCP: Retarget setup")
		var undo := ToolContext.undo_redo
		if modifier_created:
			undo.add_do_method(source, "add_child", modifier, true)
			undo.add_do_method(modifier, "set_owner", scene_root)
			undo.add_do_reference(modifier)
		for call in setup:
			if call.has("property"):
				undo.add_do_property(modifier, call.property, call.value)
				# Reconfiguring snapshots the old value so undo restores it.
				if not modifier_created:
					undo.add_undo_property(modifier, call.property, call.previous)
			else:
				_add_do_call(undo, modifier, call.method, call.get("args", []))
				if not modifier_created:
					_add_undo_call(undo, modifier, call.method, call.previous_args)
		if move_target and not already_under_modifier:
			var old_parent := move_node.get_parent()
			undo.add_do_method(move_node, "reparent", modifier, true)
			# Undo methods run in registration order, so the target goes back to
			# its old parent before the modifier (its current parent) is removed.
			undo.add_undo_method(move_node, "reparent", old_parent, true)
			undo.add_undo_method(source, "remove_child", modifier)
		elif modifier_created:
			undo.add_undo_method(source, "remove_child", modifier)
		undo.commit_action()
	# Failsafe: the modifier is only useful if the target skeleton is a direct
	# child of it, and a profile is only useful if its bones resolved. Check
	# after the commit (the settings are readable then) and roll the whole thing
	# back rather than reporting a setup that cannot work.
	if not _dry_run:
		var direct := false
		for child in modifier.get_children():
			if child == target:
				direct = true
		if not direct:
			return _undo_and_fail(ErrorCodes.INVALID_PARAMS,
				"The retarget modifier was created but the target skeleton is not one of its children, so it would drive nothing")
		if modifier.profile != null and modifier.get_profile().get_bone_size() > 0 \
				and not _profile_bones_resolve(modifier.get_profile(), target):
			return _undo_and_fail(ErrorCodes.INVALID_PARAMS,
				"The retarget profile's bones do not resolve on the target skeleton, so the modifier would drive nothing")
	var data := {
		"skeleton_path": resolved.path,
		"kind": resolved.kind,
		"modifier_class": "RetargetModifier3D",
		"modifier_path": ValueCodec.from_node(modifier, scene_root),
		"modifier_created": modifier_created,
		"target_path": ValueCodec.from_node(target, scene_root),
		"moved_target": move_target and not already_under_modifier,
		"moved_path": ValueCodec.from_node(move_node, scene_root) if move_target and not already_under_modifier else "",
		"profile_source": str(resolved_profile.source),
		"profile_bones": profile.get_bone_size(),
		"mapped_bones": mapped_bones.size(),
		"unmapped_bones": resolved_profile.unmapped,
		"source_only_bones": resolved_profile.source_only,
		"target_only_bones": resolved_profile.target_only,
		"parent_mismatches": resolved_profile.topology,
		"source_scale": source_scale,
		"target_scale": target_scale,
		"enable_flags": flags if not use_global_pose else 0,
		"effective_flags": "global pose (per-transform flags ignored)" if use_global_pose \
			else "position/rotation/scale enable flags",
		"use_global_pose": use_global_pose,
		"active": active,
		"warnings": warnings,
		"undoable": true,
	}
	if not active:
		data["active_note"] = "inactive: an active retarget modifier also drives the target while you edit the scene - pass active=true (or enable the modifier) when it is ready"
	return {"data": data}


# ============================================================================
# walk_cycle / idle_breathing / blink
# ============================================================================

## Procedural recipes: build a looping clip on a skeleton from bone roles.
func walk_cycle(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"walk_cycle needs a Skeleton3D (bone roles are matched by name)")
	var skeleton: Skeleton3D = resolved.node
	var roles := _resolve_roles(params, skeleton)
	if roles.has("_error"):
		return roles["_error"]
	var missing: Array = []
	for role in ["thigh_l", "thigh_r", "shin_l", "shin_r", "arm_l", "arm_r"]:
		if not roles.has(role):
			missing.append(role)
	if not missing.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot find bones for: %s. Pass 'roles' to name them explicitly (e.g. {\"thigh_l\": \"B-thigh.L\"})." % ", ".join(missing))
	var length := float(params.get("duration", 1.0))
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "duration must be > 0")
	var loop_result := _loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var stride := float(params.get("stride", 25.0))
	var knee := float(params.get("knee_bend", 30.0))
	var arm := float(params.get("arm_swing", 20.0))
	var arm_down := float(params.get("arm_down", 0.0))
	var bob := float(params.get("bob", 0.05))
	var axis_name := str(params.get("swing_axis", "x"))
	var axis := _spec_vector3(axis_name_to_vector(axis_name))
	if axis == Vector3.ZERO:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid swing_axis '%s'. Valid: x, y, z" % axis_name)
	var down_l := _aim_delta(skeleton, str(roles.arm_l), Vector3.DOWN, arm_down)
	var down_r := _aim_delta(skeleton, str(roles.arm_r), Vector3.DOWN, arm_down)
	var half := length * 0.5
	var keys := {}
	keys[roles.thigh_l] = {"rotation": [
		{"time": 0.0, "delta": Quaternion(axis, deg_to_rad(stride))},
		{"time": half, "delta": Quaternion(axis, deg_to_rad(-stride))},
		{"time": length, "delta": Quaternion(axis, deg_to_rad(stride))},
	]}
	keys[roles.thigh_r] = {"rotation": [
		{"time": 0.0, "delta": Quaternion(axis, deg_to_rad(-stride))},
		{"time": half, "delta": Quaternion(axis, deg_to_rad(stride))},
		{"time": length, "delta": Quaternion(axis, deg_to_rad(-stride))},
	]}
	keys[roles.shin_l] = {"rotation": [
		{"time": 0.0, "delta": Quaternion(axis, deg_to_rad(-knee * 0.15))},
		{"time": length * 0.4, "delta": Quaternion(axis, deg_to_rad(-knee))},
		{"time": length * 0.6, "delta": Quaternion(axis, deg_to_rad(-knee * 0.35))},
		{"time": length, "delta": Quaternion(axis, deg_to_rad(-knee * 0.15))},
	]}
	keys[roles.shin_r] = {"rotation": [
		{"time": 0.0, "delta": Quaternion(axis, deg_to_rad(-knee * 0.35))},
		{"time": length * 0.4, "delta": Quaternion(axis, deg_to_rad(-knee * 0.15))},
		{"time": length * 0.6, "delta": Quaternion(axis, deg_to_rad(-knee))},
		{"time": length, "delta": Quaternion(axis, deg_to_rad(-knee * 0.35))},
	]}
	keys[roles.arm_l] = {"rotation": [
		{"time": 0.0, "delta": (down_l * Quaternion(axis, deg_to_rad(-arm))).normalized()},
		{"time": half, "delta": (down_l * Quaternion(axis, deg_to_rad(arm))).normalized()},
		{"time": length, "delta": (down_l * Quaternion(axis, deg_to_rad(-arm))).normalized()},
	]}
	keys[roles.arm_r] = {"rotation": [
		{"time": 0.0, "delta": (down_r * Quaternion(axis, deg_to_rad(arm))).normalized()},
		{"time": half, "delta": (down_r * Quaternion(axis, deg_to_rad(-arm))).normalized()},
		{"time": length, "delta": (down_r * Quaternion(axis, deg_to_rad(arm))).normalized()},
	]}
	if roles.has("hips"):
		keys[roles.hips] = {"position": [
			{"time": 0.0, "delta": Vector3.ZERO},
			{"time": length * 0.25, "delta": Vector3(0, bob, 0)},
			{"time": length * 0.5, "delta": Vector3.ZERO},
			{"time": length * 0.75, "delta": Vector3(0, bob, 0)},
			{"time": length, "delta": Vector3.ZERO},
		]}
	var committed := _commit_procedural_clip(params, resolved,
		str(params.get("animation_name", "walk")), length, loop_result.ok, keys)
	if committed.has("error"):
		return committed
	committed.data["roles"] = roles
	committed.data["arm_down"] = arm_down
	committed.data["note"] = "in-place cycle: no root motion is keyed"
	return committed


## The torso chain a rig recipe distributes over. An explicit `spine_chain` is
## honoured as given - it used to be validated and then replaced by a
## role-derived chain, which dropped the neck and any named intermediate. Without
## one, the detected chain is used, falling back to the scalar roles.
func _torso_chain(params: Dictionary, skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	var resolved := resolve_spine_chain(params, skeleton, roles)
	if resolved.has("error"):
		return resolved
	# The detected chain already includes intermediates (a neck, an upper chest);
	# rebuilding it from the four scalar roles dropped them, so the roles are only
	# a fallback for a rig where detection found nothing.
	var detected: Array = resolved.chain
	if not detected.is_empty():
		return resolved
	var chain: Array = []
	for role in ["hips", "spine", "chest", "head"]:
		var bone := str(roles.get(role, ""))
		if not bone.is_empty() and not chain.has(bone):
			chain.append(bone)
	return {"chain": chain}


## A subtle looping idle: chest/spine breathing, a light head counter-move and
## an optional hip bob.
func idle_breathing(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "idle_breathing needs a Skeleton3D")
	var skeleton: Skeleton3D = resolved.node
	var roles := _resolve_roles(params, skeleton)
	if roles.has("_error"):
		return roles["_error"]
	var chest := str(roles.get("chest", ""))
	if chest.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot find a chest/spine bone. Pass 'roles': {\"chest\": \"B-chest\"}.")
	var length := float(params.get("duration", 3.0))
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "duration must be > 0")
	var loop_result := _loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var amplitude := deg_to_rad(float(params.get("amplitude", 2.0)))
	var head_amplitude := deg_to_rad(float(params.get("head_amplitude", 1.0)))
	var bob := float(params.get("bob", 0.01))
	var axis := _spec_vector3(axis_name_to_vector(str(params.get("axis", "x"))))
	if axis == Vector3.ZERO:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid axis '%s'. Valid: x, y, z" % str(params.get("axis", "x")))
	var breathe := func(amount: float) -> Array:
		return [
			{"time": 0.0, "delta": Quaternion(axis, 0.0)},
			{"time": length * 0.35, "delta": Quaternion(axis, amount)},
			{"time": length * 0.6, "delta": Quaternion(axis, amount * 0.85)},
			{"time": length, "delta": Quaternion(axis, 0.0)},
		]
	var keys := {}
	# The breathing moves the whole chain, not just a spine/chest pair: the
	# lowest torso bone takes 0.6 of the amplitude and it ramps to the chest,
	# the head counter-moves. Before, a 6-bone spine only breathed in two places.
	var chain := _torso_chain(params, skeleton, roles)
	if chain.has("error"):
		return chain
	var chain_bones: Array = chain.chain
	var breathe_by_bone := {}
	for index in chain_bones.size():
		var bone := str(chain_bones[index])
		if bone.is_empty() or bone == str(roles.get("hips", "")):
			continue
		var amount := amplitude
		if bone == str(roles.get("head", "")):
			amount = -head_amplitude
		elif chain_bones.size() > 1:
			amount = amplitude * lerpf(0.6, 1.0, float(index) / float(chain_bones.size() - 1))
		breathe_by_bone[bone] = breathe.call(amount)
	for bone in breathe_by_bone:
		keys[bone] = {"rotation": breathe_by_bone[bone]}
	if roles.has("hips") and not is_zero_approx(bob):
		keys[str(roles.hips)] = {"position": [
			{"time": 0.0, "delta": Vector3.ZERO},
			{"time": length * 0.5, "delta": Vector3(0, bob, 0)},
			{"time": length, "delta": Vector3.ZERO},
		]}
	var committed := _commit_procedural_clip(params, resolved,
		str(params.get("animation_name", "idle")), length, loop_result.ok, keys)
	if committed.has("error"):
		return committed
	committed.data["roles"] = roles
	return committed


## A quick eye blink: scale (default) or rotate the eyelid/eye bones closed and
## back, optionally several blinks per clip.
func blink(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "blink needs a Skeleton3D")
	var skeleton: Skeleton3D = resolved.node
	var roles := _resolve_roles(params, skeleton)
	if roles.has("_error"):
		return roles["_error"]
	var eye_bones: Array = params.get("bones", [])
	if eye_bones.is_empty():
		for role in ["eye_l", "eye_r", "eyelid_l", "eyelid_r"]:
			if roles.has(role):
				eye_bones.append(str(roles[role]))
	if eye_bones.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot find eye/eyelid bones. Pass 'bones': [\"eyelid.L\", \"eyelid.R\"].")
	var mode := str(params.get("mode", "scale"))
	if mode != "scale" and mode != "rotate":
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid mode '%s'. Valid: scale, rotate" % mode)
	var length := float(params.get("duration", 0.18))
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "duration must be > 0")
	var loop_result := _loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var blinks := maxi(1, int(params.get("blinks", 1)))
	var closed_scale := float(params.get("closed_scale", 0.05))
	var angle := deg_to_rad(float(params.get("angle", 25.0)))
	var axis := _spec_vector3(axis_name_to_vector(str(params.get("axis", "x"))))
	if axis == Vector3.ZERO:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid axis '%s'. Valid: x, y, z" % str(params.get("axis", "x")))
	var keys := {}
	for bone_name in eye_bones:
		var span := length / float(blinks)
		var rotation_keys: Array = []
		var scale_keys: Array = []
		for index in blinks:
			var start := index * span
			rotation_keys.append({"time": start, "delta": Quaternion(axis, 0.0)})
			rotation_keys.append({"time": start + span * 0.4, "delta": Quaternion(axis, angle)})
			rotation_keys.append({"time": start + span * 0.55, "delta": Quaternion(axis, angle)})
			rotation_keys.append({"time": start + span, "delta": Quaternion(axis, 0.0)})
			scale_keys.append({"time": start, "value": Vector3.ONE})
			scale_keys.append({"time": start + span * 0.4, "value": Vector3(1.0, closed_scale, 1.0)})
			scale_keys.append({"time": start + span * 0.55, "value": Vector3(1.0, closed_scale, 1.0)})
			scale_keys.append({"time": start + span, "value": Vector3.ONE})
		if mode == "scale":
			keys[str(bone_name)] = {"scale": scale_keys}
		else:
			keys[str(bone_name)] = {"rotation": rotation_keys}
	var committed := _commit_procedural_clip(params, resolved,
		str(params.get("animation_name", "blink")), length, loop_result.ok, keys)
	if committed.has("error"):
		return committed
	committed.data["bones"] = eye_bones
	committed.data["mode"] = mode
	return committed


# ============================================================================
# jumping_jack / squat / punch
# ============================================================================

## A jumping-jack rep: the arms swing down -> overhead while the legs spread
## apart and back together, with a small rise when open. Needs a standing rest
## pose (T- or A-pose arms both work).
func jumping_jack(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "jumping_jack needs a Skeleton3D")
	var skeleton: Skeleton3D = resolved.node
	var roles := _resolve_roles(params, skeleton)
	if roles.has("_error"):
		return roles["_error"]
	var missing: Array = []
	for role in ["arm_l", "arm_r", "thigh_l", "thigh_r"]:
		if not roles.has(role):
			missing.append(role)
	if not missing.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot find bones for: %s. Pass 'roles' to name them explicitly (e.g. {\"thigh_l\": \"B-thigh.L\"})." % ", ".join(missing))
	var length := float(params.get("duration", 1.0))
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "duration must be > 0")
	var loop_result := _loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var arm_amount := float(params.get("amplitude", 80.0))
	var spread := float(params.get("stride", 18.0))
	var hop := float(params.get("bob", 0.04))
	var half := length * 0.5
	var keys := {}
	for side in ["l", "r"]:
		var arm := str(roles["arm_" + side])
		keys[arm] = {"rotation": [
			{"time": 0.0, "delta": _aim_delta(skeleton, arm, Vector3.DOWN, arm_amount)},
			{"time": half, "delta": _aim_delta(skeleton, arm, Vector3.UP, arm_amount)},
			{"time": length, "delta": _aim_delta(skeleton, arm, Vector3.DOWN, arm_amount)},
		]}
		var thigh := str(roles["thigh_" + side])
		var outward := Vector3.RIGHT if side == "l" else Vector3.LEFT
		keys[thigh] = {"rotation": [
			{"time": 0.0, "delta": Quaternion.IDENTITY},
			{"time": half, "delta": _aim_delta(skeleton, thigh, outward, spread)},
			{"time": length, "delta": Quaternion.IDENTITY},
		]}
	if roles.has("hips"):
		keys[roles.hips] = {"position": [
			{"time": 0.0, "delta": Vector3.ZERO},
			{"time": half, "delta": Vector3(0, hop, 0)},
			{"time": length, "delta": Vector3.ZERO},
		]}
	var committed := _commit_procedural_clip(params, resolved,
		str(params.get("animation_name", "jumping_jack")), length, loop_result.ok, keys)
	if committed.has("error"):
		return committed
	committed.data["roles"] = roles
	return committed


## A squat rep with planted feet: the hips drop, the knees bend forward and the
## leg chains are solved so the ankles stay at their rest positions. The arms
## ease forward for balance. Needs thighs, shins, feet and a hips bone.
func squat(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "squat needs a Skeleton3D")
	var skeleton: Skeleton3D = resolved.node
	var roles := _resolve_roles(params, skeleton)
	if roles.has("_error"):
		return roles["_error"]
	var missing: Array = []
	for role in ["thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r", "hips"]:
		if not roles.has(role):
			missing.append(role)
	if not missing.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot find bones for: %s. Pass 'roles' to name them explicitly." % ", ".join(missing))
	var length := float(params.get("duration", 2.0))
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "duration must be > 0")
	var loop_result := _loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var depth := float(params.get("bob", 0.25))
	if depth <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "bob (squat depth in metres) must be > 0")
	var arm_amount := float(params.get("amplitude", 65.0))
	var times := [0.0, length * 0.35, length * 0.65, length]
	var factors := [0.0, 1.0, 1.0, 0.0]
	var snapshot := _pose_snapshot(skeleton)
	var keys := {}
	for index in times.size():
		var factor: float = factors[index]
		var deltas := _squat_deltas(skeleton, roles, depth * factor, arm_amount * factor)
		for bone in deltas:
			var entry: Dictionary = deltas[bone]
			if not keys.has(bone):
				keys[bone] = {}
			var kind := "rotation" if entry.has("rotation") else "position"
			if not (keys[bone] as Dictionary).has(kind):
				(keys[bone] as Dictionary)[kind] = []
			((keys[bone] as Dictionary)[kind] as Array).append({"time": times[index], "delta": entry[kind]})
	_pose_restore(skeleton, snapshot)
	var committed := _commit_procedural_clip(params, resolved,
		str(params.get("animation_name", "squat")), length, loop_result.ok, keys)
	if committed.has("error"):
		return committed
	committed.data["roles"] = roles
	committed.data["depth"] = depth
	return committed


## Pose the squat at `depth` metres (arms forward by `arm_amount` degrees) and
## return rest-relative deltas per bone.
static func _squat_deltas(skeleton: Skeleton3D, roles: Dictionary, depth: float, arm_amount: float) -> Dictionary:
	skeleton.reset_bone_poses()
	var out := {}
	var hips_index := skeleton.find_bone(str(roles.hips))
	if hips_index >= 0:
		var hips_delta := Vector3(0, -depth, 0)
		skeleton.set_bone_pose_position(hips_index, skeleton.get_bone_rest(hips_index).origin + hips_delta)
		out[str(roles.hips)] = {"position": hips_delta}
	var forward := _forward_dir(skeleton, roles)
	for side in ["l", "r"]:
		var thigh := str(roles.get("thigh_" + side, ""))
		var shin := str(roles.get("shin_" + side, ""))
		var foot := str(roles.get("foot_" + side, ""))
		if thigh.is_empty() or shin.is_empty() or foot.is_empty():
			continue
		var thigh_index := skeleton.find_bone(thigh)
		var shin_index := skeleton.find_bone(shin)
		var foot_index := skeleton.find_bone(foot)
		var hip := skeleton.get_bone_global_pose(thigh_index).origin
		var ankle := skeleton.get_bone_global_rest(foot_index).origin
		var upper := (skeleton.get_bone_global_rest(shin_index).origin - skeleton.get_bone_global_rest(thigh_index).origin).length()
		var lower := (skeleton.get_bone_global_rest(foot_index).origin - skeleton.get_bone_global_rest(shin_index).origin).length()
		var knee := _knee_position(hip, ankle, upper, lower, forward)
		_point_bone(skeleton, thigh, knee - hip)
		_point_bone(skeleton, shin, ankle - knee)
		out[thigh] = {"rotation": _pose_delta_rotation(skeleton, thigh_index)}
		out[shin] = {"rotation": _pose_delta_rotation(skeleton, shin_index)}
		var arm := str(roles.get("arm_" + side, ""))
		if not arm.is_empty():
			var arm_target := (forward * 0.8 + Vector3.DOWN * 0.35).normalized()
			out[arm] = {"rotation": _aim_delta(skeleton, arm, arm_target, arm_amount)}
	return out


## A boxing combo: guard, then alternating straight punches with a torso twist.
## `cycles` punches fit in the clip; `amplitude` is the twist in degrees and
## `bob` the stance crouch in metres.
func punch(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "punch needs a Skeleton3D")
	var skeleton: Skeleton3D = resolved.node
	var roles := _resolve_roles(params, skeleton)
	if roles.has("_error"):
		return roles["_error"]
	var missing: Array = []
	for role in ["arm_l", "arm_r", "forearm_l", "forearm_r"]:
		if not roles.has(role):
			missing.append(role)
	if not missing.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot find bones for: %s. Pass 'roles' to name them explicitly." % ", ".join(missing))
	var length := float(params.get("duration", 0.8))
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "duration must be > 0")
	var loop_result := _loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var cycles := maxi(1, int(params.get("cycles", 2)))
	var twist := float(params.get("amplitude", 12.0))
	var crouch := float(params.get("bob", 0.05))
	var span := length / float(cycles)
	var snapshot := _pose_snapshot(skeleton)
	var times: Array = [0.0]
	var states: Array = [""]
	for cycle in cycles:
		var base := cycle * span
		times.append(base + span * 0.35)
		states.append("l" if cycle % 2 == 0 else "r")
		times.append(base + span)
		states.append("")
	var chain := _torso_chain(params, skeleton, roles)
	if chain.has("error"):
		return chain
	var keys := {}
	for index in times.size():
		var deltas := _punch_deltas(skeleton, roles, str(states[index]), twist, crouch, chain.chain)
		for bone in deltas:
			var entry: Dictionary = deltas[bone]
			if not keys.has(bone):
				keys[bone] = {}
			var kind := "rotation" if entry.has("rotation") else "position"
			if not (keys[bone] as Dictionary).has(kind):
				(keys[bone] as Dictionary)[kind] = []
			((keys[bone] as Dictionary)[kind] as Array).append({"time": times[index], "delta": entry[kind]})
	_pose_restore(skeleton, snapshot)
	var committed := _commit_procedural_clip(params, resolved,
		str(params.get("animation_name", "punch")), length, loop_result.ok, keys)
	if committed.has("error"):
		return committed
	committed.data["roles"] = roles
	committed.data["cycles"] = cycles
	return committed


## Pose the boxing stance at one moment (`punching` is "l", "r" or "" for the
## guard) and return rest-relative deltas per bone.
static func _punch_deltas(skeleton: Skeleton3D, roles: Dictionary, punching: String, twist: float, crouch: float, chain: Array) -> Dictionary:
	skeleton.reset_bone_poses()
	var out := {}
	var hips := str(roles.get("hips", ""))
	if not hips.is_empty():
		var hips_index := skeleton.find_bone(hips)
		if hips_index >= 0:
			var hips_delta := Vector3(0, -crouch, 0)
			skeleton.set_bone_pose_position(hips_index, skeleton.get_bone_rest(hips_index).origin + hips_delta)
			out[hips] = {"position": hips_delta}
	var forward := _forward_dir(skeleton, roles)
	var twist_sign := 0.0
	if punching == "l":
		twist_sign = 1.0
	elif punching == "r":
		twist_sign = -1.0
	# `amplitude` is the *total* torso twist in degrees, shared over the chain:
	# mostly in the upper chest, a little in the lower spine, so a long spine
	# gets a smooth rotation instead of one bone snapping the whole torso.
	var torso: Array = []
	for slot in chain:
		var name := str(slot)
		if not name.is_empty() and name != hips:
			torso.append(name)
	var weights: Array = []
	for index in torso.size():
		weights.append(0.2 if torso.size() < 2 else lerpf(0.2, 1.0, float(index) / float(torso.size() - 1)))
	var degrees: Array = SpineTwist.amplitudes(maxi(1, torso.size()), twist, weights) if not torso.is_empty() else []
	for index in torso.size():
		var bone := str(torso[index])
		out[bone] = {"rotation": Quaternion(Vector3.UP, deg_to_rad(float(degrees[index]) * twist_sign))}
	for side in ["l", "r"]:
		var arm := str(roles.get("arm_" + side, ""))
		var forearm := str(roles.get("forearm_" + side, ""))
		if arm.is_empty() or forearm.is_empty():
			continue
		if side == punching:
			_point_bone(skeleton, arm, (forward + Vector3.DOWN * 0.08).normalized())
			_point_bone(skeleton, forearm, forward)
		else:
			_point_bone(skeleton, arm, (Vector3.DOWN * 0.8 + forward * 0.4).normalized())
			_point_bone(skeleton, forearm, (Vector3.UP * 0.45 + forward * 0.85).normalized())
		out[arm] = {"rotation": _pose_delta_rotation(skeleton, skeleton.find_bone(arm))}
		out[forearm] = {"rotation": _pose_delta_rotation(skeleton, skeleton.find_bone(forearm))}
	return out


# ============================================================================
# bake_pose_sequence
# ============================================================================

## Sample a skeleton over time into a clip. Any AnimationPlayer on the skeleton
## is seeked to each sample first, then the skeleton is updated so modifiers
## (IK, springs, retarget) run - the baked clip plays without them.
func bake_pose_sequence(params: Dictionary) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"bake_pose_sequence needs a Skeleton3D")
	var skeleton: Skeleton3D = resolved.node
	var length := float(params.get("duration", 1.0))
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "duration must be > 0")
	var fps := maxi(1, int(params.get("fps", 30)))
	var loop_result := _loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var include_positions := bool(params.get("positions", true))
	var include_scales := bool(params.get("scales", false))
	var bones_filter: Array = params.get("bones", [])
	var player_resolved := _resolve_player(str(params.get("player_path", "")))
	if player_resolved.has("error"):
		return player_resolved
	var player: AnimationPlayer = player_resolved.player
	var library: AnimationLibrary = player_resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true
	# The source clip has to be assigned to the player before seek() can sample
	# it - a player that was never played has no current animation, and seeking
	# it would leave the skeleton at rest.
	var source := str(params.get("source_animation", ""))
	if source.is_empty():
		source = player.current_animation
	if source.is_empty() and not String(player.assigned_animation).is_empty():
		source = String(player.assigned_animation)
	if not source.is_empty() and not player.has_animation(source):
		var names: Array = []
		for name in library.get_animation_list():
			names.append(str(name))
		names.sort()
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Animation '%s' not found on the player. Available: %s"
			% [source, ", ".join(names) if not names.is_empty() else "(none)"])
	var root_node := ValueCodec.player_root_node(player)
	if root_node == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The AnimationPlayer has no resolvable root_node")
	var track_root := str(root_node.get_path_to(skeleton))
	if track_root.is_empty() or track_root == ".":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The skeleton must live under the player's root_node")
	# Remember the current pose so the bake leaves the scene as it found it. A
	# RetargetModifier3D writes to its target's skeleton, so the target counts as
	# "the scene" here too - restoring only the source left the target posed.
	var restore: Array = []
	for index in skeleton.get_bone_count():
		restore.append({
			"rotation": skeleton.get_bone_pose_rotation(index),
			"position": skeleton.get_bone_pose_position(index),
			"scale": skeleton.get_bone_pose_scale(index),
		})
	var retarget_targets: Array = []
	var retarget_restores: Array = []
	for child in skeleton.get_children():
		if child is RetargetModifier3D and (child as RetargetModifier3D).active:
			for grandchild in child.get_children():
				var found_skeleton := _skeleton_below(grandchild)
				if found_skeleton != null and not retarget_targets.has(found_skeleton):
					retarget_targets.append(found_skeleton)
					retarget_restores.append({
						"skeleton": found_skeleton,
						"pose": _pose_snapshot(found_skeleton),
					})
	var indices: Array = []
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		if not bones_filter.is_empty() and not bones_filter.has(bone_name):
			continue
		indices.append(index)
	if indices.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "No bones to bake")
	var samples := int(ceil(length * float(fps))) + 1
	if samples > MAX_BAKE_SAMPLES:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"duration x fps would sample %d poses (max %d). Lower fps or shorten the clip." % [samples, MAX_BAKE_SAMPLES])
	var step := 1.0 / float(fps)
	var keys := {}
	for index in indices:
		keys[skeleton.get_bone_name(index)] = {"rotation": [], "position": [], "scale": []}
	var was_playing := player.is_playing()
	var was_animation := player.current_animation
	var was_position := player.current_animation_position
	if not source.is_empty():
		player.play(source)
	# Active modifiers (IK, springs, retarget) only run in the skeleton's
	# deferred update, and their result is only readable inside
	# modification_processed - get_bone_pose_* outside it returns the
	# pre-modifier pose. Drive that update manually per sample and capture the
	# final pose in the signal handler.
	var modifiers: Array = []
	for child in skeleton.get_children():
		if child is SkeletonModifier3D and (child as SkeletonModifier3D).active:
			modifiers.append(child)
	# Stateful modifiers carry internal velocity/spring state between updates, so
	# a second bake would start from wherever the first one ended. Reset what can
	# be reset (SpringBoneSimulator3D.reset()) so the result only depends on fps.
	var reset_modifiers: Array = []
	for modifier in modifiers:
		if (modifier as SkeletonModifier3D).has_method("reset"):
			(modifier as SkeletonModifier3D).call("reset")
			reset_modifiers.append((modifier as SkeletonModifier3D).get_class())
	var sampled: Dictionary = {}
	var capture := func() -> void:
		sampled.clear()
		for index in indices:
			sampled[index] = {
				"rotation": skeleton.get_bone_pose_rotation(index),
				"position": skeleton.get_bone_pose_position(index),
				"scale": skeleton.get_bone_pose_scale(index),
			}
	for modifier in modifiers:
		(modifier as SkeletonModifier3D).modification_processed.connect(capture)
	# Sample 0 is the state after one step of modifier time, so the baked clip
	# starts where playback would put it rather than at an unresolved step.
	var missing_capture_at := -1.0
	for sample in samples:
		var time := minf(sample * step, length)
		if not source.is_empty():
			player.seek(time, true)
		sampled.clear()
		if not modifiers.is_empty():
			# advance() accumulates the delta and the deferred update consumes it,
			# so the pair gives the modifiers exactly `step` instead of whatever
			# the editor's frame time was - springs integrate deterministically.
			skeleton.advance(step)
			skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
			# `sampled` stays empty when no modifier reported in, which would mean
			# the clip would hold pre-modifier poses.
			if sampled.is_empty() and missing_capture_at < 0.0:
				missing_capture_at = time
		for index in indices:
			var bone_name := skeleton.get_bone_name(index)
			var entry: Dictionary = keys[bone_name]
			var rotation: Quaternion = skeleton.get_bone_pose_rotation(index)
			var position: Vector3 = skeleton.get_bone_pose_position(index)
			var bone_scale: Vector3 = skeleton.get_bone_pose_scale(index)
			if sampled.has(index):
				rotation = sampled[index].rotation
				position = sampled[index].position
				bone_scale = sampled[index].scale
			(entry.rotation as Array).append({"time": time, "value": rotation, "transition": "linear"})
			if include_positions:
				(entry.position as Array).append({"time": time, "value": position, "transition": "linear"})
			if include_scales:
				(entry.scale as Array).append({"time": time, "value": bone_scale, "transition": "linear"})
	for modifier in modifiers:
		if (modifier as SkeletonModifier3D).modification_processed.is_connected(capture):
			(modifier as SkeletonModifier3D).modification_processed.disconnect(capture)
	if missing_capture_at >= 0.0:
		_restore_bake_state(skeleton, restore, retarget_restores, player,
			was_playing, was_animation, was_position)
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The active modifier on %s never reported modification_processed at t=%.3f, so the sampled pose would be the pre-modifier one. Nothing was written - make the modifier active, or bake with the modifiers disabled."
				% [resolved.path, missing_capture_at])
	_restore_bake_state(skeleton, restore, retarget_restores, player,
		was_playing, was_animation, was_position)
	var anim_name := str(params.get("animation_name", "baked"))
	var spec := ClipSpec.make(length, loop_result.ok)
	for bone_name in keys:
		var entry: Dictionary = keys[bone_name]
		var rotation_keys: Array = entry.rotation
		if not rotation_keys.is_empty():
			ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone_name], rotation_keys,
				Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
		var position_keys: Array = entry.position
		if include_positions and not position_keys.is_empty():
			ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone_name], position_keys,
				Animation.INTERPOLATION_LINEAR, Animation.TYPE_POSITION_3D)
		var scale_keys: Array = entry.scale
		if include_scales and not scale_keys.is_empty():
			ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone_name], scale_keys,
				Animation.INTERPOLATION_LINEAR, Animation.TYPE_SCALE_3D)
	var valid := SpecBuilder.validate(spec)
	if valid.has("error"):
		return valid
	var overwrite := bool(params.get("overwrite", false))
	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var anim := SpecBuilder.to_animation(spec)
	_commit_animation_add("MCP: Baked clip %s" % anim_name, player, library,
		created_library, anim_name, anim, existing.old_anim)
	return {"data": {
		"player_path": str(params.get("player_path", "")),
		"skeleton_path": resolved.path,
		"animation_name": anim_name,
		"length": length,
		"fps": fps,
		"samples": samples,
		"bone_count": indices.size(),
		"track_count": (spec.tracks as Array).size(),
		"positions": include_positions,
		"scales": include_scales,
		"source_animation": source,
		"loop_mode": ValueCodec.loop_mode_to_string(int(spec.loop_mode)),
		"library_created": created_library,
		"overwritten": existing.old_anim != null,
		"undoable": true,
		"modifiers": _modifier_names(modifiers),
		"reset_modifiers": reset_modifiers,
		"sample_delta": step,
		"restored_skeletons": [resolved.path] + _skeleton_paths(retarget_restores,
			EditorInterface.get_edited_scene_root()),
		"retarget_targets": _skeleton_paths(retarget_restores,
			EditorInterface.get_edited_scene_root()),
		"note": "the skeleton's pose was restored after sampling; disable the source modifiers once you play the baked clip",
	}}


## Class names of the modifier stack that participated, for the reply.
static func _modifier_names(modifiers: Array) -> Array:
	var names: Array = []
	for modifier in modifiers:
		names.append((modifier as SkeletonModifier3D).get_class())
	return names


## Put every skeleton the bake touched and the player back the way they were:
## the source pose, each retarget target's pose, and the player's animation,
## time and play state.
func _restore_bake_state(skeleton: Skeleton3D, restore: Array, retarget_restores: Array,
		player: AnimationPlayer, was_playing: bool, was_animation: String,
		was_position: float) -> void:
	# Player first: seeking it back writes the animation's pose into the bones,
	# so the bone restore has to come after it to be the last word.
	if was_animation.is_empty():
		player.stop()
	else:
		player.play(was_animation)
		player.seek(was_position, true)
		if not was_playing:
			player.pause()
	for entry in retarget_restores:
		_pose_restore(entry.skeleton, entry.pose)
	for index in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(index, restore[index].rotation)
		skeleton.set_bone_pose_position(index, restore[index].position)
		skeleton.set_bone_pose_scale(index, restore[index].scale)


## The Skeleton3D at or below a node (a retarget modifier drives its target's
## skeleton, which may sit inside the target's own scene).
static func _skeleton_below(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _skeleton_below(child)
		if found != null:
			return found
	return null


## Scene paths of the snapshot entries built for retarget targets.
static func _skeleton_paths(entries: Array, scene_root: Node) -> Array:
	var paths: Array = []
	for entry in entries:
		paths.append(ValueCodec.from_node(entry.skeleton, scene_root))
	return paths


# ============================================================================
# Helpers
# ============================================================================

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


## Solve every `aim` entry on top of `pose` and return the resolved pose.
##
## Each entry is `{chain: [root, mid, end], target: [x, y, z], pole?: [x, y, z]}`:
## the end bone's origin lands on `target` (world space) and the mid bone bends
## into the `pole` half-plane, or keeps the base pose's bend without one. The
## skeleton pose is always restored afterwards.
func _apply_aims(resolved: Dictionary, pose: Dictionary, aims) -> Dictionary:
	if not (aims is Array) or (aims as Array).is_empty():
		return {"pose": pose}
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'aim' needs a Skeleton3D")
	var skeleton: Skeleton3D = resolved.node
	var bones: Array = PoseMath.bone_names(pose)
	for aim in aims:
		var entry := _aim_entry(aim)
		if entry.has("error"):
			return entry
		for bone in entry.chain:
			if skeleton.find_bone(str(bone)) < 0:
				return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
					"aim chain bone '%s' is not on this skeleton" % str(bone))
			if not bones.has(bone):
				bones.append(bone)
	var snapshot := _pose_snapshot(skeleton)
	for bone in PoseMath.bone_names(pose):
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		var rest := skeleton.get_bone_rest(index)
		var absolute := PoseMath.delta_to_pose(
			pose.bones[bone], rest.basis.get_rotation_quaternion(), rest.origin)
		skeleton.set_bone_pose_rotation(index, absolute.rotation)
		skeleton.set_bone_pose_position(index, absolute.position)
		skeleton.set_bone_pose_scale(index, absolute.scale)
	var world := skeleton.global_transform
	var contacts: Array = []
	for aim in aims:
		var entry := _aim_entry(aim)
		var target: Vector3 = world.affine_inverse() * (entry.target as Vector3)
		# The pole is a world point like the target, so it needs the same full
		# inverse: basis.inverse() alone left the skeleton's world translation in
		# the pole, which moved the bend direction on any translated skeleton.
		var pole: Vector3 = world.affine_inverse() * (entry.pole as Vector3)
		var root_index := skeleton.find_bone(entry.chain[0])
		var parent_delta := Transform3D.IDENTITY
		var parent_index := skeleton.get_bone_parent(root_index)
		if parent_index >= 0:
			parent_delta = skeleton.get_bone_global_pose(parent_index) \
				* skeleton.get_bone_global_rest(parent_index).affine_inverse()
		var rest_globals: Array = []
		var base_deltas: Array = []
		for slot in 3:
			var index := skeleton.find_bone(entry.chain[slot])
			rest_globals.append(skeleton.get_bone_global_rest(index))
			base_deltas.append(_pose_delta_rotation(skeleton, index))
		var solved := PoseSolver.solve_chain(rest_globals, parent_delta, base_deltas, target, pole)
		if solved.has("error"):
			_pose_restore(skeleton, snapshot)
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "aim: %s" % str(solved.error))
		for slot in 3:
			var index := skeleton.find_bone(entry.chain[slot])
			# The solver returns rest-relative deltas; the skeleton wants rest * delta.
			var rest_quat: Quaternion = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(index,
				(rest_quat * (solved.rotations[slot] as Quaternion)).normalized())
		contacts.append({
			"chain": (entry.chain as Array).duplicate(),
			"target": [entry.target.x, entry.target.y, entry.target.z],
			"reach": snappedf(float(solved.reach), 0.0001),
			"clamped": bool(solved.clamped),
		})
	var captured := _capture_pose(resolved, bones)
	_pose_restore(skeleton, snapshot)
	if captured.has("error"):
		return captured
	return {"pose": captured.pose, "contacts": contacts}


## Validate one aim entry into `{chain: Array, target: Vector3, pole: Vector3}`.
func _aim_entry(aim) -> Dictionary:
	if not (aim is Dictionary):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "each aim entry must be an object")
	var chain: Array = (aim as Dictionary).get("chain", [])
	if chain.size() != 3:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"aim.chain needs exactly three bone names (root, mid, end)")
	var names: Array = []
	for bone in chain:
		names.append(str(bone))
	if not (aim as Dictionary).has("target"):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "aim needs 'target': [x, y, z]")
	var target_value = (aim as Dictionary).get("target")
	if not (target_value is Array or target_value is Dictionary or target_value is Vector3):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "aim.target must be [x, y, z]")
	return {
		"chain": names,
		"target": _spec_vector3(target_value),
		"pole": _spec_vector3((aim as Dictionary).get("pole", Vector3.ZERO)),
	}


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
	# A dry run reports the path it WOULD write and leaves the disk alone. The
	# pose still comes back in the reply, so the caller loses nothing.
	if _dry_run:
		return {"ok": true, "dry_run": true}
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
## virtual tip along the bone when it has no child. Read from the global *rest*
## frame, so a default marker does not land wherever the editor happened to be
## playing or posing.
func _bone_tip_3d(skeleton: Skeleton3D, bone_index: int) -> Dictionary:
	var children := skeleton.get_bone_children(bone_index)
	if not children.is_empty():
		return {"position": skeleton.global_transform * skeleton.get_bone_global_rest(children[0]).origin, "warning": null}
	var pose := skeleton.get_bone_global_rest(bone_index)
	var tip := pose.origin + pose.basis.y.normalized() * 0.1
	return {
		"position": skeleton.global_transform * tip,
		"warning": "the end bone '%s' has no child bone, so the target uses a 10 cm virtual tip - move it where it belongs" % skeleton.get_bone_name(bone_index),
	}


# --- modifier enum helpers --------------------------------------------------

## NodePath from a modifier (a child of `skeleton`) to a target node: IK and
## look-at settings resolve their paths against the modifier. Targets created by
## the same action are not in the tree yet, so their path is built by hand (they
## land directly under the edited scene root).
static func _modifier_target_path(skeleton: Skeleton3D, modifier: Node, target: Node, scene_root: Node) -> NodePath:
	if target.is_inside_tree() and modifier.is_inside_tree():
		return modifier.get_path_to(target)
	var up := str(skeleton.get_path_to(scene_root))
	var base := ".." if up.is_empty() else "../%s" % up
	return NodePath("%s/%s" % [base, str(target.name)])


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
	# Bones that only one side has, and mapped bones whose parents disagree:
	# both mean the modifier will drive a different shape than the source.
	var source_only: Array = []
	var target_only: Array = []
	for index in source.get_bone_count():
		var bone_name := str(source.get_bone_name(index))
		if target.find_bone(bone_name) < 0:
			source_only.append(bone_name)
	for index in target.get_bone_count():
		var bone_name := str(target.get_bone_name(index))
		if source.find_bone(bone_name) < 0:
			target_only.append(bone_name)
	var topology: Array = []
	for bone_name in mapped:
		var source_parent := source.get_bone_parent(source.find_bone(str(bone_name)))
		var target_parent := target.get_bone_parent(target.find_bone(str(bone_name)))
		var source_parent_name := "" if source_parent < 0 else str(source.get_bone_name(source_parent))
		var target_parent_name := "" if target_parent < 0 else str(target.get_bone_name(target_parent))
		if source_parent_name != target_parent_name:
			topology.append("%s: source parent '%s' vs target parent '%s'" % [
				str(bone_name), source_parent_name, target_parent_name])
	return {
		"profile": profile,
		"source": profile_source,
		"mapped": mapped,
		"unmapped": unmapped,
		"source_only": source_only,
		"target_only": target_only,
		"topology": topology,
	}


## Bones a map has to cover or the modifier cannot pose the body: the roles both
## skeletons actually have, hips first and then the leg chain. A role only the
## source has is not a gap - retargeting onto a reduced proxy skeleton (Godot
## explicitly supports dummy bones for that) is a legitimate setup.
func _retarget_missing_core(mapped: Array, source: Skeleton3D, target: Skeleton3D) -> Array:
	var source_names: Array = []
	for index in source.get_bone_count():
		source_names.append(str(source.get_bone_name(index)))
	var source_roles := (RigAnalysis.detect_roles(source_names) as Dictionary).get("roles", {}) as Dictionary
	var target_names: Array = []
	for index in target.get_bone_count():
		target_names.append(str(target.get_bone_name(index)))
	var target_roles := (RigAnalysis.detect_roles(target_names) as Dictionary).get("roles", {}) as Dictionary
	var required: Array = []
	for key in ["hips", "thigh_l", "thigh_r", "shin_l", "shin_r"]:
		var bone_name := str(source_roles.get(key, ""))
		if bone_name.is_empty() or not required.has(bone_name):
			continue
		# Both sides need the role, and it has to be the same bone, or there is
		# nothing to map it to.
		if str(target_roles.get(key, "")) != bone_name:
			continue
		required.append(bone_name)
	var missing: Array = []
	for bone_name in required:
		if not mapped.has(bone_name):
			missing.append(bone_name)
	return missing
