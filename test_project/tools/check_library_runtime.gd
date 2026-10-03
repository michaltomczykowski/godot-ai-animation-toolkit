extends SceneTree

## Play scene clips created by template_apply and spec_apply through Godot AI.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("LIBRARY_RUNTIME_FAIL: pass saved scene path after --")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("LIBRARY_RUNTIME_FAIL: missing scene %s" % args[0])
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var player := scene.get_node("AnimationPlayer") as AnimationPlayer
	var target := scene.get_node("OtherCharacter") as Node2D
	var source := scene.get_node("Character") as Node2D
	var results: Array = []
	var worst := 0.0
	for item in [["templated_drift", 30.0], ["imported_walk", 50.0]]:
		target.position = Vector2.ZERO
		source.position = Vector2.ZERO
		player.play(item[0])
		player.seek(0.5, true)
		player.advance(0.0)
		worst = maxf(worst, absf(target.position.x - float(item[1])))
		worst = maxf(worst, absf(source.position.x))
		results.append({"clip": item[0], "target_x": target.position.x,
			"source_x": source.position.x, "expected_x": item[1]})
	print("LIBRARY_RUNTIME=" + JSON.stringify({"scene": args[0],
		"samples": results, "worst_error": worst}))
	quit(0 if worst < 0.1 else 1)
