extends SceneTree
const Evidence := preload("res://tools/edit_native_evidence.gd")
var logger := Evidence.Capture.new()

## Engine playback assertions for live Godot AI edit audit scenes that need
## more than the simple three-sample Character.x checker.

func _initialize() -> void:
	OS.add_logger(logger)
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("EDIT_REMAINING_FAIL: pass scene path and operation after --")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("EDIT_REMAINING_FAIL: cannot load %s" % args[0])
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var character := fixture.get_node("Character") as Node2D
	var other := fixture.get_node("OtherCharacter") as Node2D
	var op := args[1]
	var checks: Array = []
	match op:
		"retarget":
			checks = [["walk", 0.5, other, "x", 50.0], ["walk", 0.5, character, "x", 0.0]]
		"ease_range":
			checks = [["walk", 0.25, character, "x", 6.25], ["walk", 0.5, character, "x", 25.0]]
		"set_interp":
			checks = [["walk", 0.25, character, "x", 0.0], ["walk", 0.75, character, "x", 0.0]]
		"split_at":
			checks = [["walk_head", 0.0, character, "x", 0.0], ["walk_head", 0.25, character, "x", 25.0], ["walk", 0.0, character, "x", 50.0], ["walk", 0.25, character, "x", 75.0]]
		"merge":
			checks = [["walk_run", 0.5, character, "x", 50.0], ["walk_run", 1.5, character, "x", 100.0]]
		"cleanup":
			checks = [["idle", 0.0, character, "x", 0.0], ["idle", 0.5, character, "x", 0.0]]
		"smooth":
			checks = [["jump", 0.0, character, "y", -20.0], ["jump", 0.5, character, "y", -40.0]]
		"reduce":
			checks = [["walk", 0.25, character, "x", 25.0], ["walk", 0.75, character, "x", 75.0]]
		"add_noise":
			checks = [["walk", 0.0, character, "x", -0.9593609], ["walk", 0.0, character, "y", -0.5208515]]
		_:
			print("EDIT_REMAINING_FAIL: unknown op %s" % op)
			quit(1)
			return
	var results: Array = []
	var names: Array = []
	var worst := 0.0
	for check in checks:
		var clip_name: String = check[0]
		if not names.has(clip_name): names.append(clip_name)
		var at: float = check[1]
		var target: Node2D = check[2]
		var axis: String = check[3]
		var expected: float = check[4]
		player.play(clip_name)
		player.seek(at, true)
		player.advance(0.0)
		var measured := target.position.x if axis == "x" else target.position.y
		worst = maxf(worst, absf(measured - expected))
		results.append({"clip": clip_name, "time": at, "node": target.name,
			"axis": axis, "measured": measured, "expected": expected,"assigned_animation":str(player.assigned_animation),"player_position":player.current_animation_position})
	var raw := Evidence.describe(args[0],fixture,player,names)
	OS.remove_logger(logger)
	print("EDIT_REMAINING=" + JSON.stringify({"op": op, "scene": args[0],
		"samples": results, "worst_error": worst,"raw":raw,"engine_errors":logger.errors}))
	quit(0 if worst < 0.25 and logger.errors.is_empty() else 1)
