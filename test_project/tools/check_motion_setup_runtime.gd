extends SceneTree

## Saved-scene playback probe for character_setup and secondary_motion.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("MOTION_SETUP_RUNTIME_FAIL: scene required")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("MOTION_SETUP_RUNTIME_FAIL: scene not loadable")
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton := fixture.get_node("Dummy/Skeleton3D") as Skeleton3D
	var tree := fixture.get_node_or_null("AnimationTree") as AnimationTree
	var failures: Array[String] = []
	if tree == null:
		print("MOTION_SETUP_RUNTIME_FAIL: saved tree missing")
		quit(1)
		return
	if tree.active:
		failures.append("tree should be inactive by request")
	if str(tree.root_motion_track) != "Dummy:position":
		failures.append("saved tree root motion path missing")
	if str(player.root_motion_track) != "Dummy:position":
		failures.append("saved player root motion path missing")
	var thigh := skeleton.find_bone("B-thigh.L")
	var initial := skeleton.get_bone_pose_rotation(thigh)
	tree.active = true
	tree.set("parameters/Base/blend_position", 0.7)
	var travel := 0.0
	for _step in 5:
		tree.advance(0.1)
		travel += tree.get_root_motion_position().length()
	var thigh_change := initial.angle_to(skeleton.get_bone_pose_rotation(thigh))
	if thigh_change < 0.001:
		failures.append("active tree did not pose the walking thigh")
	if travel < 0.01:
		failures.append("active tree did not extract root translation")
	tree.active = false
	var walk := player.get_animation("walk")
	var jaw_track := walk.find_track(NodePath("Dummy/Skeleton3D:B-jaw"), Animation.TYPE_ROTATION_3D)
	var jaw_range := 0.0
	var jaw_first_angle := 0.0
	var jaw_rest_angle := 0.0
	var jaw_play_error := 0.0
	if jaw_track < 0:
		failures.append("spring jaw track missing")
	else:
		var jaw := skeleton.find_bone("B-jaw")
		var first := walk.track_get_key_value(jaw_track, 0) as Quaternion
		jaw_first_angle = first.angle_to(Quaternion.IDENTITY)
		jaw_rest_angle = skeleton.get_bone_rest(jaw).basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)
		for key in walk.track_get_key_count(jaw_track):
			var expected := walk.track_get_key_value(jaw_track, key) as Quaternion
			jaw_range = maxf(jaw_range, first.angle_to(expected))
			if key == 1:
				player.play("walk")
				player.seek(walk.track_get_key_time(jaw_track, key), true)
				player.advance(0.0)
				jaw_play_error = skeleton.get_bone_pose_rotation(jaw).angle_to(expected)
		if jaw_range < 0.001:
			failures.append("spring jaw has no motion")
		if jaw_play_error > 0.02:
			failures.append("spring jaw did not play its saved key")
	print("MOTION_SETUP_RUNTIME=" + JSON.stringify({"scene": args[0],
		"tree_active_saved": false, "thigh_change": thigh_change,
		"root_extraction": travel, "jaw_range": jaw_range,
		"jaw_first_angle": jaw_first_angle, "jaw_rest_angle": jaw_rest_angle,
		"jaw_play_error": jaw_play_error, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
