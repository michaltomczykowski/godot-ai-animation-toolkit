extends SceneTree

## Diagnose a saved motion clip's played foot heights at selected times.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var fixture := (load(args[0]) as PackedScene).instantiate()
	root.add_child(fixture)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton := fixture.get_node("Dummy/Skeleton3D") as Skeleton3D
	var clip := player.get_animation(args[1])
	var foot_l := skeleton.find_bone("B-foot.L")
	var foot_r := skeleton.find_bone("B-foot.R")
	var hips := skeleton.find_bone("B-hips")
	var ground_l := skeleton.get_bone_global_rest(foot_l).origin.y
	var ground_r := skeleton.get_bone_global_rest(foot_r).origin.y
	var rows: Array = []
	for fraction in [0.0, 0.14, 0.2, 0.25, 0.3, 0.32, 0.35, 0.47, 0.55,
		0.62, 0.74, 0.8, 0.84, 0.88, 0.9, 0.95, 1.0]:
		var time := float(fraction) * clip.length
		player.play(args[1])
		player.seek(time, true)
		player.advance(0.0)
		rows.append({"f": fraction,
			"left": snappedf(skeleton.get_bone_global_pose(foot_l).origin.y - ground_l, 0.0001),
			"right": snappedf(skeleton.get_bone_global_pose(foot_r).origin.y - ground_r, 0.0001),
			"hips": snappedf(skeleton.get_bone_global_pose(hips).origin.y, 0.0001)})
	print("MOTION_TRACE=" + JSON.stringify({"op": args[1], "rows": rows}))
	quit()
