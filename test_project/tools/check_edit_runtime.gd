extends SceneTree

## Play a saved Godot AI edit and compare the engine-evaluated property.

const EXPECTED := {
	"retime": [0.0, 50.0, 100.0],
	"reverse": [100.0, 50.0, 0.0],
	"mirror": [0.0, -50.0, -100.0],
	"trim": [20.0, 50.0, 80.0],
	"amplitude": [0.0, 25.0, 50.0],
	"resample": [0.0, 50.0, 100.0],
	"layer": [0.0, 90.0, 180.0],
	"offset": [0.0, 40.0, 100.0],
	"loop": [0.0, 50.0, 100.0],
	"key_edit": [0.0, 15.0, 100.0],
	"overlap": [0.0, 45.0, 100.0],
}


func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not EXPECTED.has(args[1]):
		print("EDIT_RUNTIME_FAIL: pass scene path and known operation after --")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("EDIT_RUNTIME_FAIL: cannot load %s" % args[0])
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var character := fixture.get_node("Character") as Node2D
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var clip := player.get_animation("walk")
	var samples: Array = []
	player.play("walk")
	for at in [0.0, clip.length * 0.5, clip.length - 0.0001]:
		player.seek(at, true)
		player.advance(0.0)
		samples.append(character.position.x)
	var expected: Array = EXPECTED[args[1]]
	var worst := 0.0
	for index in 3:
		worst = maxf(worst, absf(float(samples[index]) - float(expected[index])))
	print("EDIT_RUNTIME=" + JSON.stringify({
		"op": args[1], "scene": args[0], "length": clip.length,
		"samples": samples, "expected": expected, "worst_error": worst,
	}))
	quit(0 if worst < 1.0 else 1)
