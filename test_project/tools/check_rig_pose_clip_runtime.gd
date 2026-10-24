extends SceneTree

## Saved pose_to_clip playback on the imported dummy skeleton.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("RIG_POSE_CLIP_FAIL: pass saved scene after --")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("RIG_POSE_CLIP_FAIL: scene did not load")
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton := fixture.get_node("Dummy/Skeleton3D") as Skeleton3D
	var bone := skeleton.find_bone("B-upperArm.L")
	var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	var results: Array = []
	var worst := 0.0
	for sample in [[0.0, 0.0], [0.5, 0.6], [1.0, 0.0]]:
		player.play("arm_wave")
		player.seek(sample[0], true)
		player.advance(0.0)
		var angle := (rest.inverse() * skeleton.get_bone_pose_rotation(bone)).get_angle()
		worst = maxf(worst, absf(angle - sample[1]))
		results.append({"time": sample[0], "expected": sample[1], "angle": angle})
	print("RIG_POSE_CLIP=" + JSON.stringify({"scene": args[0], "samples": results,
		"worst_error": worst}))
	quit(0 if worst < 0.02 else 1)
