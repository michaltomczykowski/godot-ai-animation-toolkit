extends SceneTree

## Verify a saved RetargetModifier3D transfers a source pose when activated.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("RETARGET_RUNTIME_FAIL: scene required")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("RETARGET_RUNTIME_FAIL: saved scene not loadable")
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var source := fixture.get_node("Source") as Skeleton3D
	var modifier := fixture.get_node("Source/Retarget") as RetargetModifier3D
	var target := fixture.get_node("Source/Retarget/Target") as Skeleton3D
	var failures: Array[String] = []
	if modifier.active:
		failures.append("modifier unexpectedly active in saved scene")
	if modifier.get_parent() != source or target.get_parent() != modifier:
		failures.append("saved source/modifier/target ownership is wrong")
	if modifier.get_profile() == null or modifier.get_profile().get_bone_size() != 3:
		failures.append("saved profile has no three-bone map")
	var source_head := source.find_bone("B-head")
	var target_head := target.find_bone("B-head")
	var before := target.get_bone_pose_rotation(target_head)
	var wanted := Quaternion(Vector3.FORWARD, 0.6)
	source.set_bone_pose_rotation(source_head, wanted)
	var observed := {"max": 0.0, "count": 0, "latest": 0.0}
	modifier.modification_processed.connect(func() -> void:
		observed.count += 1
		var angle := before.angle_to(target.get_bone_pose_rotation(target_head))
		observed.max = maxf(float(observed.max), angle)
		observed.latest = angle)
	modifier.active = true
	for _i in 6:
		source.advance(0.1)
		await process_frame
	if float(observed.max) < 0.1:
		failures.append("active modifier did not transfer source head rotation")
	print("RETARGET_RUNTIME=" + JSON.stringify({"scene": args[0],
		"processed": observed.count, "target_head_change": observed.max,
		"failures": failures}))
	quit(0 if failures.is_empty() else 1)
