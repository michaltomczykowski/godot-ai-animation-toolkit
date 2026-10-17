extends SceneTree

## Two scene-owned skeletons with matching names and different proportions.

func _initialize() -> void:
	_create.call_deferred()


func _skeleton(parent: Node3D, name: String, scale_factor: float) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = name
	parent.add_child(skeleton)
	skeleton.owner = parent
	var hips := skeleton.add_bone("B-hips")
	skeleton.set_bone_rest(hips, Transform3D(Basis.IDENTITY,
		Vector3(0, 0.9 * scale_factor, 0)))
	var spine := skeleton.add_bone("B-spine")
	skeleton.set_bone_parent(spine, hips)
	skeleton.set_bone_rest(spine, Transform3D(Basis.IDENTITY,
		Vector3(0, 0.2 * scale_factor, 0)))
	var head := skeleton.add_bone("B-head")
	skeleton.set_bone_parent(head, spine)
	skeleton.set_bone_rest(head, Transform3D(Basis.IDENTITY,
		Vector3(0, 0.3 * scale_factor, 0)))
	return skeleton


func _create() -> void:
	var scene := Node3D.new()
	scene.name = "RepairRetargetFixture"
	root.add_child(scene)
	_skeleton(scene, "Source", 1.0)
	_skeleton(scene, "Target", 1.3)
	var packed := PackedScene.new()
	var pack_error := packed.pack(scene)
	var saved := ResourceSaver.save(packed, "res://repair_retarget_fixture.tscn")
	print("RETARGET_FIXTURE=" + JSON.stringify({"pack": pack_error,
		"save": saved}))
	quit(0 if pack_error == OK and saved == OK else 1)
