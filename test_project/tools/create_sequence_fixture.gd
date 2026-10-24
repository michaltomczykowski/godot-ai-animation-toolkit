extends SceneTree

## Build a small, saved 3D rig whose clips can be composed through Godot AI.

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "RepairSequenceFixture"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	skeleton.owner = root
	skeleton.add_bone("Root")
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.owner = root
	var library := AnimationLibrary.new()
	player.add_animation_library("", library)
	for source in ["approach", "kick"]:
		var clip := Animation.new()
		clip.length = 1.0
		var rotation := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(rotation, NodePath("Skeleton3D:Root"))
		clip.track_insert_key(rotation, 0.0, Quaternion.IDENTITY)
		clip.track_insert_key(rotation, 1.0,
			Quaternion(Vector3.RIGHT, 0.8 if source == "kick" else 0.2))
		library.add_animation(source, clip)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, "res://repair_sequence_fixture.tscn")
	print("SEQUENCE_FIXTURE_SAVE=", err)
	root.free()
	quit(0 if err == OK else 1)
