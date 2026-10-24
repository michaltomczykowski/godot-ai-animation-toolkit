extends SceneTree

const HistorySuite := preload("res://tests/test_graph_route_history.gd")
var _logger := HistorySuite.ErrorCapture.new()

func _initialize() -> void:
	OS.add_logger(_logger)
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		_finish(["expected scene, root-motion flag and FPS"])
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		_finish(["saved scene missing"])
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var fixture := scene.get_node_or_null("CharacterHistory") as Node3D
	if fixture == null:
		_finish(["fixture missing"])
		return
	var tree := fixture.get_node_or_null("AnimationTree") as AnimationTree
	var player := fixture.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skeleton := fixture.get_node_or_null("Dummy/Skeleton3D") as Skeleton3D
	if tree == null or player == null or skeleton == null:
		_finish(["tree, player or skeleton missing"])
		return
	var failures: Array[String] = []
	var rooted := args[1] == "true"
	var fps := int(args[2])
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if tree.get_node_or_null(tree.anim_player) != player: failures.append("player path unresolved")
	if str(tree.root_motion_track) != (".:position" if rooted else ""): failures.append("tree extraction path wrong")
	if player.root_motion_track != tree.root_motion_track: failures.append("player/tree extraction mismatch")
	for clip in ["idle", "walk", "run", "jump", "turn_left"]:
		if not player.has_animation(clip): failures.append("missing " + clip)
	var thigh := skeleton.find_bone("B-thigh.L")
	if thigh < 0:
		_finish(["thigh missing"])
		return
	var initial := skeleton.get_bone_pose_rotation(thigh)
	var position := fixture.position
	tree.active = true
	tree.set("parameters/Base/blend_position", 0.7)
	var travel := 0.0
	var bone_change := 0.0
	for _frame in int(0.6 * fps):
		tree.advance(1.0 / fps)
		travel += tree.get_root_motion_position().length()
		bone_change = maxf(bone_change, initial.angle_to(skeleton.get_bone_pose_rotation(thigh)))
	if bone_change < 0.001: failures.append("tree did not pose thigh")
	if rooted and travel < 0.01: failures.append("tree did not extract travel")
	if not rooted and travel > 0.001: failures.append("in-place tree extracts travel")
	if fixture.position.distance_to(position) > 0.001: failures.append("root translation has a competing owner")
	if player.is_playing(): failures.append("player competes with tree")
	_finish(failures)

func _finish(failures: Array[String]) -> void:
	failures.append_array(_logger.errors)
	OS.remove_logger(_logger)
	print("CHARACTER_HISTORY_RUNTIME=" + JSON.stringify({"failures": failures}))
	quit(0 if failures.is_empty() else 1)
