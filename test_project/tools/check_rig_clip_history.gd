extends SceneTree

## Authored playback expectations; no toolkit/test scripts are loaded here.
const OPS := ["pose_to_clip", "walk_cycle", "idle_breathing", "blink", "jumping_jack", "squat", "punch", "bake_pose_sequence"]
var failures: Array = []
var saved_states := 0
class Capture extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
func _initialize() -> void: _probe.call_deferred()
func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _rotation(skeleton: Skeleton3D, bone: String, expected: Quaternion, label: String) -> void:
	var actual := skeleton.get_bone_pose_rotation(skeleton.find_bone(bone))
	_check(actual.angle_to(expected) < 0.002, label + " rotation " + bone + " actual=" + str(actual) + " expected=" + str(expected))
func _play(player: AnimationPlayer, skeleton: Node, time: float) -> void:
	player.stop()
	if skeleton is Skeleton3D: skeleton.reset_bone_poses()
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.speed_scale = 1.0
	player.play("generated")
	player.seek(time, true, true)
func _authored(player: AnimationPlayer, skeleton: Node, op: String, kind: String, label: String) -> void:
	if kind == "2d":
		for time in [0.0, 0.25, 0.5, 0.75, 1.0]:
			_play(player, skeleton, time)
			_check(is_equal_approx(skeleton.get_node("arm_L").rotation, 0.2 + 0.6 * time), label + " played 2D rotation " + str(time))
		return
	var rig := skeleton as Skeleton3D
	if op == "pose_to_clip":
		for time in [0.0, 0.25, 0.5, 0.75, 1.0]:
			_play(player, rig, time)
			_rotation(rig, "arm_L", Quaternion(Vector3.BACK, -PI / 2 + 0.6 * time), label + " played pose " + str(time))
	elif op == "walk_cycle":
		for time in [0.0, 0.25, 0.5, 0.75, 1.0]:
			_play(player, rig, time)
			var angle: float = 25.0 * (1.0 - 4.0 * time if time <= 0.5 else 4.0 * time - 3.0)
			_rotation(rig, "thigh_L", Quaternion(Vector3.BACK, PI) * Quaternion(Vector3.RIGHT, deg_to_rad(angle)), label + " played stride " + str(time))
			var bob := 0.05 if time in [0.25, 0.75] else 0.0
			_check(rig.get_bone_pose_position(0).is_equal_approx(Vector3(0, 1.1 + bob, 0)), label + " played hip bob " + str(time))
	elif op == "idle_breathing":
		_play(player, rig, 0.35)
		_rotation(rig, "chest", Quaternion(Vector3.RIGHT, deg_to_rad(1.6)), label + " chest breath")
		_rotation(rig, "head", Quaternion(Vector3.RIGHT, deg_to_rad(-1.0)), label + " head counter move")
		_play(player, rig, 0.5)
		_check(rig.get_bone_pose_position(0).is_equal_approx(Vector3(0, 1.11, 0)), label + " breath hip lift")
	elif op == "blink":
		for record in [[0.0, 1.0], [0.2, 0.55], [0.4, 0.1], [0.55, 0.1], [1.0, 1.0]]:
			_play(player, rig, record[0])
			_check(rig.get_bone_pose_scale(rig.find_bone("eye")).is_equal_approx(Vector3(1, record[1], 1)), label + " played blink " + str(record[0]))
	elif op == "jumping_jack":
		_play(player, rig, 0.5)
		_rotation(rig, "arm_L", Quaternion(Vector3.BACK, deg_to_rad(-10)), label + " raised left arm")
		_rotation(rig, "arm_R", Quaternion(Vector3.BACK, deg_to_rad(10)), label + " raised right arm")
		_check(rig.get_bone_pose_position(0).is_equal_approx(Vector3(0, 1.14, 0)), label + " jump lift")
	elif op == "squat":
		for time in [0.35, 0.5, 0.65]:
			_play(player, rig, time)
			_check(rig.get_bone_pose_position(0).is_equal_approx(Vector3(0, 0.9, 0)), label + " squat depth " + str(time))
			for side in ["L", "R"]:
				var foot := rig.find_bone("foot_" + side)
				_check(rig.get_bone_global_pose(foot).origin.distance_to(rig.get_bone_global_rest(foot).origin) < 0.003, label + " planted ankle at held squat " + side + " " + str(time))
	elif op == "punch":
		for record in [[0.175, "L"], [0.675, "R"]]:
			_play(player, rig, record[0])
			var direction := (rig.get_bone_global_pose(rig.find_bone("arm_" + record[1])).basis * Vector3.UP).normalized()
			_check(direction.dot(Vector3.BACK) > 0.95, label + " extended punching arm " + str(record))
			_check(rig.get_bone_pose_position(0).is_equal_approx(Vector3(0, 1.05, 0)), label + " stance crouch")
	elif op == "bake_pose_sequence":
		for time in [0.0, 0.125, 0.25, 0.375, 0.5, 0.75, 1.0]:
			_play(player, rig, time)
			_rotation(rig, "hips", Quaternion(Vector3.RIGHT, 0.1 + 0.6 * time), label + " played bake " + str(time))
			_check(rig.get_bone_pose_position(0).is_equal_approx(Vector3(0.02, 1.13, 0)), label + " baked source position")
			_check(rig.get_bone_pose_scale(0).is_equal_approx(Vector3(1.1, 0.9, 1.05)), label + " baked source scale")
func _case(mode: String, kind: String, op: String, state: String) -> void:
	var label := "%s_%s_%s_%s" % [mode, kind, op, state]
	var path := "user://rig_clip_history_%s.tscn" % label
	if not ResourceLoader.exists(path):
		failures.append(label + " missing scene")
		return
	var scene := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(scene)
	saved_states += 1
	var fixture := scene.get_node("RigClipHistory")
	var skeleton := fixture.get_node("Character/Skeleton")
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	_check(player.root_node == NodePath("../../Character"), label + " root preserved")
	_check(player.has_animation("source/input") and player.has_animation("source/next"), label + " named source preserved")
	_check(player.get_node(player.root_node) == fixture.get_node("Character"), label + " root resolves")
	_check(player.has_animation_library("") == (mode != "missing_library" or state == "redo"), label + " default library existence")
	_check(player.has_animation("generated") == (state == "redo" or mode == "overwrite"), label + " generated existence")
	if kind == "3d":
		_rotation(skeleton, "hips", Quaternion(Vector3.RIGHT, 0.22), label + " persisted source pose")
		_check(skeleton.get_bone_pose_position(0).is_equal_approx(Vector3(0.02, 1.13, 0)), label + " persisted source position")
	else:
		_check(is_equal_approx(skeleton.get_node("arm_L").rotation, 0.22), label + " persisted 2D source")
	if state == "redo":
		var clip := player.get_animation("generated")
		_check(is_equal_approx(clip.length, 1.0) and clip.loop_mode == Animation.LOOP_NONE, label + " duration/loop")
		_check(clip.get_track_count() > 0, label + " nonempty clip")
		for index in clip.get_track_count():
			var track := clip.track_get_path(index)
			var target := player.get_node(player.root_node).get_node_or_null(NodePath(track.get_concatenated_names()))
			if kind == "3d":
				_check(target == skeleton and skeleton.find_bone(str(track.get_concatenated_subnames())) >= 0 and clip.track_get_type(index) in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D], label + " resolved bone track " + str(index))
			else:
				_check(target is Bone2D and track.get_concatenated_subnames() == "rotation" and clip.track_get_type(index) == Animation.TYPE_VALUE, label + " resolved 2D track")
		_authored(player, skeleton, op, kind, label)
	elif mode == "overwrite":
		_play(player, skeleton, 0.5)
		if kind == "3d": _rotation(skeleton, "hips", Quaternion(Vector3.RIGHT, 1.3), label + " original clip playback")
		else: _check(is_equal_approx(skeleton.get_node("arm_L").rotation, 1.3), label + " original 2D clip playback")
	scene.free()
func _probe() -> void:
	var logger := Capture.new()
	OS.add_logger(logger)
	var args := OS.get_cmdline_user_args()
	var mode := str(args[0]) if not args.is_empty() else "local"
	_check(mode in ["local", "overwrite", "missing_library", "instanced", "editable"], "known layout")
	for op in OPS:
		for state in ["undo", "redo"]: _case(mode, "3d", op, state)
	for state in ["undo", "redo"]: _case(mode, "2d", "pose_to_clip", state)
	OS.remove_logger(logger)
	print("RIG_CLIP_HISTORY_RUNTIME=" + JSON.stringify({"layout": mode, "saved_states": saved_states, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if saved_states == 18 and failures.is_empty() and logger.errors.is_empty() else 1)
