extends SceneTree

## Saved heterogeneous targets for live Godot AI FX route checks.

func _initialize() -> void:
	_create.call_deferred()


func _add(parent: Node, scene: Node, child: Node, name: String) -> void:
	child.name = name
	parent.add_child(child)
	child.owner = scene


func _create() -> void:
	var scene := Node2D.new()
	scene.name = "RepairFxFixture"
	root.add_child(scene)
	_add(scene, scene, AnimationPlayer.new(), "AnimationPlayer")
	_add(scene, scene, Camera2D.new(), "Camera2D")
	var flash := ColorRect.new()
	flash.color = Color(0.3, 0.2, 0.2)
	flash.size = Vector2(80, 40)
	_add(scene, scene, flash, "Flash")
	var damage := ProgressBar.new()
	damage.max_value = 100.0
	damage.value = 80.0
	_add(scene, scene, damage, "DamageBar")
	var fill := ProgressBar.new()
	fill.max_value = 100.0
	fill.value = 10.0
	_add(scene, scene, fill, "FillBar")
	var type_label := Label.new()
	type_label.text = "Procedural animation toolkit"
	_add(scene, scene, type_label, "TypeLabel")
	var score := Label.new()
	score.text = "0"
	_add(scene, scene, score, "ScoreLabel")
	_add(scene, scene, Panel.new(), "DialogPanel")
	var fade := ColorRect.new()
	fade.size = Vector2(640, 360)
	fade.color = Color(0, 0, 0)
	_add(scene, scene, fade, "FadeOverlay")
	for index in 3:
		var card := Node2D.new()
		card.position = Vector2(80.0 * index, 0)
		_add(scene, scene, card, "Card%d" % (index + 1))
	_add(scene, scene, Node2D.new(), "SpringTarget")
	_add(scene, scene, Node2D.new(), "PendulumTarget")
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2(0, 0))
	path.curve.add_point(Vector2(100, 0))
	path.curve.add_point(Vector2(100, 80))
	_add(scene, scene, path, "PatrolPath")
	_add(scene, scene, Node2D.new(), "Drone")
	var sprite := Sprite2D.new()
	sprite.texture = load("res://tests/fixtures/sheet.png")
	sprite.hframes = 4
	_add(scene, scene, sprite, "Sprite2D")
	_add(scene, scene, AnimatedSprite2D.new(), "SheetSprite")
	_add(scene, scene, AudioStreamPlayer2D.new(), "CuePlayer")
	var packed := PackedScene.new()
	var packed_error := packed.pack(scene)
	var saved := ResourceSaver.save(packed, "res://repair_fx_fixture.tscn")
	print("FX_FIXTURE=" + JSON.stringify({"pack": packed_error,
		"save": saved, "path": "res://repair_fx_fixture.tscn"}))
	quit(0 if packed_error == OK and saved == OK else 1)
