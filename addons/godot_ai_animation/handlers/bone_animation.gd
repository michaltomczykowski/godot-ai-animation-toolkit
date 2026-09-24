@tool
extends "res://addons/godot_ai_animation/handlers/animation_tool_base.gd"

## Shared bone-animation plumbing for the rig and motion handler families:
## skeleton/role resolution, loop-mode parsing, aim/knee pose math, and the one
## commit path that turns procedural bone keys into a clip. Pure curve/noise
## math lives in `spec/motion_drivers.gd`; this file only touches the live
## Skeleton3D.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const SpecModifiers := preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")
const RigAnalysis := preload("res://addons/godot_ai_animation/spec/rig_analysis.gd")

const _LOOP_MODES := {
	"none": Animation.LOOP_NONE,
	"linear": Animation.LOOP_LINEAR,
	"pingpong": Animation.LOOP_PINGPONG,
}


# --- skeleton / roles -------------------------------------------------------

static func _loop_mode(params: Dictionary) -> Dictionary:
	var mode := str(params.get("loop_mode", "none"))
	if not _LOOP_MODES.has(mode):
		return {"error": "Invalid loop_mode '%s'. Valid: %s" % [mode, ", ".join(_LOOP_MODES.keys())]}
	return {"ok": _LOOP_MODES[mode]}


## The torso chain a twist distribution walks: an explicit `spine_chain` param
## when given (validated against the skeleton, so a typo fails loudly instead of
## twisting a limb), otherwise detected from the bone parents. Returns
## `{"chain": [...]}` or an error. Shared by the rig and motion families.
static func resolve_spine_chain(params: Dictionary, skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	var explicit = params.get("spine_chain", [])
	if explicit is Array and not (explicit as Array).is_empty():
		var chain: Array = []
		var previous := -1
		for value in explicit:
			var name := str(value)
			var index := skeleton.find_bone(name)
			if index < 0:
				return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
					"spine_chain bone '%s' is not on this skeleton" % name)
			if previous >= 0 and skeleton.get_bone_parent(index) != previous:
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"spine_chain must be one parent chain, but '%s' does not follow '%s'"
						% [name, skeleton.get_bone_name(previous)])
			chain.append(name)
			previous = index
		return {"chain": chain}
	var parent_of := {}
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		parent_of[str(skeleton.get_bone_name(index))] = str(skeleton.get_bone_name(parent)) if parent >= 0 else ""
	return {"chain": RigAnalysis.spine_chain(parent_of, roles)}


## Bone roles for the procedural recipes: explicit `roles` overrides win, then a
## saved `profile` (name or res:// path), then name-based auto-detection
## (`spec/rig_analysis.gd`). Shared by the rig and motion families.
##
## Returns the role map, or `{"_error": <error dict>}` when `profile` names a
## file that cannot be read or is not a rig profile.
static func _resolve_roles(params: Dictionary, skeleton: Skeleton3D) -> Dictionary:
	var names: Array = []
	for index in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(index))
	var roles := RigAnalysis.detect_roles(names).roles as Dictionary
	var profile := _profile_roles(params.get("profile", null), names)
	if profile.has("error"):
		return {"_error": profile.error}
	for role in profile.roles:
		roles[str(role)] = str(profile.roles[role])
	var overrides = params.get("roles", {})
	if overrides is Dictionary:
		for role in overrides:
			roles[str(role)] = str((overrides as Dictionary)[role])
	return roles


## Load `profile` (inline dict, `res://` path, or a bare profile name) and keep
## the roles whose bones exist on this skeleton.
static func _profile_roles(profile, bone_names: Array) -> Dictionary:
	if profile == null:
		return {"roles": {}}
	var data
	if profile is Dictionary:
		data = profile
	else:
		var value := str(profile)
		if value.is_empty():
			return {"roles": {}}
		var path := value if value.ends_with(".json") else "%s/%s.json" % [RigAnalysis.PROFILE_DIR, value]
		if not FileAccess.file_exists(path):
			return {"error": ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Rig profile not found: %s. Save one with animation_inspect(op=\"rig_profile\", save=true)." % path)}
		var raw := FileAccess.get_file_as_string(path)
		data = JSON.parse_string(raw)
		if data == null:
			return {"error": ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "%s is not valid JSON" % path)}
	var parsed = RigAnalysis.profile_roles(data)
	if parsed.has("error"):
		return {"error": ErrorCodes.make(ErrorCodes.INVALID_PARAMS, str(parsed.error))}
	var known := {}
	for name in bone_names:
		known[str(name)] = true
	var roles := {}
	for role in parsed.roles:
		if known.has(str(parsed.roles[role])):
			roles[str(role)] = str(parsed.roles[role])
	return {"roles": roles}


# --- vector / pose math -----------------------------------------------------

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


static func axis_name_to_vector(axis: String) -> Vector3:
	match axis.to_lower():
		"x": return Vector3.RIGHT
		"y": return Vector3.UP
		"z": return Vector3.BACK
	return Vector3.ZERO


## The bone-local rotation that rotates a bone from its rest direction toward
## `target_dir` by `degrees` (clamped so it never rotates past the target).
## Negative degrees rotate away from the target. The bone is assumed to point
## along its local +Y at rest (Godot's bone convention).
static func _aim_delta(skeleton: Skeleton3D, bone_name: String, target_dir: Vector3, degrees: float) -> Quaternion:
	if is_zero_approx(degrees):
		return Quaternion.IDENTITY
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return Quaternion.IDENTITY
	var rest_dir := (skeleton.get_bone_global_rest(index).basis * Vector3.UP).normalized()
	var target := target_dir.normalized()
	var axis_world := rest_dir.cross(target)
	if axis_world.length_squared() < 0.00000001:
		return Quaternion.IDENTITY
	axis_world = axis_world.normalized()
	var limit := rad_to_deg(rest_dir.angle_to(target))
	var amount := minf(degrees, limit) if degrees > 0.0 else maxf(degrees, -limit)
	var desired_world := rest_dir.rotated(axis_world, deg_to_rad(amount))
	return _local_delta_toward(skeleton, index, desired_world)


## Convert a desired bone direction (skeleton space) into the pose rotation
## that produces it from the bone's rest, using the rest hierarchy.
static func _local_delta_toward(skeleton: Skeleton3D, bone_index: int, desired_world_dir: Vector3) -> Quaternion:
	var parent_basis := Basis.IDENTITY
	var parent := skeleton.get_bone_parent(bone_index)
	if parent >= 0:
		parent_basis = skeleton.get_bone_global_rest(parent).basis
	var desired_parent := (parent_basis.inverse() * desired_world_dir).normalized()
	var rest_rotation := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
	var desired_local := (rest_rotation.inverse() * desired_parent).normalized()
	return Quaternion(Vector3.UP, desired_local).normalized()


## Point a bone along `direction` (skeleton space) right now, keeping the
## current roll. Poses the bone's parents first when a chain is driven.
static func _point_bone(skeleton: Skeleton3D, bone_name: String, direction: Vector3) -> void:
	var index := skeleton.find_bone(bone_name)
	if index < 0 or direction.length_squared() < 0.000001:
		return
	var global_pose := skeleton.get_bone_global_pose(index)
	var current_dir := (global_pose.basis * Vector3.UP).normalized()
	var delta := Quaternion(current_dir, direction.normalized())
	var basis := (Basis(delta) * global_pose.basis).orthonormalized()
	skeleton.set_bone_global_pose(index, Transform3D(basis, global_pose.origin))


## Rest-relative rotation delta of a bone's current pose (identity at rest).
static func _pose_delta_rotation(skeleton: Skeleton3D, index: int) -> Quaternion:
	var rest_rotation := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	return (rest_rotation.inverse() * skeleton.get_bone_pose_rotation(index)).normalized()


## The direction a character faces, taken from the feet (ankle -> toe) so
## recipe targets are rig-relative. Falls back to +Z.
static func _forward_dir(skeleton: Skeleton3D, roles: Dictionary) -> Vector3:
	var foot := str(roles.get("foot_l", ""))
	var toe := str(roles.get("toe_l", ""))
	if foot.is_empty() or toe.is_empty():
		foot = str(roles.get("foot_r", ""))
		toe = str(roles.get("toe_r", ""))
	if foot.is_empty() or toe.is_empty():
		return Vector3(0, 0, 1)
	var foot_index := skeleton.find_bone(foot)
	var toe_index := skeleton.find_bone(toe)
	if foot_index < 0 or toe_index < 0:
		return Vector3(0, 0, 1)
	var direction := skeleton.get_bone_global_rest(toe_index).origin \
		- skeleton.get_bone_global_rest(foot_index).origin
	direction.y = 0.0
	if direction.length_squared() < 0.000001:
		return Vector3(0, 0, 1)
	return direction.normalized()


## The knee position for a two-bone leg so the ankle stays where it is:
## law of cosines in the plane spanned by the hip-ankle line and `forward`.
static func _knee_position(hip: Vector3, ankle: Vector3, upper: float, lower: float, forward: Vector3) -> Vector3:
	var to_ankle := ankle - hip
	var distance := clampf(to_ankle.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var direction := to_ankle.normalized()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(upper * upper - along * along, 0.0))
	var perpendicular := forward - direction * direction.dot(forward)
	if perpendicular.length_squared() < 0.000001:
		perpendicular = Vector3.UP.cross(direction)
	perpendicular = perpendicular.normalized()
	return hip + direction * along + perpendicular * height


## Snapshot every bone pose so a recipe can pose the skeleton temporarily.
static func _pose_snapshot(skeleton: Skeleton3D) -> Array:
	var snapshot: Array = []
	for index in skeleton.get_bone_count():
		snapshot.append({
			"rotation": skeleton.get_bone_pose_rotation(index),
			"position": skeleton.get_bone_pose_position(index),
			"scale": skeleton.get_bone_pose_scale(index),
		})
	return snapshot


static func _pose_restore(skeleton: Skeleton3D, snapshot: Array) -> void:
	for index in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(index, snapshot[index].rotation)
		skeleton.set_bone_pose_position(index, snapshot[index].position)
		skeleton.set_bone_pose_scale(index, snapshot[index].scale)


## Apply a clip spec to the skeleton at `time` (rest + sampled key values), so
## read-only probes and spring passes can pose the skeleton without a player.
static func _apply_spec_at(skeleton: Skeleton3D, spec: Dictionary, time: float) -> void:
	skeleton.reset_bone_poses()
	for track in spec.get("tracks", []):
		var type := int(track.get("type", -1))
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var index := skeleton.find_bone(ClipSpec.property_of(str(track.get("path", ""))))
		if index < 0:
			continue
		var value = SpecModifiers.sample_track(track, time)
		if value == null:
			continue
		match type:
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(index, value)
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(index, value)
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(index, value)


# --- procedural clip commit -------------------------------------------------

## Build the Animation for a procedurally keyed bone clip without committing
## it. `keys` maps bone names to
## {"rotation": [{time, delta}], "position": [{time, delta}], "scale": [{time, value}]}
## where rotation/position deltas are rest-relative. `markers` is an optional
## list of {name, time, color?} cues (footsteps, jump phases, ...).
##
## Returns `{anim, spec, track_root, bones, player, library, created_library}`,
## so a caller can bundle several clips into one undo action
## (`character_setup`), or an error dict.
func _build_procedural_animation(
	params: Dictionary, resolved: Dictionary, anim_name: String, length: float,
	loop_mode: int, keys: Dictionary, markers: Array = [],
) -> Dictionary:
	var player_resolved := _resolve_player(str(params.get("player_path", "")))
	if player_resolved.has("error"):
		return player_resolved
	var player: AnimationPlayer = player_resolved.player
	var library: AnimationLibrary = player_resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true
	var root_node := ValueCodec.player_root_node(player)
	if root_node == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The AnimationPlayer has no resolvable root_node")
	var track_root := str(root_node.get_path_to(resolved.node))
	if track_root.is_empty() or track_root == ".":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"The skeleton must live under the player's root_node")
	var skeleton: Skeleton3D = resolved.node
	var spec := ClipSpec.make(length, loop_mode)
	for marker in markers:
		var marker_name := str(marker.get("name", ""))
		if marker_name.is_empty():
			continue
		ClipSpec.add_marker(spec, marker_name, clampf(float(marker.get("time", 0.0)), 0.0, length),
			marker.get("color", Color(1, 1, 1, 1)))
	var used: Array = []
	for bone_name in keys:
		var index := skeleton.find_bone(str(bone_name))
		if index < 0:
			continue
		var entry: Dictionary = keys[bone_name]
		var rest := skeleton.get_bone_rest(index)
		var rest_rotation := rest.basis.get_rotation_quaternion()
		var closes := bool(entry.get("loop_close", true)) and loop_mode != Animation.LOOP_NONE
		var wrote := false
		if entry.has("rotation"):
			var rotation_keys: Array = []
			for key in entry.rotation:
				rotation_keys.append({
					"time": float(key.time),
					"value": (rest_rotation * (key.delta as Quaternion)).normalized(),
					"transition": str(key.get("transition", "ease_in_out")),
				})
			ClipSpec.align_quaternions(rotation_keys)
			if closes:
				ClipSpec.close_loop(rotation_keys, length)
			ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone_name], rotation_keys,
				Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
			wrote = true
		if entry.has("position"):
			var position_keys: Array = []
			for key in entry.position:
				position_keys.append({
					"time": float(key.time),
					"value": rest.origin + (key.delta as Vector3),
					"transition": str(key.get("transition", "ease_in_out")),
				})
			if closes:
				ClipSpec.close_loop(position_keys, length)
			ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone_name], position_keys,
				Animation.INTERPOLATION_LINEAR, Animation.TYPE_POSITION_3D)
			wrote = true
		if entry.has("scale"):
			var scale_keys: Array = []
			for key in entry.scale:
				scale_keys.append({
					"time": float(key.time),
					"value": key.value,
					"transition": str(key.get("transition", "ease_in_out")),
				})
			if closes:
				ClipSpec.close_loop(scale_keys, length)
			ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone_name], scale_keys,
				Animation.INTERPOLATION_LINEAR, Animation.TYPE_SCALE_3D)
			wrote = true
		if wrote:
			used.append(str(bone_name))
	var valid := SpecBuilder.validate(spec)
	if valid.has("error"):
		return valid
	return {
		"anim": SpecBuilder.to_animation(spec),
		"spec": spec,
		"track_root": track_root,
		"bones": used,
		"player": player,
		"library": library,
		"created_library": created_library,
	}


## Commit a procedurally built bone clip as one undo action (the cycle/recipe
## path). Builds through `_build_procedural_animation`, so a caller can also
## build without committing.
func _commit_procedural_clip(
	params: Dictionary, resolved: Dictionary, anim_name: String, length: float,
	loop_mode: int, keys: Dictionary, markers: Array = [], extra_props: Array = [],
) -> Dictionary:
	var built := _build_procedural_animation(params, resolved, anim_name, length, loop_mode, keys, markers)
	if built.has("error"):
		return built
	var existing := _existing_animation(built.library, anim_name, bool(params.get("overwrite", false)))
	if existing.has("error"):
		return existing.error
	_commit_animation_add("MCP: %s" % anim_name, built.player, built.library, built.created_library,
		anim_name, built.anim, existing.old_anim, extra_props)
	return {"data": {
		"player_path": str(params.get("player_path", "")),
		"skeleton_path": resolved.path,
		"animation_name": anim_name,
		"length": length,
		"loop_mode": ValueCodec.loop_mode_to_string(int(built.spec.loop_mode)),
		"track_count": (built.spec.tracks as Array).size(),
		"key_count": ClipSpec.total_key_count(built.spec),
		"bones": built.bones,
		"library_created": built.created_library,
		"overwritten": existing.old_anim != null,
		"undoable": true,
	}}
