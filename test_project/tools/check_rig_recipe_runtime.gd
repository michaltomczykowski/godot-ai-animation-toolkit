extends SceneTree

## Play saved rig recipes through AnimationPlayer and compare typed bone tracks.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("RIG_RECIPE_FAIL: pass scene and operation after --")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("RIG_RECIPE_FAIL: saved scene did not load")
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton := fixture.get_node("Dummy/Skeleton3D") as Skeleton3D
	var op := args[1]
	var animation := player.get_animation(op)
	if animation == null:
		print("RIG_RECIPE_FAIL: missing saved clip " + op)
		quit(1)
		return
	var failures: Array = []
	var checked := 0
	var moving := 0
	var worst := 0.0
	for track_index in animation.get_track_count():
		var path := animation.track_get_path(track_index)
		if path.get_subname_count() != 1:
			failures.append("unexpected bone track path: %s" % str(path))
			continue
		var bone := skeleton.find_bone(str(path.get_subname(0)))
		if bone < 0:
			failures.append("missing bone: %s" % str(path))
			continue
		var key_index := mini(1, animation.track_get_key_count(track_index) - 1)
		if animation.track_get_key_time(track_index, key_index) >= animation.length - 0.00001:
			key_index = 0
		var at := animation.track_get_key_time(track_index, key_index)
		var expected: Variant = animation.track_get_key_value(track_index, key_index)
		player.play(op)
		player.seek(at, true)
		player.advance(0.0)
		var actual: Variant
		var rest: Variant
		match animation.track_get_type(track_index):
			Animation.TYPE_ROTATION_3D:
				actual = skeleton.get_bone_pose_rotation(bone)
				rest = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			Animation.TYPE_POSITION_3D:
				actual = skeleton.get_bone_pose_position(bone)
				rest = skeleton.get_bone_rest(bone).origin
			Animation.TYPE_SCALE_3D:
				actual = skeleton.get_bone_pose_scale(bone)
				rest = skeleton.get_bone_rest(bone).basis.get_scale()
			_:
				failures.append("unsupported track type on %s" % str(path))
				continue
		var error := 0.0
		var travel := 0.0
		if actual is Quaternion:
			error = (actual as Quaternion).angle_to(expected)
			travel = (expected as Quaternion).angle_to(rest)
		else:
			error = (actual as Vector3).distance_to(expected)
			travel = (expected as Vector3).distance_to(rest)
		worst = maxf(worst, error)
		checked += 1
		if travel > 0.001:
			moving += 1
		if error > 0.02:
			failures.append("played bone differs from authored key: %s at %.3f" % [str(path), at])
	if checked == 0 or moving == 0:
		failures.append("clip has no verified moving bone")
	print("RIG_RECIPE_RUNTIME=" + JSON.stringify({"op": op, "scene": args[0],
		"checked": checked, "moving": moving, "worst_error": worst,
		"failures": failures}))
	quit(0 if failures.is_empty() else 1)
