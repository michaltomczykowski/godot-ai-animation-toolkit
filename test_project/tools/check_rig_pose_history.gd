extends SceneTree

## Independently authored expectations for persisted poses and skeletons.
var failures: Array = []
var saved_states := 0
class Capture extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
func _initialize() -> void: _probe.call_deferred()
func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _load(label: String, family: String) -> Node:
	var path := "user://rig_%s_history_%s.tscn" % [family, label]
	if not ResourceLoader.exists(path):
		failures.append(label + " missing " + path)
		return null
	var scene := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(scene)
	saved_states += 1
	return scene
func _pose(kind: String, mode: String, variant: String, state: String) -> void:
	var label := "%s_%s_%s_%s" % [kind, mode, variant, state]
	var scene := _load(label, "pose")
	if scene == null: return
	var skeleton := scene.get_node("RigPoseHistory/Skeleton")
	for i in 3:
		var angle: float = [0.5, -0.4, 0.7][i]
		var position := Vector3(i + 1.1, 2.2, 0)
		var scale := Vector3(1.2, 0.8, 1.1)
		if state == "redo":
			if variant in ["reset", "reset_blend"]:
				angle = [0.2, -0.1, 0.35][i]
				position = Vector3(i + 1, 2, 0)
				scale = Vector3.ONE
			if i == (1 if variant == "mirror" else 0):
				angle = -0.7 if variant == "mirror" else 0.65 if variant == "blend" else 0.5 if variant == "reset_blend" else 0.8
				position = Vector3(1.6, 1.7, 0) if variant == "mirror" else Vector3(1.25, 1.95, 0) if variant == "blend" else Vector3(1.2, 1.85, 0) if variant == "reset_blend" else Vector3(1.4, 1.7, 0)
				scale = Vector3(1.4, 0.7, 1.2) if variant == "blend" else Vector3(1.3, 0.8, 1.15) if variant == "reset_blend" else Vector3(1.6, 0.6, 1.3)
		if kind == "3d":
			_check(skeleton.get_bone_pose_rotation(i).angle_to(Quaternion(Vector3.BACK, angle)) < 0.001, label + " rotation " + str(i))
			_check(skeleton.get_bone_pose_position(i).is_equal_approx(position), label + " position " + str(i))
			_check(skeleton.get_bone_pose_scale(i).is_equal_approx(scale), label + " scale " + str(i))
			_check(skeleton.is_bone_enabled(i) == (i != 2), label + " enabled " + str(i))
			_check(skeleton.get_bone_meta(i, &"authored") == "keep", label + " metadata " + str(i))
		else:
			var bone: Bone2D = skeleton.get_bone(i)
			_check(is_equal_approx(bone.rotation, angle), label + " rotation " + str(i))
			_check(bone.position.is_equal_approx(Vector2(position.x, position.y)), label + " position " + str(i))
			_check(bone.scale.is_equal_approx(Vector2(scale.x, scale.y)), label + " scale " + str(i))
			_check(is_equal_approx(bone.get_length(), 10.0 + i), label + " length " + str(i))
			_check(bone.owner != null, label + " owner " + str(i))
	scene.free()
func _chain(kind: String, mode: String, variant: String, state: String) -> void:
	var label := "%s_%s_%s_%s" % [kind, mode, variant, state]
	var scene := _load(label, "chain")
	if scene == null: return
	var fixture := scene.get_node("RigChainHistory")
	var path := "Branch/Generated" if variant == "subtree" else "Skeleton" if variant == "append" else "Generated"
	var skeleton := fixture.get_node_or_null(path)
	if state == "undo":
		if variant != "append": _check(skeleton == null, label + " new skeleton absent")
		elif kind == "3d": _check(skeleton.get_bone_count() == 3 and skeleton.find_bone("tool") == -1, label + " appended bone absent")
		else: _check(skeleton.get_node_or_null("arm_L/tool") == null, label + " appended bone absent")
	else:
		_check(skeleton != null and skeleton.owner != null, label + " skeleton retained/owned")
		if skeleton != null:
			if kind == "3d":
				var index: int = skeleton.find_bone("Leaf" if variant == "subtree" else "tool")
				var rest := Transform3D(Basis(Vector3.BACK, 0.3).scaled(Vector3(1.4, 0.8, 1.2)), Vector3(1, 2, 3)) if variant == "subtree" else Transform3D(Basis.from_euler(Vector3(0, 0, PI / 6)).scaled(Vector3(1.4, 0.8, 1.2)), Vector3(0.5, 1, 0))
				_check(index >= 0, label + " bone exists")
				if index >= 0:
					_check(skeleton.get_bone_rest(index).is_equal_approx(rest), label + " rest")
					_check(skeleton.get_bone_parent(index) == (-1 if variant == "create" else 0), label + " hierarchy")
			else:
				var bone := skeleton.get_node_or_null("Branch/Leaf" if variant == "subtree" else "arm_L/tool" if variant == "append" else "tool") as Bone2D
				_check(bone != null and bone.owner != null, label + " bone retained/owned")
				if bone != null:
					var rest := Transform2D(0.3, Vector2(1.4, 0.8), 0.1, Vector2(1, 2)) if variant == "subtree" else Transform2D(PI / 6, Vector2(1.4, 0.8), 0, Vector2(0.5, 1))
					_check(bone.rest.is_equal_approx(rest) and bone.transform.is_equal_approx(rest), label + " rest/pose")
	if variant == "append":
		var original := fixture.get_node("Skeleton")
		if kind == "3d":
			_check(original.get_bone_meta(2, &"authored") == "keep" and not original.is_bone_enabled(2), label + " original metadata/enabled")
			_check(original.get_bone_pose_position(2).is_equal_approx(Vector3(3.1, 2.2, 0)), label + " original pose")
		else: _check(original.get_node("untouched").position.is_equal_approx(Vector2(3.1, 2.2)), label + " original pose")
	scene.free()
func _probe() -> void:
	var logger := Capture.new()
	OS.add_logger(logger)
	var mode := OS.get_cmdline_user_args()[0]
	for kind in ["3d", "2d"]:
		for state in ["undo", "redo"]:
			for variant in ["apply", "blend", "reset", "reset_blend", "mirror"]: _pose(kind, mode, variant, state)
			for variant in ["create", "append", "subtree"]: _chain(kind, mode, variant, state)
	OS.remove_logger(logger)
	print("RIG_POSE_HISTORY_RUNTIME=" + JSON.stringify({"saved_states": saved_states, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
