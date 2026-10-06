@tool
extends McpTestSuite

## Next checkpoint baseline: baking must not rewrite the source player's state.
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const PoseHistory := preload("res://tests/test_rig_pose_history.gd")
var _undo: EditorUndoRedoManager
var _dispatcher
var _logger: Capture.ErrorCapture
var _checks := PoseHistory.new()
var _read_position := true
func suite_name() -> String: return "rig_bake_state"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
func suite_teardown() -> void: OS.remove_logger(_logger)
func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "rig-bake-state", "command": "custom_tool:animation_rig", "params": params})
func _player_state(player: AnimationPlayer) -> Dictionary:
	var has_section := _read_position and not String(player.assigned_animation).is_empty() and player.has_section()
	return {"assigned": player.assigned_animation, "current": player.current_animation,
		"playing": player.is_playing(), "speed_scale": player.speed_scale,
		"playing_speed": player.get_playing_speed(), "queue": player.get_queue(),
		"section": has_section,
		"section_start": player.get_section_start_time() if has_section else 0.0,
		"section_end": player.get_section_end_time() if has_section else 0.0,
		"position": player.current_animation_position if _read_position and not String(player.assigned_animation).is_empty() else 0.0}
func _zero_speed(player: AnimationPlayer, state: String, label: String) -> void:
	if state != "zero_scale": return
	# At speed_scale=0, get_playing_speed hides the custom multiplier. Reveal it
	# briefly in the fixture to verify it survived, then restore the zero scale.
	player.speed_scale = 1.0
	assert_true(is_equal_approx(player.get_playing_speed(), 2.3), label + " hidden custom speed")
	player.speed_scale = 0.0
func _persist(label: String) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(EditorInterface.get_edited_scene_root()), OK, label + " pack")
	assert_eq(ResourceSaver.save(packed, "user://rig_bake_state_%s.tscn" % label), OK, label + " save")
func _case(state: String) -> void:
	# stop() retains assigned_animation but clears playback data; its position
	# getter is invalid. pause() retains playback data and its readable time.
	_read_position = state not in ["unassigned", "stopped"]
	var root := EditorInterface.get_edited_scene_root()
	var fixture := Node3D.new()
	fixture.name = "BakeState"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	fixture.add_child(skeleton)
	skeleton.add_bone("arm")
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(1, 2, 0)))
	skeleton.set_bone_pose_position(0, Vector3(1.2, 2.3, 0))
	skeleton.set_bone_pose_rotation(0, Quaternion(Vector3.RIGHT, 0.2))
	skeleton.set_bone_pose_scale(0, Vector3(1.2, 0.8, 1.1))
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	fixture.add_child(player)
	var library := AnimationLibrary.new()
	for label in ["input", "next"]:
		var animation := Animation.new()
		animation.length = 1.0
		var index := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(index, "Skeleton:arm")
		animation.track_insert_key(index, 0, Quaternion.IDENTITY)
		animation.track_insert_key(index, 1, Quaternion(Vector3.RIGHT, 0.6 if label == "input" else 0.9))
		library.add_animation(label, animation)
	player.add_animation_library("source", library)
	root.add_child(fixture)
	_checks._checks._own(fixture, root)
	player.speed_scale = 0.7 if state != "zero_scale" else 0.0
	if state != "unassigned":
		player.play("source/next" if state == "other_source" else "source/input", -1, -1.5 if state == "reverse" else 2.3, state == "reverse")
		if state == "section": player.set_section(0.1, 0.8)
		player.seek(0.3, true)
		if state == "paused": player.pause()
		elif state == "stopped": player.stop(true)
		else: player.queue("source/next")
	var before_player := _player_state(player)
	var before_pose := _checks._snapshot(skeleton)
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var version := history.get_version()
	var errors := _logger.errors.size()
	var params := {"op": "bake_pose_sequence", "skeleton_path": str(skeleton.get_path()),
		"player_path": str(player.get_path()), "source_animation": "source/input",
		"animation_name": "generated", "duration": 0.5, "fps": 4}
	var orphans := Node.get_orphan_node_ids()
	assert_has_key(_call(params.merged({"dry_run": true})), "data", state + " dry")
	assert_eq(Node.get_orphan_node_ids(), orphans, state + " dry no orphan nodes")
	assert_true(_checks._same(_player_state(player), before_player), state + " dry playback state " + str(_player_state(player)) + " expected " + str(before_player))
	_zero_speed(player, state, "dry")
	assert_true(_checks._same(_checks._snapshot(skeleton), before_pose), state + " dry pose")
	assert_eq(history.get_version(), version, state + " dry history")
	assert_has_key(_call(params), "data", state + " bake")
	assert_eq(Node.get_orphan_node_ids(), orphans, state + " bake no orphan nodes")
	assert_true(_checks._same(_player_state(player), before_player), state + " bake playback state")
	_zero_speed(player, state, "bake")
	assert_true(_checks._same(_checks._snapshot(skeleton), before_pose), state + " bake pose")
	assert_eq(history.get_version(), version + 1, state + " one action")
	assert_has_key(_call(params).get("error", {}), "code", state + " overwrite refusal")
	assert_eq(Node.get_orphan_node_ids(), orphans, state + " refusal no orphan nodes")
	assert_true(_checks._same(_player_state(player), before_player), state + " refused playback state")
	_zero_speed(player, state, "refused")
	assert_true(_checks._same(_checks._snapshot(skeleton), before_pose), state + " refused pose")
	assert_eq(history.get_version(), version + 1, state + " refused history")
	var baked := player.get_animation("generated")
	assert_true(is_equal_approx(baked.length, 0.5), state + " authored duration")
	var rotation_track := baked.find_track("Skeleton:arm", Animation.TYPE_ROTATION_3D)
	assert_true(rotation_track >= 0, state + " sampled rotation track")
	if rotation_track >= 0:
		assert_eq(baked.track_get_key_count(rotation_track), 3, state + " three samples")
		for index in 3:
			var actual: Quaternion = baked.track_get_key_value(rotation_track, index)
			assert_true(actual.angle_to(Quaternion(Vector3.RIGHT, index * 0.15)) < 0.001, state + " independent sampled value " + str(index))
	assert_true(history.undo(), state + " undo")
	assert_false(player.has_animation_library(""), state + " original missing default library")
	assert_true(player.get_animation_library("source") == library, state + " source library identity")
	assert_true(_checks._same(_player_state(player), before_player), state + " undo playback state")
	_zero_speed(player, state, "undo")
	assert_true(_checks._same(_checks._snapshot(skeleton), before_pose), state + " undo pose")
	_persist(state + "_undo")
	assert_true(history.redo(), state + " redo")
	assert_true(player.get_animation("generated") == baked, state + " redo clip identity")
	assert_true(_checks._same(_player_state(player), before_player), state + " redo playback state")
	_zero_speed(player, state, "redo")
	assert_true(_checks._same(_checks._snapshot(skeleton), before_pose), state + " redo pose")
	_persist(state + "_redo")
	assert_eq(_logger.errors.size(), errors, state + " zero engine errors")
	fixture.free()
func test_unassigned_source_state() -> void: _case("unassigned")
func test_paused_source_state() -> void: _case("paused")
func test_stopped_source_state() -> void: _case("stopped")
func test_playing_source_state() -> void: _case("playing")
func test_reverse_source_state() -> void: _case("reverse")
func test_zero_scale_source_state() -> void: _case("zero_scale")
func test_other_source_state() -> void: _case("other_source")
func test_section_source_state() -> void: _case("section")
