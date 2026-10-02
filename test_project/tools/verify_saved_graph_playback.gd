extends SceneTree

## Load an editor-saved graph scene in a fresh Godot process, then verify that
## the AnimationTree alone drives its saved walk clip.
##
## godot --headless --path test_project --script res://tools/verify_saved_graph_playback.gd -- res://repair_graph_audit/<run>/state_machine.tscn

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		_fail("expected one saved scene path")
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		_fail("could not load %s" % args[0])
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	var player := scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var tree := scene.get_node_or_null("AnimationTree") as AnimationTree
	var character := scene.get_node_or_null("Character") as Node2D
	if player == null or tree == null or character == null:
		_fail("saved player, tree or target is missing")
		return
	if tree.anim_player != NodePath("../AnimationPlayer"):
		_fail("saved tree does not target its scene-owned AnimationPlayer")
		return
	var saved_active := tree.active
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	if tree.tree_root is AnimationNodeStateMachine:
		if args[0].get_file() == "wire_parameter.tscn":
			if not saved_active or tree.get("parameters/conditions/walking") != true:
				_fail("wire did not persist active=true and the walking condition")
				return
			for _frame in 30:
				tree.advance(1.0 / 60.0)
			if character.position.x < 20.0 or player.is_playing():
				_fail("wired walking condition did not drive the tree (x=%.3f)" % character.position.x)
				return
			print("GRAPH_SAVED_PLAYBACK_PASS: %s condition_walk_x=%.3f player_idle=true" % [args[0], character.position.x])
			quit(0)
			return
		var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback == null:
			_fail("state machine has no playback controller")
			return
		playback.start("idle")
		tree.advance(0.1)
		if absf(character.position.x) > 0.01:
			_fail("idle unexpectedly moved the character to %.3f" % character.position.x)
			return
		playback.travel("walk")
	elif tree.tree_root is AnimationNodeBlendSpace1D:
		tree.set("parameters/blend_position", 1.0)
	elif tree.tree_root is AnimationNodeBlendTree:
		var blend_root := tree.tree_root as AnimationNodeBlendTree
		if blend_root.has_node("OneShot"):
			var base := tree.get("parameters/Base/playback") as AnimationNodeStateMachinePlayback
			if base == null:
				_fail("one-shot base has no state-machine playback")
				return
			base.start("idle")
			tree.advance(0.1)
			tree.set("parameters/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			for _frame in 30:
				tree.advance(1.0 / 60.0)
			if character.position.y > -20.0 or player.is_playing():
				_fail("one-shot jump did not play solely through the tree (y=%.3f)" % character.position.y)
				return
			print("GRAPH_SAVED_PLAYBACK_PASS: %s jump_y=%.3f player_idle=true" % [args[0], character.position.y])
			quit(0)
			return
		if blend_root.has_node("Add2"):
			var base := tree.get("parameters/Base/playback") as AnimationNodeStateMachinePlayback
			if base == null:
				_fail("additive base has no state-machine playback")
				return
			base.start("idle")
			tree.set("parameters/Add2/add_amount", 1.0)
			for _frame in 30:
				tree.advance(1.0 / 60.0)
			if character.rotation < 0.05 or player.is_playing():
				_fail("additive lean did not play solely through the tree (rotation=%.3f)" % character.rotation)
				return
			print("GRAPH_SAVED_PLAYBACK_PASS: %s lean=%.3f player_idle=true" % [args[0], character.rotation])
			quit(0)
			return
		if not blend_root.has_node("Blend2"):
			_fail("saved blend tree has no checked Blend2 node")
			return
		tree.advance(0.1)
		if absf(character.position.x) > 0.01:
			_fail("blend tree idle branch moved the character to %.3f" % character.position.x)
			return
		tree.set("parameters/Blend2/blend_amount", 1.0)
	else:
		_fail("saved graph root has no checked playback path")
		return
	for _frame in 30:
		tree.advance(1.0 / 60.0)
	var walk_x := character.position.x
	if walk_x < 20.0:
		_fail("saved walk did not play through the tree (x=%.3f)" % walk_x)
		return
	if tree.tree_root is AnimationNodeBlendSpace1D:
		tree.set("parameters/blend_position", 2.0)
		for _frame in 6:
			tree.advance(1.0 / 60.0)
		if character.position.x <= walk_x + 10.0:
			_fail("blend space did not switch to faster run (walk=%.3f, run=%.3f)"
				% [walk_x, character.position.x])
			return
	if player.is_playing():
		_fail("AnimationPlayer is competing with the tree")
		return
	print("GRAPH_SAVED_PLAYBACK_PASS: %s walk_x=%.3f player_idle=true" % [args[0], walk_x])
	quit(0)


func _fail(message: String) -> void:
	printerr("GRAPH_SAVED_PLAYBACK_FAIL: %s" % message)
	quit(1)
