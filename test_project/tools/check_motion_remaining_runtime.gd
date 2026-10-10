extends SceneTree

## Play a saved motion clip in Godot 4.7.2 and verify sampled authored bones.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("MOTION_REMAINING_FAIL: scene and clip required")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("MOTION_REMAINING_FAIL: scene did not load")
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton := fixture.get_node("Dummy/Skeleton3D") as Skeleton3D
	var clip := player.get_animation(args[1])
	if clip == null:
		print("MOTION_REMAINING_FAIL: saved clip missing")
		quit(1)
		return
	var failures: Array[String] = []
	var checked := 0
	var moving := 0
	var worst := 0.0
	var root_tracks := 0
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		if path.get_subname_count() != 1:
			failures.append("unresolved track path %s" % path)
			continue
		var bone := skeleton.find_bone(str(path.get_subname(0)))
		if bone < 0:
			if str(path) == "Dummy:position":
				root_tracks += 1
				continue
			failures.append("unknown bone track %s" % path)
			continue
		var key := mini(1, clip.track_get_key_count(track) - 1)
		var time := clip.track_get_key_time(track, key)
		var expected: Variant = clip.track_get_key_value(track, key)
		player.play(args[1])
		player.seek(time, true)
		player.advance(0.0)
		var actual: Variant
		match clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				actual = skeleton.get_bone_pose_rotation(bone)
			Animation.TYPE_POSITION_3D:
				actual = skeleton.get_bone_pose_position(bone)
			_:
				failures.append("unsupported bone track %s" % path)
				continue
		var error := 0.0
		if actual is Quaternion:
			error = (actual as Quaternion).angle_to(expected)
			if (expected as Quaternion).angle_to(Quaternion.IDENTITY) > 0.001:
				moving += 1
		else:
			error = (actual as Vector3).distance_to(expected)
			if (expected as Vector3).length() > 0.001:
				moving += 1
		worst = maxf(worst, error)
		checked += 1
		if error > 0.02:
			failures.append("played value differs at %s %.3f" % [path, time])
	if checked == 0 or moving == 0:
		failures.append("no sampled moving bone")
	print("MOTION_REMAINING_RUNTIME=" + JSON.stringify({"clip": args[1],
		"checked": checked, "moving": moving, "root_tracks": root_tracks,
		"worst_error": worst, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
