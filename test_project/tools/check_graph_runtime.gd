extends SceneTree

## Play a saved Godot AI graph fixture in the actual game loop. Run with
## `--fixed-fps 60 --script res://tools/check_graph_runtime.gd -- res://...`.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("GRAPH_RUNTIME_FAIL: pass a scene path after --")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("GRAPH_RUNTIME_FAIL: cannot load %s" % args[0])
		quit(1)
		return
	var mode := str(args[1]) if args.size() > 1 else "blend"
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var character := fixture.get_node("Character") as Node2D
	var tree := fixture.get_node("AnimationTree") as AnimationTree
	if mode == "one_shot" or mode == "nested_one_shot":
		tree.set("parameters/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	var playback: AnimationNodeStateMachinePlayback = null
	if mode.begins_with("state_machine") or mode == "condition":
		playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback == null:
			print("GRAPH_RUNTIME_FAIL: state machine has no playback object")
			quit(1)
			return
		if mode == "state_machine":
			playback.start("walk")
	for _frame in 2:
		await process_frame
	var start := character.position.x
	var start_y := character.position.y
	var start_rotation := character.rotation
	for _frame in 30:
		await process_frame
	var end := character.position.x
	var end_y := character.position.y
	var end_rotation := character.rotation
	var result := {
		"scene": args[0],
		"mode": mode,
		"active": tree.active,
		"anim_player_resolved": tree.get_node_or_null(tree.anim_player) is AnimationPlayer,
		"blend_position": tree.get("parameters/blend_position") if mode == "blend" else null,
		"current_state": playback.get_current_node() if playback != null else "",
		"walking": tree.get("parameters/conditions/walking") if mode == "condition" else null,
		"start_x": start,
		"end_x": end,
		"delta_x": end - start,
		"start_y": start_y,
		"end_y": end_y,
		"delta_y": end_y - start_y,
		"start_rotation": start_rotation,
		"end_rotation": end_rotation,
		"delta_rotation": end_rotation - start_rotation,
	}
	print("GRAPH_RUNTIME=" + JSON.stringify(result))
	if mode == "state_machine_auto":
		quit(0 if tree.active else 1)
	elif mode == "one_shot" or mode == "nested_one_shot":
		quit(0 if tree.active and absf(end_y - start_y) > 10.0 else 1)
	elif mode == "additive":
		quit(0 if tree.active and absf(end_rotation - start_rotation) > 0.05 else 1)
	else:
		quit(0 if tree.active and absf(end - start) > 10.0 else 1)
