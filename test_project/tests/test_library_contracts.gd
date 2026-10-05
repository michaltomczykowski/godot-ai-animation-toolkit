@tool
extends McpTestSuite

const History := preload("res://tests/test_preset_library_history.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const DIR := "res://animation_toolkit/history_contracts/"
var _checks := History.new()
var _undo: EditorUndoRedoManager
var _dispatcher
var _logger: Capture.ErrorCapture
var _files: Array[String] = []

func suite_name() -> String: return "library_contracts"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
	DirAccess.make_dir_recursive_absolute(DIR)
func suite_teardown() -> void:
	OS.remove_logger(_logger)
	for path in _files: DirAccess.remove_absolute(path)
func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "library-contracts", "command": "custom_tool:animation_library", "params": params})
func _file(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(data if data is String else JSON.stringify(data))
	file.close()
	if path not in _files: _files.append(path)
func _fixture() -> Node:
	var node := _checks._seed("local")
	node.name = "LibraryContracts"
	var audio := AudioStreamPlayer.new()
	audio.name = "Audio"
	node.add_child(audio)
	var root := EditorInterface.get_edited_scene_root()
	root.add_child(node)
	_checks._own(node, root)
	return node
func _typed_error(reply: Dictionary, label: String) -> void:
	assert_has_key(reply.get("error", {}), "code", label + " typed refusal " + str(reply))

func test_file_operations_preserve_history_and_dry_bytes() -> void:
	var fixture := _fixture()
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(fixture))
	var global := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global.get_version()
	var baseline := _checks._snapshot(fixture)
	var errors := _logger.errors.size()
	var path := DIR + "recipes.json"
	_files.append(path)
	DirAccess.remove_absolute(path)
	var save := {"op": "template_save", "name": "bounce", "tool": "animation_presets", "forward_op": "bounce", "library_path": path, "intensity": 0.25}
	assert_has_key(_call(save.merged({"dry_run": true})), "data", "new recipe dry")
	assert_false(FileAccess.file_exists(path), "dry does not create recipe")
	var made := _call(save)
	assert_eq(made.get("data", {}).get("undoable"), false, "file save non-undoable")
	var bytes := FileAccess.get_file_as_bytes(path)
	assert_true(bytes.size() > 0, "recipe written")
	var listed := _call({"op": "template_list", "library_path": path})
	assert_eq(listed.get("data", {}).get("template_count"), 1, "reopen recipe count")
	assert_eq(listed.get("data", {}).get("templates", [{}])[0].get("params", {}).get("intensity"), 0.25, "reopen recipe params")
	for dry in [false, true]:
		_typed_error(_call(save.merged({"dry_run": dry})), "duplicate recipe")
		assert_eq(FileAccess.get_file_as_bytes(path), bytes, "duplicate preserves bytes")
	var replacement := save.merged({"overwrite": true, "intensity": 0.4}, true)
	assert_has_key(_call(replacement.merged({"dry_run": true})), "data")
	assert_eq(FileAccess.get_file_as_bytes(path), bytes, "replacement dry preserves bytes")
	assert_has_key(_call(replacement), "data")
	assert_false(FileAccess.get_file_as_bytes(path) == bytes, "replacement writes bytes")
	bytes = FileAccess.get_file_as_bytes(path)
	var delete := {"op": "template_delete", "library_path": path, "name": "bounce"}
	assert_has_key(_call(delete.merged({"dry_run": true})), "data")
	assert_eq(FileAccess.get_file_as_bytes(path), bytes, "delete dry preserves bytes")
	assert_eq(_call(delete).get("data", {}).get("undoable"), false, "delete non-undoable")
	assert_eq(_call({"op": "template_list", "library_path": path}).get("data", {}).get("template_count"), 0)
	_typed_error(_call(delete), "delete missing")
	var spec_path := DIR + "export.json"
	_files.append(spec_path)
	DirAccess.remove_absolute(spec_path)
	var export := {"op": "spec_export", "player_path": str(player.get_path()), "animation_name": "unrelated", "path": spec_path, "overwrite": false}
	assert_has_key(_call(export.merged({"dry_run": true})), "data")
	assert_false(FileAccess.file_exists(spec_path), "dry does not create spec")
	assert_eq(_call(export).get("data", {}).get("undoable"), false, "export non-undoable")
	bytes = FileAccess.get_file_as_bytes(spec_path)
	for dry in [false, true]:
		_typed_error(_call(export.merged({"dry_run": dry})), "duplicate export")
		assert_eq(FileAccess.get_file_as_bytes(spec_path), bytes, "duplicate export bytes")
	assert_eq(_call({"op": "spec_import", "path": spec_path}).get("data", {}).get("track_count"), 1, "spec reopen")
	assert_true(_checks._same(_checks._snapshot(fixture), baseline), "file ops preserve scene")
	assert_eq(history.get_version(), version, "file ops zero scene history")
	assert_eq(global.get_version(), global_version, "file ops zero global history")
	assert_eq(_logger.errors.size(), errors, "file ops engine errors " + str(_logger.errors.slice(errors)))
	fixture.free()

func test_safe_paths_and_malformed_documents_are_typed() -> void:
	var fixture := _fixture()
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(fixture))
	var version := history.get_version()
	var baseline := _checks._snapshot(fixture)
	var errors := _logger.errors.size()
	for path in ["user://outside_library.json", "res://animation_toolkit/../../project.godot", "res://project.godot", "res://animation_toolkit/", "res://animation_toolkit/bad:name.json"]:
		for dry in [true, false]:
			_typed_error(_call({"op": "template_save", "name": "unsafe", "forward_op": "bounce", "library_path": path, "dry_run": dry}), "unsafe recipe " + path)
			_typed_error(_call({"op": "spec_export", "player_path": str(player.get_path()), "animation_name": "unrelated", "path": path, "dry_run": dry}), "unsafe export " + path)
	var path := DIR + "malformed.json"
	for doc in ["{bad-json", [], {"format": "other"}, {"format": "godot-ai-animation-library", "version": 99, "templates": {}}, {"templates": []}, {"templates": {"broken": []}}, {"templates": {"broken": {"tool": "animation_presets", "op": "bounce", "params": []}}}, {"templates": {"broken": {"tool": "animation_presets", "op": "missing", "params": {}}}}]:
		_file(path, doc)
		var bytes := FileAccess.get_file_as_bytes(path)
		for op in ["template_list", "template_apply", "template_delete"]:
			_typed_error(_call({"op": op, "name": "broken", "library_path": path, "player_path": str(player.get_path())}), "malformed recipe " + op + " " + str(doc))
		assert_eq(FileAccess.get_file_as_bytes(path), bytes, "malformed recipe bytes")
	for doc in [{"format": "godot-ai-animation-clip", "version": 1, "tracks": {}}, {"format": "godot-ai-animation-clip", "version": 1, "markers": [4], "tracks": []}, {"format": "godot-ai-animation-clip", "version": 1, "tracks": [{"type": 0, "path": "Widget:position", "keys": [4]}]}]:
		_file(path, doc)
		for op in ["spec_import", "spec_apply"]:
			_typed_error(_call({"op": op, "path": path, "player_path": str(player.get_path())}), "malformed spec " + str(doc))
	for change in [{"interp": 99}, {"update_mode": -1}, {"keys": [{"time": 0, "value": {"kind": "vector2", "x": "bad", "y": 0}}]}]:
		var doc := _checks._spec()
		doc.tracks[0].merge(change, true)
		_typed_error(_call({"op": "spec_import", "spec": doc}), "malformed metadata " + str(change))
	assert_true(_checks._same(_checks._snapshot(fixture), baseline), "rejections preserve scene")
	assert_eq(history.get_version(), version, "rejections preserve history")
	assert_eq(_logger.errors.size(), errors, "malformed engine errors " + str(_logger.errors.slice(errors)))
	fixture.free()

func _animation(kind: String) -> Animation:
	var anim := Animation.new()
	anim.length = 1.0
	var types: Array
	var paths: Array
	var first: Array
	var last: Array
	match kind:
		"2d":
			types = [Animation.TYPE_VALUE, Animation.TYPE_VALUE, Animation.TYPE_VALUE]
			paths = ["Widget:position", "Widget:visible", "Widget:tooltip_text"]
			first = [Vector2(10, 20), false, "first"]
			last = [Vector2(30, 40), true, "last"]
		"3d":
			types = [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]
			paths = ["Target3D", "Target3D", "Target3D"]
			first = [Vector3(2, 3, 4), Quaternion.IDENTITY, Vector3.ONE]
			last = [Vector3(4, 5, 6), Quaternion(Vector3.UP, PI / 2), Vector3(2, 2, 2)]
		"transform":
			types = [Animation.TYPE_VALUE]
			paths = ["Target3D:transform"]
			first = [Transform3D(Basis.IDENTITY, Vector3(2, 3, 4))]
			last = [Transform3D(Basis.IDENTITY.scaled(Vector3(2, 2, 2)), Vector3(2, 5, 4))]
		"cues":
			types = [Animation.TYPE_METHOD, Animation.TYPE_AUDIO]
			paths = ["Widget", "Audio"]
			first = [{"method": "set_meta", "args": ["cue", 42]}, {"stream": load("res://tests/fixtures/cue.wav"), "start_offset": 0.0, "end_offset": 0.0}]
			last = [{"method": "set_meta", "args": ["cue", 99]}, {"stream": load("res://tests/fixtures/cue.wav"), "start_offset": 0.0, "end_offset": 0.0}]
	for i in types.size():
		var index := anim.add_track(types[i])
		anim.track_set_path(index, NodePath(paths[i]))
		anim.track_set_interpolation_loop_wrap(index, false)
		if types[i] == Animation.TYPE_VALUE:
			anim.value_track_set_update_mode(index, Animation.UPDATE_CONTINUOUS if i == 0 else Animation.UPDATE_DISCRETE)
			anim.track_set_interpolation_type(index, Animation.INTERPOLATION_LINEAR if i == 0 else Animation.INTERPOLATION_NEAREST)
		if types[i] == Animation.TYPE_AUDIO: anim.audio_track_set_use_blend(index, true)
		anim.track_insert_key(index, 0.0, first[i], 1.0)
		anim.track_insert_key(index, 1.0, last[i], 0.75)
	anim.add_marker("impact", 0.4)
	anim.set_marker_color("impact", Color(1, 0, 0, 1))
	return anim

func test_invalid_destinations_and_unexportable_values_leave_no_effect() -> void:
	var fixture := _fixture()
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(fixture))
	var global := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global.get_version()
	var errors := _logger.errors.size()
	for change in [{"path": "Missing:position:x"}, {"path": "Widget:missing"}, {"path": "Widget:position:missing"}, {"type": Animation.TYPE_POSITION_3D, "path": "Widget"}, {"enabled": false}, {"keys": [{"time": 0.0, "value": "wrong"}]}]:
		var spec := _checks._spec()
		spec.tracks[0].merge(change, true)
		for dry in [true, false]:
			_typed_error(_call({"op": "spec_apply", "player_path": str(player.get_path()), "animation_name": "invalid", "spec": spec, "dry_run": dry}), "invalid destination " + str(change))
		assert_false(player.has_animation("invalid"), "invalid clip absent")
	var path := DIR + "protected_export.json"
	_file(path, {"sentinel": "unchanged"})
	var bytes := FileAccess.get_file_as_bytes(path)
	var bad := Animation.new()
	var index := bad.add_track(Animation.TYPE_VALUE)
	bad.track_set_path(index, NodePath("Widget:position"))
	bad.track_insert_key(index, 0.0, {"unrepresentable": Vector2.ONE})
	player.get_animation_library("").add_animation("bad_export", bad)
	for dry in [true, false]:
		_typed_error(_call({"op": "spec_export", "player_path": str(player.get_path()), "animation_name": "bad_export", "path": path, "dry_run": dry}), "unexportable value")
		assert_eq(FileAccess.get_file_as_bytes(path), bytes, "export refusal preserves destination")
	assert_eq(history.get_version(), version, "invalid calls zero scene actions")
	assert_eq(global.get_version(), global_version, "invalid calls zero global actions")
	assert_eq(_logger.errors.size(), errors, "invalid destination engine errors " + str(_logger.errors.slice(errors)))
	fixture.free()

func test_typed_export_apply_preserves_metadata_and_history() -> void:
	for kind in ["2d", "3d", "transform", "cues"]:
		var errors := _logger.errors.size()
		var fixture := _fixture()
		var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
		var library := player.get_animation_library("")
		var anim := _animation(kind)
		library.add_animation("typed", anim)
		var expected := _checks._history._clip(anim)
		var baseline := _checks._snapshot(fixture)
		var history := _undo.get_history_undo_redo(_undo.get_object_history_id(fixture))
		var version := history.get_version()
		var path: String = DIR + str(kind) + ".json"
		_files.append(path)
		assert_has_key(_call({"op": "spec_export", "player_path": str(player.get_path()), "animation_name": "typed", "path": path}), "data", kind + " export")
		var result := _call({"op": "spec_apply", "player_path": str(player.get_path()), "animation_name": "copy", "path": path})
		assert_has_key(result, "data", kind + " apply " + str(result))
		if player.has_animation("copy"):
			assert_true(_checks._same(_checks._history._clip(player.get_animation("copy")), expected), kind + " exact exported metadata")
		assert_eq(history.get_version(), version + 1, kind + " one apply action")
		var generated := _checks._snapshot(fixture)
		assert_true(history.undo())
		assert_true(_checks._same(_checks._snapshot(fixture), baseline), kind + " undo exact")
		assert_true(library.get_animation("typed") == anim, kind + " source identity")
		_checks._persist(fixture, baseline, "typed_" + kind + "_undo")
		assert_true(history.redo())
		_checks._persist(fixture, generated, "typed_" + kind + "_redo")
		assert_eq(_logger.errors.size(), errors, kind + " engine errors " + str(_logger.errors.slice(errors)))
		fixture.free()
