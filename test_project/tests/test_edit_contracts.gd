@tool
extends McpTestSuite

const History := preload("res://tests/test_edit_route_history.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
var _undo: EditorUndoRedoManager
var _dispatcher
var _checks := History.new()

func suite_name() -> String: return "edit_contracts"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")

func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "edit-contracts", "command": "custom_tool:animation_edit", "params": params})

func _fixture() -> Node:
	var fixture := Node3D.new()
	fixture.name = "EditContracts"
	EditorInterface.get_edited_scene_root().add_child(fixture)
	fixture.owner = EditorInterface.get_edited_scene_root()
	var target := Node3D.new()
	target.name = "Target"
	fixture.add_child(target)
	target.owner = fixture.owner
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	fixture.add_child(player)
	player.owner = fixture.owner
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.add_animation_library("", AnimationLibrary.new())
	return fixture

func _animation() -> Animation:
	var anim := Animation.new()
	anim.length = 1.0
	anim.loop_mode = Animation.LOOP_LINEAR
	var types := [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_VALUE]
	var first := [Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE, false]
	var last := [Vector3(2, 0, 0), Quaternion(Vector3.UP, PI / 2), Vector3(2, 2, 2), true]
	for i in types.size():
		var index := anim.add_track(types[i])
		anim.track_set_path(index, NodePath("Target:visible" if types[i] == Animation.TYPE_VALUE else "Target"))
		anim.track_set_interpolation_loop_wrap(index, false)
		anim.track_set_interpolation_type(index, Animation.INTERPOLATION_NEAREST if types[i] == Animation.TYPE_VALUE else Animation.INTERPOLATION_LINEAR)
		if types[i] == Animation.TYPE_VALUE: anim.value_track_set_update_mode(index, Animation.UPDATE_DISCRETE)
		anim.track_insert_key(index, 0.0, first[i], 1.0)
		anim.track_insert_key(index, 1.0, last[i], 0.75)
	var disabled := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(disabled, NodePath("Target:position:y"))
	anim.track_set_enabled(disabled, false)
	anim.track_set_interpolation_loop_wrap(disabled, false)
	anim.track_insert_key(disabled, 0.0, 0.0, 2.0)
	anim.track_insert_key(disabled, 1.0, 42.0)
	anim.add_marker("impact", 0.25)
	anim.set_marker_color("impact", Color(0.8, 0.2, 0.1, 1))
	return anim

func _persist(label: String, expected: Dictionary) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(EditorInterface.get_edited_scene_root()), OK, "3D pack " + label)
	var path := "user://edit_contracts_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK, "3D save " + label)
	var saved := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var player := saved.get_node("EditContracts/AnimationPlayer") as AnimationPlayer
	assert_true(_checks._checks._same(_checks._clips(player), expected), "3D saved metadata " + label)
	saved.free()

func test_3d_and_value_metadata_survive_retime_history() -> void:
	var logger := Capture.ErrorCapture.new()
	OS.add_logger(logger)
	var fixture := _fixture()
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var library := player.get_animation_library("")
	var original := _animation()
	library.add_animation("pose", original)
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(fixture))
	var version := history.get_version()
	var baseline := _checks._clips(player)
	var expected: Dictionary = baseline.duplicate(true)
	expected.pose.length = 2.0
	expected.pose.markers.impact[0] = 0.5
	for track in expected.pose.tracks:
		for key in track.keys: key[0] *= 2.0
	var result := _call({"op": "retime", "player_path": str(player.get_path()), "animation_name": "pose", "factor": 2.0})
	assert_has_key(result, "data", "3D retime route " + str(result))
	assert_true(_checks._checks._same(_checks._clips(player), expected), "all metadata preserved except deliberately retimed times")
	assert_eq(history.get_version(), version + 1, "3D one scene action")
	assert_true(history.undo(), "3D undo")
	assert_true(player.get_animation("pose") == original, "3D original identity")
	_persist("undo", baseline)
	assert_true(history.redo(), "3D redo")
	_persist("redo", expected)
	assert_eq(logger.errors.size(), 0, "3D engine errors " + str(logger.errors))
	OS.remove_logger(logger)
	fixture.free()

func _rejected(compressed: bool) -> void:
	var logger := Capture.ErrorCapture.new()
	OS.add_logger(logger)
	var fixture := _fixture()
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var lib := player.get_animation_library("")
	lib.add_animation("pose", _animation())
	var refused := Animation.new()
	refused.length = 1.0
	if compressed:
		var index := refused.add_track(Animation.TYPE_POSITION_3D)
		refused.track_set_path(index, NodePath("Target"))
		refused.position_track_insert_key(index, 0, Vector3.ZERO)
		refused.position_track_insert_key(index, 1, Vector3.ONE)
		refused.compress()
		assert_true(refused.track_is_compressed(0), "fixture is actually compressed")
	else:
		var index := refused.add_track(Animation.TYPE_BEZIER)
		refused.track_set_path(index, NodePath("Target:position:x"))
		refused.bezier_track_insert_key(index, 0, 0)
		refused.bezier_track_insert_key(index, 1, 1)
	lib.add_animation("refused", refused)
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(fixture))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var baseline := _checks._clips(player)
	for op in ["retime", "merge", "layer"]:
		var params := {"op": op, "player_path": str(player.get_path()), "animation_name": "refused" if op == "retime" else "pose", "factor": 2.0,
			"source_animation": "refused", "sources": [{"animation_name": "pose"}, {"animation_name": "refused"}], "new_name": "output"}
		for dry in [false, true]:
			var result := _call(params.merged({"dry_run": dry}))
			assert_has_key(result, "error", op + " rejects unrepresentable source " + str(result))
			assert_eq(result.get("error", {}).get("code"), "INVALID_PARAMS" if compressed else "WRONG_TYPE", op + " typed error")
			assert_eq(history.get_version(), version, op + " no scene history")
			assert_eq(global_history.get_version(), global_version, op + " no global history")
			assert_true(player.get_animation_library("") == lib, op + " library unchanged")
			assert_true(player.get_animation("refused") == refused, op + " source identity unchanged")
			assert_true(_checks._checks._same(_checks._clips(player), baseline), op + " source/target contents unchanged")
	assert_eq(logger.errors.size(), 0, "rejected route engine errors " + str(logger.errors))
	OS.remove_logger(logger)
	fixture.free()

func test_compressed_sources_are_rejected_consistently() -> void: _rejected(true)
func test_unsupported_sources_are_rejected_consistently() -> void: _rejected(false)
