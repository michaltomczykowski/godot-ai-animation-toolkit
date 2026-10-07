extends SceneTree

const Native := preload("res://tools/modifier_native_reference.gd")

## Engine-only saved playback; intentionally no toolkit/test imports.
class CaptureErrors extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
class Witness extends SkeletonModifier3D:
	func _process_modification_with_delta(_delta: float) -> void: pass
var failures: Array[String] = []
var rows: Array = []
var saved_states := 0
var logger := CaptureErrors.new()
var native_states := 0
var stack_states := 0
var probe_centers := false
var probe_jacobian := false
func _properties(node: Object) -> Dictionary:
	var result := {}
	for property in node.get_property_list():
		var key := str(property.name)
		if int(property.usage) & PROPERTY_USAGE_STORAGE and (key.contains("/") or key in ["active", "influence", "mutable_bone_axes", "bone_name", "target_node", "origin_from", "origin_bone_name", "origin_external_node", "forward_axis", "primary_rotation_axis", "use_secondary_rotation", "use_angle_limitation", "primary_limit_angle", "secondary_limit_angle", "relative", "duration", "enable_flags", "use_global_pose"]): result[key] = node.get(key)
	return result
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _poses(skeleton: Skeleton3D) -> Array:
	var result: Array = []
	for i in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(i))
	return result
func _restore(skeleton: Skeleton3D, poses: Array) -> void:
	for i in poses.size():
		skeleton.set_bone_pose_position(i, poses[i].origin)
		skeleton.set_bone_pose_rotation(i, poses[i].basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(i, poses[i].basis.get_scale())
func _difference(a: Array, b: Array) -> float:
	if a.size() != b.size(): return INF
	var error := 0.0
	for i in a.size():
		if a[i].is_equal_approx(b[i]): continue
		error = maxf(error, a[i].origin.distance_to(b[i].origin))
		error = maxf(error, a[i].basis.get_rotation_quaternion().angle_to(b[i].basis.get_rotation_quaternion()))
		error = maxf(error, a[i].basis.get_scale().distance_to(b[i].basis.get_scale()))
	return error
func _effector(source: Skeleton3D, modifier: SkeletonModifier3D) -> Vector3:
	var index: int = modifier.get_end_bone(0)
	var pose := source.get_bone_global_pose(index)
	if modifier is TwoBoneIK3D and modifier.is_using_virtual_end(0):
		var rest := source.get_bone_global_rest(index)
		var parent := source.get_bone_global_rest(source.get_bone_parent(index))
		var axis := (rest.basis.inverse() * (rest.origin - parent.origin)).normalized()
		pose.origin += pose.basis * axis * modifier.get_end_bone_length(0)
	return source.global_transform * pose.origin
func _sample(source: Skeleton3D, observed: Skeleton3D, modifier: SkeletonModifier3D, witness: Witness, poses: Array, active: bool, weight: float, fps: int = 60) -> Dictionary:
	modifier.active = active
	modifier.influence = weight
	_restore(source, poses)
	if modifier is SpringBoneSimulator3D: modifier.reset()
	var result := {"raw_count": 0, "final_count": 0, "skin_count": 0, "raw": [], "final": [], "skin": [], "input": [], "globals": [], "endpoint": Vector3.ZERO, "collision_checks": 0, "penetration": 0.0}
	var raw := func():
		result.raw_count += 1
		result.raw = _poses(observed)
	var final := func():
		result.final_count += 1
		result.final = _poses(observed)
		result.globals = []
		for i in observed.get_bone_count(): result.globals.append(observed.global_transform * observed.get_bone_global_pose(i))
		if modifier is IKModifier3D and not modifier is SplineIK3D: result.endpoint = _effector(observed, modifier)
		if modifier is SpringBoneSimulator3D and active and is_equal_approx(weight, 1.0):
			for setting in modifier.get_setting_count():
				var collisions: Array = []
				if modifier.are_all_child_collisions_enabled(setting):
					collisions = modifier.get_children().filter(func(child): return child is SpringBoneCollisionSphere3D)
					for excluded in modifier.get_exclude_collision_count(setting): collisions.erase(modifier.get_node(modifier.get_exclude_collision_path(setting, excluded)))
				else:
					for c in modifier.get_collision_count(setting): collisions.append(modifier.get_node(modifier.get_collision_path(setting, c)))
				for joint in modifier.get_joint_count(setting) - 1:
					var tail: Vector3 = result.globals[modifier.get_joint_bone(setting, joint + 1)].origin
					for collider in collisions:
						result.collision_checks += 1
						var separation: float = tail.distance_to(collider.global_position) - collider.radius - modifier.get_joint_radius(setting, joint)
						result.penetration = maxf(result.penetration, -separation)
	var skin := func():
		result.skin_count += 1
		result.skin = _poses(observed)
	modifier.modification_processed.connect(raw)
	witness.modification_processed.connect(final)
	source.skeleton_updated.connect(skin)
	var frames := maxi(1, fps / 4) if modifier is SpringBoneSimulator3D else 1
	# Native iterative solvers default to four 2-degree-limited iterations per
	# step, retaining solver state between steps. Measure settled tracking after
	# four seconds, rather than requiring a large target change in one frame.
	if modifier is IterateIK3D: frames = fps * 4
	if modifier is LookAtModifier3D and modifier.duration > 0: frames = int(ceil(modifier.duration * fps)) + 2
	for frame in frames:
		_restore(source, poses)
		if modifier is SpringBoneSimulator3D:
			source.set_bone_pose_rotation(0, poses[0].basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, 0.15 * sin(float(frame) / fps * TAU)))
		result.input = _poses(source)
		source.advance(1.0 / fps)
		source.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	modifier.modification_processed.disconnect(raw)
	witness.modification_processed.disconnect(final)
	source.skeleton_updated.disconnect(skin)
	return result
func _settings(row: Dictionary, source: Skeleton3D, modifier: SkeletonModifier3D, label: String) -> void:
	var params: Dictionary = row.params
	_check(modifier.active == bool(params.get("active", false)), label + " saved active")
	match row.op:
		"ik_setup":
			_check(modifier.get_root_bone_name(0) == str(params.chain[0]), label + " root bone")
			var target: Node = modifier.get_node_or_null(modifier.get_path_3d(0) if params.kind == "spline" else modifier.get_target_node(0))
			_check(target is Path3D if params.kind == "spline" else target is Node3D, label + " saved target resolves")
			if params.kind == "two_bone": _check(modifier.get_node_or_null(modifier.get_pole_node(0)) is Node3D, label + " saved pole resolves")
		"look_at_setup":
			_check(modifier.get_node_or_null(modifier.target_node) is Node3D, label + " target resolves")
			_check(modifier.use_secondary_rotation == bool(params.get("use_secondary_rotation", false)), label + " secondary rotation matches request/default")
			if str(params.get("origin_from", "self")) == "external_node": _check(modifier.get_node_or_null(modifier.origin_external_node) is Node3D, label + " origin resolves")
		"spring_setup":
			_check(modifier.get_setting_count() == params.springs.size(), label + " spring settings")
			for i in params.springs.size():
				_check(modifier.get_root_bone_name(i) == params.springs[i].root_bone, label + " spring root")
				_check(modifier.get_joint_count(i) >= 2, label + " generated spring joints")
				for c in modifier.get_collision_count(i): _check(modifier.get_node_or_null(modifier.get_collision_path(i, c)) is SpringBoneCollision3D, label + " collision resolves")
		"retarget_setup":
			_check(modifier.profile != null and modifier.get_child_count() >= 1, label + " retarget useful profile/child")
		"twist_setup":
			_check(modifier.get_setting_count() == 1, label + " twist settings")
func _play(row: Dictionary, state: String, reference: bool = false, fps: int = 60) -> Array:
	var label := str(row.id) + "/" + state + ("/native" if reference else "") + "/" + str(fps)
	var packed := ResourceLoader.load(row.states[state], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_check(packed != null, label + " saved scene exists")
	if packed == null: return []
	var scene := packed.instantiate()
	var authored_inputs := {}
	for rig in scene.find_children("*", "Skeleton3D", true, false):
		authored_inputs[rig] = _poses(rig)
		rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	root.add_child(scene)
	var source := scene.get_node(row.source) as Skeleton3D
	var peer := scene.get_node(row.peer) as Skeleton3D
	source.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	peer.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var peer_before := _poses(peer)
	var modifier := scene.get_node_or_null(row.modifier) as SkeletonModifier3D
	await process_frame
	for rig in authored_inputs:
		_check(_difference(authored_inputs[rig], _poses(rig)) < 0.001, label + " authored input survives tree entry " + str(rig.name))
	if state == "undo":
		_check(modifier != null if str(row.variant).begins_with("existing") else modifier == null, label + " modifier existence after Undo")
		source.advance(1.0 / 60)
		source.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		_check(_difference(peer_before, _poses(peer)) < 0.001, label + " Undo peer stable")
		rows.append({"id": row.id, "state": state, "fps": fps, "native": false, "effect": 0.0, "samples": 1})
		saved_states += 1
		scene.free()
		return []
	_check(modifier != null, label + " modifier exists")
	if modifier == null:
		scene.free()
		return []
	if probe_jacobian:
		# Build the disabled native solver from a supported saved fixture. This
		# probe remains reproducible without older local Jacobian scene files.
		modifier = Native.replace(row, source, modifier, "JacobianIK3D")
		await process_frame
		Native.finish(modifier)
	if probe_centers:
		source.rotation += Vector3(0.0, 1.1, 0.6)
		source.reset_physics_interpolation()
	if probe_centers and row.op == "spring_setup" and str(row.variant).ends_with("no_collision"):
		var collision := SpringBoneCollisionSphere3D.new()
		collision.name = "NativeProbeCollider"
		modifier.add_child(collision)
	if reference:
		var expected_saved := _properties(modifier)
		modifier = Native.replace(row, source, modifier)
		await process_frame
		Native.finish(modifier)
		var configured := _properties(modifier)
		for key in configured:
			# Generated joint lists are evaluated below after the first step.
			if key.contains("/joints/") or key.ends_with("/joint_count"): continue
			var equal: bool = expected_saved.get(key).is_equal_approx(configured[key]) if configured[key] is Vector3 else expected_saved.get(key) == configured[key]
			_check(equal, label + " requested native property " + key + " " + str(expected_saved.get(key)) + " vs " + str(configured[key]))
	_settings(row, source, modifier, label)
	var observed := scene.get_node(row.receiver) as Skeleton3D if row.op == "retarget_setup" else source
	observed.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var witness := Witness.new()
	witness.name = "EnginePlaybackWitness"
	source.add_child(witness)
	var input := _poses(source)
	if row.op == "twist_setup":
		var end: int = modifier.get_end_bone(0)
		if not modifier.is_end_bone_extended(0): end = source.get_bone_parent(end)
		source.set_bone_pose_rotation(end, source.get_bone_rest(end).basis.get_rotation_quaternion() * Quaternion(Vector3.UP, 0.7))
		input = _poses(source)
	if row.op == "spring_setup":
		modifier.external_force = Vector3(0.7, 0, 0.4)
		if not modifier.get_children().is_empty():
			var collider := modifier.get_children()[0] as SpringBoneCollisionSphere3D
			var child: int = modifier.get_joint_bone(0, 1)
			var tail: Vector3 = source.global_transform * source.get_bone_global_pose(child).origin
			var start: Vector3 = source.global_transform * source.get_bone_global_pose(modifier.get_joint_bone(0, 0)).origin
			var side: Vector3 = (tail - start).normalized().cross(Vector3.FORWARD).normalized()
			if side.length() < 0.1: side = Vector3.UP
			collider.radius = source.get_bone_rest(child).origin.length() * 0.25
			# Approach a reachable obstacle from outside. A fixed 12 cm sphere
			# engulfed the dummy's much shorter forearm and tested an impossible
			# initial configuration rather than collision response.
			collider.global_position = tail + side * (collider.radius + modifier.get_joint_radius(0, 0)) * 1.05
			modifier.external_force = side * 0.7
			collider.reset_physics_interpolation()
	if row.op == "retarget_setup":
		source.set_bone_pose_rotation(1, source.get_bone_rest(1).basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, 0.6))
		source.set_bone_pose_position(1, source.get_bone_rest(1).origin + Vector3(0.15, 0.04, -0.03))
		source.set_bone_pose_scale(1, Vector3(1.2, 0.9, 1.1))
		input = _poses(source)
	if row.op == "look_at_setup":
		var target := modifier.get_node(modifier.target_node) as Node3D
		var origin := source.global_transform * source.get_bone_global_rest(modifier.bone).origin
		if modifier.origin_from == LookAtModifier3D.ORIGIN_FROM_SPECIFIC_BONE: origin = source.global_transform * source.get_bone_global_pose(modifier.origin_bone).origin
		if modifier.origin_from == LookAtModifier3D.ORIGIN_FROM_EXTERNAL_NODE: origin = modifier.get_node(modifier.origin_external_node).global_position
		target.global_position = origin + source.global_basis * Vector3(0.7, 0.4, 1.0)
		target.reset_physics_interpolation()
	if row.op == "ik_setup" and row.params.kind != "spline":
		var target := modifier.get_node(modifier.get_target_node(0)) as Node3D
		if not row.params.has("target_path"):
			_check(target.global_position.distance_to(_effector(source, modifier)) < 0.0001, label + " generated target uses effector origin")
		var root_position := source.global_transform * source.get_bone_global_pose(modifier.get_root_bone(0)).origin
		var direction := _effector(source, modifier) - root_position
		var side := direction.normalized().cross(Vector3.FORWARD).normalized()
		if side.length() < 0.1: side = Vector3.RIGHT
		target.global_position = root_position + direction * 0.7 + side * direction.length() * 0.15
		target.reset_physics_interpolation()
	var observed_before := _poses(observed)
	var off := _sample(source, observed, modifier, witness, input, false, 1.0, fps)
	_check(off.raw_count == 0 and off.final_count >= 1 and off.skin_count >= 1, label + " inactive signals observed")
	_check(_difference(off.final, off.input if observed == source else observed_before) < 0.001, label + " inactive inert")
	var full := _sample(source, observed, modifier, witness, input, true, 1.0, fps)
	_check(full.raw_count >= 1 and full.final_count >= 1 and full.skin_count >= 1, label + " active signals observed")
	_check(_difference(full.final, full.skin) < 0.001, label + " witness agrees with skin pose")
	if modifier is SpringBoneSimulator3D:
		# Native collision projection is followed by a bone-length constraint.
		# Require a bounded 3 mm residual at every sampled step, and verify below
		# that collisions actually change the trajectory.
		_check(full.penetration < 0.003, label + " spring sphere separation penetration=" + str(full.penetration))
		if not modifier.get_children().is_empty(): _check(full.collision_checks > 0, label + " spring collision samples present")
	for pose in full.final:
		_check(pose.origin.is_finite() and pose.basis.x.is_finite() and pose.basis.y.is_finite() and pose.basis.z.is_finite(), label + " finite output")
	var boundary_noop: bool = row.op == "twist_setup" and str(row.variant).begins_with("weighted_")
	_check(_difference(off.final, full.final) > 0.001 or boundary_noop, label + " active modifier has effect")
	if modifier is LookAtModifier3D and modifier.use_secondary_rotation and not modifier.relative and not modifier.use_angle_limitation:
		var axes := {SkeletonModifier3D.BONE_AXIS_PLUS_X: Vector3.RIGHT, SkeletonModifier3D.BONE_AXIS_MINUS_X: Vector3.LEFT, SkeletonModifier3D.BONE_AXIS_PLUS_Y: Vector3.UP, SkeletonModifier3D.BONE_AXIS_MINUS_Y: Vector3.DOWN, SkeletonModifier3D.BONE_AXIS_PLUS_Z: Vector3.BACK, SkeletonModifier3D.BONE_AXIS_MINUS_Z: Vector3.FORWARD}
		var axis: Vector3 = axes[modifier.forward_axis]
		var pose: Transform3D = full.globals[modifier.bone]
		var origin: Vector3 = pose.origin
		if modifier.origin_from == LookAtModifier3D.ORIGIN_FROM_SPECIFIC_BONE: origin = full.globals[modifier.origin_bone].origin
		if modifier.origin_from == LookAtModifier3D.ORIGIN_FROM_EXTERNAL_NODE: origin = modifier.get_node(modifier.origin_external_node).global_position
		var direction: Vector3 = (modifier.get_node(modifier.target_node).global_position - origin).normalized()
		_check((pose.basis * axis).normalized().angle_to(direction) < 0.003, label + " requested forward axis aims at target")
	if row.op == "ik_setup" and row.params.kind != "spline":
		var target := modifier.get_node(modifier.get_target_node(0)) as Node3D
		var chain_length := 0.0
		var bone: int = modifier.get_end_bone(0)
		var first: int = modifier.get_root_bone(0)
		while bone != first and bone >= 0:
			chain_length += source.get_bone_rest(bone).origin.length()
			bone = source.get_bone_parent(bone)
		if modifier is TwoBoneIK3D and modifier.is_using_virtual_end(0): chain_length += modifier.get_end_bone_length(0)
		_check(full.endpoint.distance_to(target.global_position) < chain_length * 0.005, label + " reachable IK target error=" + str(full.endpoint.distance_to(target.global_position)))
	var collision_response := 0.0
	if modifier is SpringBoneSimulator3D and not modifier.get_children().is_empty():
		for collider in modifier.get_children(): collider.global_position += Vector3(10, 10, 10)
		var unobstructed := _sample(source, observed, modifier, witness, input, true, 1.0, fps)
		collision_response = _difference(full.final, unobstructed.final)
		_check(collision_response > 0.001, label + " collision changes trajectory")
	if row.op != "retarget_setup":
		for weight in [0.0, 0.5]:
			var sample := _sample(source, observed, modifier, witness, input, true, weight, fps)
			for i in input.size():
				var expected := Transform3D(Basis(sample.input[i].basis.get_rotation_quaternion().slerp(sample.raw[i].basis.get_rotation_quaternion(), weight)).scaled(sample.input[i].basis.get_scale().lerp(sample.raw[i].basis.get_scale(), weight)), sample.input[i].origin.lerp(sample.raw[i].origin, weight))
				_check(sample.final[i].is_equal_approx(expected), label + " influence=" + str(weight) + " bone=" + str(i))
	_check(_difference(peer_before, _poses(peer)) < 0.001, label + " peer isolated during playback")
	rows.append({"id": row.id, "state": state, "fps": fps, "native": reference, "effect": _difference(off.final, full.final), "samples": full.final_count, "collision_checks": full.collision_checks, "penetration": full.penetration, "collision_response": collision_response})
	var result: Array = full.final
	if reference: native_states += 1
	else: saved_states += 1
	scene.free()
	return result
func _run() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("user://rig_modifier_history.json"))
	_check(manifest is Dictionary, "manifest exists")
	var args := OS.get_cmdline_user_args()
	var required: Array = manifest.get("cases", []) if manifest is Dictionary else []
	probe_centers = not args.is_empty() and args[0] == "probe_centers"
	probe_jacobian = not args.is_empty() and args[0] == "probe_jacobian"
	if probe_centers: required = required.filter(func(row): return row.op == "spring_setup" and row.variant in ["world_origin_listed", "node_no_collision", "bone_no_collision"])
	if probe_jacobian:
		required = required.filter(func(row): return row.op == "ik_setup" and row.params.kind == "ccdik")
		for row in required:
			row.id = str(row.id).replace("ccdik", "jacobian")
			row.params.kind = "jacobian"
	_check(not required.is_empty(), "manifest is nonempty")
	for row in required:
		if not args.is_empty() and not probe_centers and not probe_jacobian and row.op != args[0]: continue
		for fps in [30, 60, 120]:
			if row.op == "stack":
				var first := await _stack(row, "do", fps, false)
				var native := await _stack(row, "do", fps, true)
				var repeated := await _stack(row, "redo", fps, false)
				await _stack(row, "undo", fps, false)
				_check(_difference(first, native) < 0.001, str(row.id) + " ordered native playback equivalent")
				_check(_difference(first, repeated) < 0.001, str(row.id) + " ordered Do/Redo equivalent")
				continue
			var first: Array = await _play(row, "do", false, fps)
			var native: Array = await _play(row, "do", true, fps)
			_check(_difference(first, native) < 0.001, str(row.id) + " independent native playback matches request error=" + str(_difference(first, native)))
			await _play(row, "undo", false, fps)
			var repeated: Array = await _play(row, "redo", false, fps)
			_check(_difference(first, repeated) < 0.001, str(row.id) + " Do/Redo playback equivalent")
	OS.remove_logger(logger)
	print("RIG_MODIFIER_HISTORY_RUNTIME=" + JSON.stringify({"failures": failures, "engine_errors": logger.errors, "saved_states": saved_states, "native_states": native_states, "stack_states": stack_states, "rows": rows}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)

func _stack(row: Dictionary, state: String, fps: int, reference: bool) -> Array:
	var label := str(row.id) + "/" + state + "/" + str(fps) + ("/native" if reference else "")
	var scene := (ResourceLoader.load(row.states[state], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(scene)
	var source := scene.get_node(row.source) as Skeleton3D
	var peer := scene.get_node(row.peer) as Skeleton3D
	source.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	peer.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var peer_before := _poses(peer)
	var modifiers: Array[SkeletonModifier3D] = []
	for stage in row.stack:
		var modifier := scene.get_node_or_null(stage.modifier) as SkeletonModifier3D
		_check(modifier == null if state == "undo" else modifier != null, label + " stage existence " + str(stage.op))
		if modifier != null: modifiers.append(modifier)
	await process_frame
	var input := _poses(source)
	if state == "undo":
		source.advance(1.0 / fps)
		source.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		_check(_difference(input, _poses(source)) < 0.001, label + " Undo inert")
		rows.append({"id": row.id, "state": state, "fps": fps, "native": reference, "samples": 1})
		saved_states += 1
		stack_states += 1
		scene.free()
		return []
	if reference:
		for i in modifiers.size(): modifiers[i] = Native.replace(row.stack[i], source, modifiers[i])
		await process_frame
		for modifier in modifiers: Native.finish(modifier)
	for i in modifiers.size():
		var modifier := modifiers[i]
		_settings(row.stack[i], source, modifier, label)
		modifier.active = true
		modifier.influence = float(row.last_influence) if i == modifiers.size() - 1 else 1.0
		if modifier is TwoBoneIK3D:
			var target := modifier.get_node(modifier.get_target_node(0)) as Node3D
			var from := source.global_transform * source.get_bone_global_pose(modifier.get_root_bone(0)).origin
			target.global_position = from + (_effector(source, modifier) - from) * 0.7 + source.global_basis.x * 0.1
			target.reset_physics_interpolation()
		if modifier is LookAtModifier3D:
			var target := modifier.get_node(modifier.target_node) as Node3D
			var origin := modifier.get_node(modifier.origin_external_node) as Node3D
			target.global_position = origin.global_position + source.global_basis * Vector3(0.7, 0.4, 1.0 if modifier.bone_name == "head" else -1.0)
			target.reset_physics_interpolation()
		if modifier is SpringBoneSimulator3D:
			modifier.external_force = Vector3(0.7, 0, 0.4)
			modifier.reset()
	var witness := Witness.new()
	source.add_child(witness)
	var capture := {"order": [], "raw": {}, "final": [], "skin": [], "samples": 0}
	for i in modifiers.size():
		var modifier := modifiers[i]
		var stage_index := i
		modifier.modification_processed.connect(func():
			capture.order.append(stage_index)
			capture.raw[stage_index] = _poses(source)
			if modifier is TwoBoneIK3D:
				var target := modifier.get_node(modifier.get_target_node(0)) as Node3D
				_check(_effector(source, modifier).distance_to(target.global_position) < 0.0045, label + " IK stage reaches before downstream modifiers"))
	witness.modification_processed.connect(func():
		capture.final = _poses(source)
		capture.samples += 1)
	source.skeleton_updated.connect(func(): capture.skin = _poses(source))
	for frame in fps:
		_restore(source, input)
		source.set_bone_pose_rotation(0, input[0].basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, 0.1 * sin(float(frame) / fps * TAU)))
		source.set_bone_pose_rotation(2, input[2].basis.get_rotation_quaternion() * Quaternion(Vector3.UP, 0.4))
		var start := _poses(source)
		capture.order.clear()
		source.advance(1.0 / fps)
		source.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		_check(capture.order == range(modifiers.size()), label + " exact signal evaluation order")
		var incoming: Array = capture.raw[modifiers.size() - 2] if modifiers.size() > 1 else start
		var raw: Array = capture.raw[modifiers.size() - 1]
		for i in start.size():
			var weight: float = row.last_influence
			var expected := Transform3D(Basis(incoming[i].basis.get_rotation_quaternion().slerp(raw[i].basis.get_rotation_quaternion(), weight)).scaled(incoming[i].basis.get_scale().lerp(raw[i].basis.get_scale(), weight)), incoming[i].origin.lerp(raw[i].origin, weight))
			_check(capture.final[i].is_equal_approx(expected), label + " final weight applied once bone=" + str(i))
			_check(capture.final[i].origin.is_finite() and capture.final[i].basis.x.is_finite(), label + " finite stack pose")
		_check(_difference(capture.final, capture.skin) < 0.001, label + " final witness agrees with skin")
	_check(capture.samples == fps, label + " all samples present")
	_check(_difference(input, capture.final) > 0.001, label + " stack effective")
	_check(_difference(peer_before, _poses(peer)) < 0.001, label + " stack peer isolated")
	rows.append({"id": row.id, "state": state, "fps": fps, "native": reference, "samples": capture.samples, "order": row.stack.map(func(stage): return stage.op), "last_influence": row.last_influence})
	if reference: native_states += 1
	else:
		saved_states += 1
		stack_states += 1
	var result: Array = capture.final
	scene.free()
	return result
