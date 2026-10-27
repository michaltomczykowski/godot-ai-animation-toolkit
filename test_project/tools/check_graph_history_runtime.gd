extends SceneTree

## Play a saved redone history result. The tree owns playback; the player
## supplies clips and must remain stopped. Wire is a structural operation.
const HistorySuite := preload("res://tests/test_graph_route_history.gd")
var _logger := HistorySuite.ErrorCapture.new()

func _initialize() -> void:
	OS.add_logger(_logger)
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var failures: Array[String] = []
	if args.size() != 2:
		_finish(["expected scene and operation"])
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		_finish(["saved scene missing"])
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var fixture := scene.get_node_or_null("GraphHistory")
	if fixture == null:
		_finish(["saved fixture missing"])
		return
	var tree := fixture.get_node_or_null("AnimationTree") as AnimationTree
	var player := fixture.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var character := fixture.get_node_or_null("Character") as Node2D
	if tree == null or player == null or character == null:
		_finish(["saved tree, player or character missing"])
		return
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if tree.get_node_or_null(tree.anim_player) != player:
		failures.append("tree does not resolve its own player")
	var op := args[1]
	if op != "wire":
		tree.active = true
		match op:
			"state_machine":
				tree.get("parameters/playback").start("walk")
			"blend_space", "locomotion":
				tree.set("parameters/blend_position", 1.0)
			"blend_tree":
				tree.set("parameters/Blend2/blend_amount", 1.0)
			"one_shot_layer":
				tree.set("parameters/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			"additive_lean":
				tree.set("parameters/Add2/add_amount", 1.0)
		for _frame in 24:
			tree.advance(1.0 / 60.0)
		if op in ["state_machine", "blend_space", "locomotion", "blend_tree"] and character.position.x < 20.0:
			failures.append("tree did not play walk")
		if op == "one_shot_layer" and character.position.y > -20.0:
			failures.append("tree did not play jump")
		if op == "additive_lean" and character.rotation < 0.05:
			failures.append("tree did not play lean")
	if player.is_playing(): failures.append("player competes with tree")
	_finish(failures)

func _finish(failures: Array[String]) -> void:
	failures.append_array(_logger.errors)
	OS.remove_logger(_logger)
	print("GRAPH_HISTORY_RUNTIME=" + JSON.stringify({"failures": failures}))
	quit(0 if failures.is_empty() else 1)
