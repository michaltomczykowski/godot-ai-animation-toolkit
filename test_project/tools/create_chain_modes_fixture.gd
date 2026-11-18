extends SceneTree

## Independent nodes for rig_chain new-3D, new-2D and subtree routes.

func _initialize() -> void:
	_create.call_deferred()


func _add(scene: Node, parent: Node, child: Node, name: String) -> void:
	child.name = name
	parent.add_child(child)
	child.owner = scene


func _create() -> void:
	var scene := Node3D.new()
	scene.name = "RepairChainFixture"
	root.add_child(scene)
	var chain_root := Node3D.new()
	_add(scene, scene, chain_root, "ArmatureRoot")
	var shoulder := Node3D.new()
	shoulder.position = Vector3(0, 0.4, 0)
	_add(scene, chain_root, shoulder, "Shoulder")
	var elbow := Node3D.new()
	elbow.position = Vector3(0.3, 0, 0)
	_add(scene, shoulder, elbow, "Elbow")
	var packed := PackedScene.new()
	var packed_error := packed.pack(scene)
	var saved := ResourceSaver.save(packed, "res://repair_chain_modes_fixture.tscn")
	print("CHAIN_MODES_FIXTURE=" + JSON.stringify({"pack": packed_error,
		"save": saved}))
	quit(0 if packed_error == OK and saved == OK else 1)
