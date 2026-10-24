extends SceneTree

## Static imported dummy for live pose persistence checks, with no autoplay.

func _initialize() -> void:
	_create.call_deferred()


func _create() -> void:
	var scene := Node3D.new()
	scene.name = "RepairRigFixture"
	root.add_child(scene)
	var dummy_source := load("res://models/human_dummy/HumanCharacterDummy_F.fbx") as PackedScene
	if dummy_source == null:
		print("RIG_FIXTURE_FAIL: missing dummy")
		quit(1)
		return
	var dummy := dummy_source.instantiate()
	dummy.name = "Dummy"
	scene.add_child(dummy)
	dummy.owner = scene
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	scene.add_child(player)
	player.owner = scene
	var packed := PackedScene.new()
	var packed_error := packed.pack(scene)
	var saved := ResourceSaver.save(packed, "res://repair_rig_fixture.tscn")
	print("RIG_FIXTURE=" + JSON.stringify({"pack": packed_error, "save": saved}))
	quit(0 if packed_error == OK and saved == OK else 1)
