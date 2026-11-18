extends SceneTree

## Compare baked saved-scene playback with its source clip at sample times.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("RIG_BAKE_FAIL: pass saved scene after --")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("RIG_BAKE_FAIL: scene did not load")
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton := fixture.get_node("Dummy/Skeleton3D") as Skeleton3D
	var results: Array = []
	var worst := 0.0
	for bone_name in ["B-thigh.L", "B-thigh.R", "B-upperArm.L", "B-hips"]:
		var bone := skeleton.find_bone(bone_name)
		for at in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5]:
			player.play("walk_source")
			player.seek(at, true)
			player.advance(0.0)
			var source := skeleton.get_bone_pose_rotation(bone)
			player.play("walk_baked")
			player.seek(at, true)
			player.advance(0.0)
			var baked := skeleton.get_bone_pose_rotation(bone)
			var error := source.angle_to(baked)
			worst = maxf(worst, error)
			results.append({"bone": bone_name, "time": at, "angle_error": error})
	print("RIG_BAKE_RUNTIME=" + JSON.stringify({"scene": args[0],
		"samples": results.size(), "worst_error": worst}))
	quit(0 if worst < 0.02 else 1)
