extends SceneTree
## Fresh native consumption of saved static pose/chain output; no authored clips.
func _initialize() -> void:
	_probe.call_deferred()

func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[1] not in ["pose_apply", "rig_chain"]:
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var skeleton := fixture.get_node("Dummy/Skeleton3D") as Skeleton3D
	var failures: Array[String] = []
	var worst := 0.0
	var response := 0.0
	var name := "B-upperArm.L" if args[1] == "pose_apply" else "repair_tool_tip"
	var bone := skeleton.find_bone(name)
	var parent := skeleton.find_bone("B-hand.R")
	if bone < 0 or parent < 0:
		failures.append("expected saved bone missing")
	else:
		var rest := skeleton.get_bone_rest(bone)
		if args[1] == "rig_chain":
			if skeleton.get_bone_parent(bone) != parent:
				failures.append("saved appended parent differs")
			worst = rest.origin.distance_to(Vector3(0, 0.05, 0))
			worst = maxf(worst, rest.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY))
			worst = maxf(worst, rest.basis.get_scale().distance_to(Vector3.ONE))
		var before := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
		if args[1] == "rig_chain":
			skeleton.set_bone_pose_rotation(parent, skeleton.get_bone_pose_rotation(parent) * Quaternion(Vector3.UP, 0.4))
		for _i in 6:
			skeleton.advance(0.1)
			await process_frame
			if not skeleton.is_bone_enabled(bone) or not skeleton.get_bone_pose(bone).is_finite():
				failures.append("saved bone disabled or nonfinite")
			worst = maxf(worst, skeleton.get_bone_pose_position(bone).distance_to(rest.origin))
			worst = maxf(worst, skeleton.get_bone_pose_scale(bone).distance_to(Vector3.ONE))
			if args[1] == "pose_apply":
				var expected_rotation := (rest.basis.get_rotation_quaternion() * Quaternion(Vector3.UP, 0.6)).normalized()
				worst = maxf(worst, skeleton.get_bone_pose_rotation(bone).angle_to(expected_rotation))
			else:
				# Godot 4 local pose already contains the rest offset.
				worst = maxf(worst, skeleton.get_bone_pose_rotation(bone).angle_to(Quaternion.IDENTITY))
				var expected := skeleton.get_bone_global_pose(parent) * skeleton.get_bone_pose(bone)
				var actual := skeleton.get_bone_global_pose(bone)
				worst = maxf(worst, expected.origin.distance_to(actual.origin))
				worst = maxf(worst, expected.basis.get_rotation_quaternion().angle_to(actual.basis.get_rotation_quaternion()))
				response = maxf(response, before.angle_to(actual.basis.get_rotation_quaternion()))
	if worst >= 0.001 or (args[1] == "rig_chain" and response <= 0.1):
		failures.append("saved native structure response differs")
	print("RIG_SAVED_STRUCTURE=" + JSON.stringify({"scene":args[0],"op":args[1],"bone":name,"bone_index":bone,"parent":"B-hand.R","parent_index":parent,"expected_angle":0.6,"samples":6,"worst_error":worst,"parent_response":response,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
