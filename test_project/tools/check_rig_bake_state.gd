extends SceneTree

## Fresh-engine expectations authored independently of the toolkit/clip specs.
var failures: Array = []
var saved_states := 0
class Capture extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
func _initialize() -> void: _probe.call_deferred()
func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _probe() -> void:
	var logger := Capture.new()
	OS.add_logger(logger)
	for state in ["unassigned", "paused", "stopped", "playing", "reverse", "zero_scale", "other_source", "section"]:
		for version in ["undo", "redo"]:
			var label: String = state + "_" + version
			var path := "user://rig_bake_state_%s.tscn" % label
			if not ResourceLoader.exists(path):
				failures.append(label + " missing saved state")
				continue
			var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			var scene := packed.instantiate()
			root.add_child(scene)
			saved_states += 1
			var skeleton := scene.get_node("BakeState/Skeleton") as Skeleton3D
			var player := scene.get_node("BakeState/AnimationPlayer") as AnimationPlayer
			var angle := 0.2 if state == "unassigned" else 0.27 if state == "other_source" else 0.18
			_check(skeleton.get_bone_pose_rotation(0).angle_to(Quaternion(Vector3.RIGHT, angle)) < 0.001, label + " persisted source rotation")
			_check(skeleton.get_bone_pose_position(0).is_equal_approx(Vector3(1.2, 2.3, 0)), label + " persisted position")
			_check(skeleton.get_bone_pose_scale(0).is_equal_approx(Vector3(1.2, 0.8, 1.1)), label + " persisted scale")
			_check(player.has_animation("source/input") and player.has_animation("source/next"), label + " named source library")
			_check(player.has_animation("generated") == (version == "redo"), label + " clip existence")
			if version == "redo" and player.has_animation("generated"):
				var clip := player.get_animation("generated")
				_check(is_equal_approx(clip.length, 0.5), label + " duration")
				for index in clip.get_track_count():
					var track_path := clip.track_get_path(index)
					var node := scene.get_node("BakeState").get_node_or_null(NodePath(track_path.get_concatenated_names()))
					_check(node == skeleton and str(track_path.get_concatenated_subnames()) == "arm", label + " track resolves " + str(index))
				player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				player.play("generated")
				for time in [0.0, 0.125, 0.25, 0.375, 0.5]:
					player.seek(time, true)
					_check(skeleton.get_bone_pose_rotation(0).angle_to(Quaternion(Vector3.RIGHT, float(time) * 0.6)) < 0.001, label + " played rotation " + str(time))
					_check(skeleton.get_bone_pose_position(0).is_equal_approx(Vector3(1.2, 2.3, 0)), label + " played position " + str(time))
			scene.free()
	OS.remove_logger(logger)
	print("RIG_BAKE_STATE_RUNTIME=" + JSON.stringify({"saved_states": saved_states, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if saved_states == 16 and failures.is_empty() and logger.errors.is_empty() else 1)
