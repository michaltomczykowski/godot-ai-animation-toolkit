extends SceneTree

## Load an editor-saved graph scene in a fresh Godot process, then verify that
## the AnimationTree alone drives the saved walk clip.
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
	if not (tree.tree_root is AnimationNodeStateMachine):
		_fail("saved graph root is not a state machine")
		return
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
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
	for _frame in 30:
		tree.advance(1.0 / 60.0)
	if character.position.x < 20.0:
		_fail("saved walk did not play through the tree (x=%.3f)" % character.position.x)
		return
	if player.is_playing():
		_fail("AnimationPlayer is competing with the tree")
		return
	print("GRAPH_SAVED_PLAYBACK_PASS: %s walk_x=%.3f player_idle=true" % [args[0], character.position.x])
	quit(0)


func _fail(message: String) -> void:
	printerr("GRAPH_SAVED_PLAYBACK_FAIL: %s" % message)
	quit(1)
