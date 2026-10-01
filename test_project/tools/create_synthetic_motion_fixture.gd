extends SceneTree

## Make a reproducible proportions/axis fixture from the bundled dummy.
## Args: output res:// path, uniform rest scale, rotate local up to +Z (true/false).

func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		print("SYNTHETIC_FIXTURE_ERROR=args")
		quit(1)
		return
	var packed := load("res://repair_rig_fixture.tscn") as PackedScene
	if packed == null:
		print("SYNTHETIC_FIXTURE_ERROR=source")
		quit(1)
		return
	var source := packed.instantiate() as Node3D
	root.add_child(source)
	source.name = "SyntheticTemplate"
	var source_skeleton := source.get_node("Dummy/Skeleton3D") as Skeleton3D
	# Make the skeleton scene-owned. Packing overrides on an imported FBX
	# instance silently drops modified bone rests on reopen.
	var fixture := Node3D.new()
	fixture.name = "RepairRigFixture"
	root.add_child(fixture)
	var dummy := Node3D.new()
	dummy.name = "Dummy"
	fixture.add_child(dummy)
	dummy.owner = fixture
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	dummy.add_child(skeleton)
	skeleton.owner = fixture
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	fixture.add_child(player)
	player.owner = fixture
	var scale_factor := float(args[1])
	var rotate_z := str(args[2]).to_lower() == "true"
	var rotation := Basis(Vector3.RIGHT, PI * 0.5) if rotate_z else Basis.IDENTITY
	for index in source_skeleton.get_bone_count():
		skeleton.add_bone(source_skeleton.get_bone_name(index))
	for index in source_skeleton.get_bone_count():
		var rest := source_skeleton.get_bone_rest(index)
		rest.origin *= scale_factor
		var parent := source_skeleton.get_bone_parent(index)
		if parent >= 0:
			skeleton.set_bone_parent(index, parent)
		else:
			rest = Transform3D(rotation * rest.basis, rotation * rest.origin)
		skeleton.set_bone_rest(index, rest)
		# Godot stores the live pose separately from rest. A hand-built skeleton
		# otherwise starts every child at its parent's origin despite valid rests.
		skeleton.set_bone_pose_position(index, rest.origin)
		skeleton.set_bone_pose_rotation(index, rest.basis.get_rotation_quaternion())
	var result := PackedScene.new()
	var error := result.pack(fixture)
	if error == OK:
		error = ResourceSaver.save(result, args[0])
	fixture.queue_free()
	source.queue_free()
	if error != OK:
		print("SYNTHETIC_FIXTURE_ERROR=save_%d" % error)
		quit(1)
		return
	var reopened := (load(args[0]) as PackedScene).instantiate() as Node3D
	root.add_child(reopened)
	var check := reopened.get_node("Dummy/Skeleton3D") as Skeleton3D
	var hip := check.get_bone_global_rest(check.find_bone("B-thigh.L")).origin
	var foot := check.get_bone_global_rest(check.find_bone("B-foot.L")).origin
	print("SYNTHETIC_FIXTURE=" + JSON.stringify({"path": args[0],
		"scale": scale_factor, "rotate_z": rotate_z,
		"hip_to_foot": hip.distance_to(foot), "hip": [hip.x, hip.y, hip.z],
		"foot": [foot.x, foot.y, foot.z],
		"pose_error": check.get_bone_global_pose(check.find_bone("B-foot.L")).origin.distance_to(foot)}))
	quit()
