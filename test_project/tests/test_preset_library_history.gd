@tool
extends McpTestSuite

## Public dispatcher coverage, independent engine snapshots and persisted history.
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const History := preload("res://tests/test_edit_route_history.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const LIBRARY := "res://animation_toolkit/history_phase_library.json"
const CASES := {
	"pulse": {"target_path": "Target3D", "from_scale": 1.0, "to_scale": 1.4},
	"bounce": {"target_path": "Widget", "intensity": 0.2},
	"orbit": {"target_path": "Target3D", "radius": 2.0},
	"sweep": {"target_path": "Widget", "turns": 1.0},
	"drift": {"target_path": "Target3D", "axis": "x", "distance": 4.0},
	"spin": {"target_path": "Target3D", "turns": 1.0},
	"float": {"target_path": "Target3D", "height": 2.0, "scale": 1.5},
	"stagger": {"target_paths": ["Widget", "OtherWidget"], "effect": "fade_in", "stagger": 0.2},
	"template_preset": {"name": "bounce", "library_path": LIBRARY, "target_path": "Widget"},
	"template_fx": {"name": "flash", "library_path": LIBRARY, "target_path": "Widget"},
	"spec_apply": {},
}
var _undo: EditorUndoRedoManager
var _dispatcher
var _history := History.new()
var _logger: Capture.ErrorCapture
var _library_before := PackedByteArray()
var _library_existed := false

func suite_name() -> String: return "preset_library_history"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
	_library_existed = FileAccess.file_exists(LIBRARY)
	if _library_existed: _library_before = FileAccess.get_file_as_bytes(LIBRARY)
	DirAccess.make_dir_recursive_absolute(LIBRARY.get_base_dir())
	var file := FileAccess.open(LIBRARY, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": "godot-ai-animation-library", "version": 1, "templates": {
		"bounce": {"tool": "animation_presets", "op": "bounce", "params": {"intensity": 0.2}},
		"flash": {"tool": "animation_fx", "op": "hit_flash", "params": {"color": {"r": 1.0, "g": 0.0, "b": 0.0, "a": 1.0}}},
	}}))
	file.close()
func suite_teardown() -> void:
	OS.remove_logger(_logger)
	if _library_existed:
		var file := FileAccess.open(LIBRARY, FileAccess.WRITE)
		file.store_buffer(_library_before)
		file.close()
	else: DirAccess.remove_absolute(LIBRARY)

func _call(family: String, params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "preset-library-history", "command": "custom_tool:" + family, "params": params})

func _same(a: Variant, b: Variant) -> bool:
	if a is Vector2 and b is Vector2: return a.is_equal_approx(b)
	if a is Vector3 and b is Vector3: return a.is_equal_approx(b)
	if a is Quaternion and b is Quaternion: return a.is_equal_approx(b)
	if a is Transform3D and b is Transform3D: return a.is_equal_approx(b)
	if a is Color and b is Color: return a.is_equal_approx(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _same(a[i], b[i]): return false
		return true
	return _history._checks._same(a, b)

func _snapshot(node: Node) -> Dictionary:
	var values := {"class": node.get_class(), "owner": "" if node.owner == null else str(node.owner.name), "children": {}}
	for entry in node.get_property_list():
		if str(entry.name) in ["position", "scale", "rotation", "transform", "modulate", "pivot_offset", "size", "text", "visible", "current", "root_node", "autoplay", "callback_mode_process"]:
			values[str(entry.name)] = node.get(entry.name)
	# Label minimum size depends on theme/font availability while off-tree.
	# Compare its persisted font override and text, rather than that derived size.
	if node is Label:
		values.erase("size")
		values.font_override = node.get_theme_font_size("font_size") if node.has_theme_font_size_override("font_size") else 0
	if node is AnimationPlayer:
		values.clips = _history._clips(node)
		values.playing = node.is_playing()
	for child in node.get_children(): values.children[str(child.name)] = _snapshot(child)
	return values

func _own(node: Node, owner_node: Node) -> void:
	if node != owner_node: node.owner = owner_node
	for child in node.get_children(): _own(child, owner_node)

func _sentinel() -> Animation:
	var anim := Animation.new()
	anim.length = 1.0
	var index := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(index, NodePath("Widget:position:x"))
	anim.track_insert_key(index, 0.0, 10.0)
	anim.track_insert_key(index, 1.0, 30.0)
	return anim

func _seed(mode: String) -> Node:
	var fixture := Node.new()
	fixture.name = "PresetHistory"
	for label in ["Widget", "OtherWidget"]:
		var widget := Control.new()
		widget.name = label
		widget.position = Vector2(10, 20)
		widget.size = Vector2(120, 60)
		widget.pivot_offset = Vector2(7, 9)
		widget.scale = Vector2(2, 2)
		fixture.add_child(widget)
	var target := Node3D.new()
	target.name = "Target3D"
	target.position = Vector3(2, 3, 4)
	fixture.add_child(target)
	for label in ["AnimationPlayer", "OtherPlayer"]:
		var player := AnimationPlayer.new()
		player.name = label
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		fixture.add_child(player)
		if mode != "missing_library" or label == "OtherPlayer":
			var library := AnimationLibrary.new()
			library.add_animation("unrelated", _sentinel())
			if mode == "overwrite": library.add_animation("generated", _sentinel())
			player.add_animation_library("", library)
	_own(fixture, fixture)
	return fixture

func _spec() -> Dictionary:
	return {"format": "godot-ai-animation-clip", "version": 1, "length": 1.0, "loop_mode": 0, "markers": [{"name": "impact", "time": 0.4, "color": {"kind": "color", "r": 1, "g": 0, "b": 0, "a": 1}}], "tracks": [{
		"type": Animation.TYPE_VALUE, "path": "Widget:position:x", "enabled": true,
		"interp": Animation.INTERPOLATION_LINEAR, "loop_wrap": false, "update_mode": Animation.UPDATE_CONTINUOUS,
		"keys": [{"time": 0.0, "value": 10.0, "transition": 2.0}, {"time": 1.0, "value": 50.0, "transition": 0.75}],
	}]}

func _persist(fixture: Node, expected: Dictionary, label: String) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(EditorInterface.get_edited_scene_root()), OK, label + " pack")
	var path := "user://preset_library_history_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK, label + " save")
	var reopened := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved := reopened.get_node_or_null(str(EditorInterface.get_edited_scene_root().get_path_to(fixture)))
	assert_true(saved != null, label + " reopened node")
	if saved != null: assert_true(_same(_snapshot(saved), expected), label + " persisted exact state " + str(_differences(_snapshot(saved), expected)))
	reopened.free()

func _differences(a: Variant, b: Variant, path: String = "") -> Array:
	var out: Array = []
	if a is Dictionary and b is Dictionary:
		for key in b:
			if not a.has(key): out.append(path + "/" + str(key) + " missing")
			else: out.append_array(_differences(a[key], b[key], path + "/" + str(key)))
	elif not _same(a, b): out.append({"path": path, "actual": a, "expected": b})
	return out

func _case(op: String, mode: String) -> void:
	var edited_root := EditorInterface.get_edited_scene_root()
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var fixture := _seed(mode)
	var peer: Node
	var source_path := "user://preset_library_source_%s_%s.tscn" % [mode, op]
	if mode in ["instanced", "editable"]:
		var source := PackedScene.new()
		assert_eq(source.pack(fixture), OK)
		assert_eq(ResourceSaver.save(source, source_path), OK)
		fixture.free()
		source = ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		fixture = source.instantiate()
		peer = source.instantiate()
		peer.name = "PresetPeer"
		edited_root.add_child(peer)
		peer.owner = edited_root
	edited_root.add_child(fixture)
	fixture.owner = edited_root
	if mode not in ["instanced", "editable"]: _own(fixture, edited_root)
	if mode == "editable": edited_root.set_editable_instance(fixture, true)
	var label := mode + "_" + op
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var original_library := player.get_animation_library("") if player.has_animation_library("") else null
	var originals := {}
	if original_library != null:
		for name in original_library.get_animation_list(): originals[str(name)] = original_library.get_animation(name)
	var baseline := _snapshot(fixture)
	var peer_before := _snapshot(peer) if peer != null else {}
	var version := history.get_version()
	var global_version := global_history.get_version()
	var errors := _logger.errors.size()
	var library_bytes := FileAccess.get_file_as_bytes(LIBRARY)
	var family := "animation_library" if op.begins_with("template_") or op == "spec_apply" else "animation_presets"
	var params: Dictionary = CASES[op].duplicate(true)
	params.merge({"op": "template_apply" if op.begins_with("template_") else op, "player_path": str(player.get_path()), "animation_name": "generated", "overwrite": mode == "overwrite", "duration": 1.0})
	if op == "spec_apply": params.spec = _spec()
	var dry := _call(family, params.merged({"dry_run": true}))
	assert_has_key(dry, "data", label + " dry " + str(dry))
	assert_eq(dry.get("data", {}).get("undoable"), false, label + " dry undo flag")
	assert_true(_same(_snapshot(fixture), baseline), label + " dry properties")
	assert_eq(history.get_version(), version, label + " dry history")
	var invalid := _call(family, params.merged({"player_path": "/Missing"}, true))
	assert_has_key(invalid.get("error", {}), "code", label + " typed error " + str(invalid))
	assert_true(_same(_snapshot(fixture), baseline), label + " rejected properties")
	assert_eq(history.get_version(), version, label + " rejected history")
	assert_eq(edited_root.is_editable_instance(fixture), mode == "editable", label + " dry/rejected permissions")
	var made := _call(family, params)
	assert_has_key(made, "data", label + " write " + str(made))
	assert_eq(made.get("data", {}).get("undoable"), true, label + " write undo flag")
	var generated := _snapshot(fixture)
	assert_false(_same(generated, baseline), label + " effect")
	assert_true(_same(generated.children.OtherPlayer, baseline.children.OtherPlayer), label + " other player")
	if originals.has("unrelated"): assert_true(_same(generated.children.AnimationPlayer.clips.unrelated, baseline.children.AnimationPlayer.clips.unrelated), label + " unrelated clip")
	assert_eq(history.get_version(), version + 1, label + " one scene action")
	assert_eq(global_history.get_version(), global_version, label + " zero global actions")
	assert_true(history.undo(), label + " undo")
	assert_true(_same(_snapshot(fixture), baseline), label + " exact undo")
	assert_eq(player.has_animation_library(""), original_library != null, label + " library existence")
	if original_library != null:
		assert_true(player.get_animation_library("") == original_library, label + " library identity")
		for name in originals: assert_true(original_library.get_animation(name) == originals[name], label + " clip identity " + name)
	assert_eq(edited_root.is_editable_instance(fixture), mode == "editable", label + " restored permissions")
	_persist(fixture, baseline, label + "_undo")
	assert_true(history.redo(), label + " redo")
	assert_true(_same(_snapshot(fixture), generated), label + " exact redo")
	_persist(fixture, generated, label + "_redo")
	assert_eq(FileAccess.get_file_as_bytes(LIBRARY), library_bytes, label + " apply preserves recipe file")
	if peer != null:
		assert_true(_same(_snapshot(peer), peer_before), label + " peer isolated")
		var pristine := (ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var source_expected: Dictionary = baseline.duplicate(true)
		source_expected.owner = ""
		assert_true(_same(_snapshot(pristine), source_expected), label + " source isolated")
		pristine.free()
		assert_true(player.get_animation_library("") != peer.get_node("AnimationPlayer").get_animation_library(""), label + " library isolation")
		peer.free()
	assert_eq(_logger.errors.size(), errors, label + " no engine errors: " + str(_logger.errors.slice(errors)))
	fixture.free()

func _matrix(mode: String) -> void:
	for op in CASES: _case(op, mode)
	print("PRESET_LIBRARY_MATRIX_COMPLETED=" + mode)

func test_registry_operations_covered() -> void:
	var names: Array = []
	for op in Ops.op_descriptors("animation_presets"): names.append(str(op.name))
	names.sort()
	var expected := CASES.keys().filter(func(name): return not str(name).begins_with("template_") and name != "spec_apply")
	expected.append("showcase")
	expected.sort()
	assert_eq(names, expected, "every preset has history coverage")
func test_local_history() -> void: _matrix("local")
func test_overwrite_history() -> void: _matrix("overwrite")
func test_missing_library_history() -> void: _matrix("missing_library")
func test_instanced_history() -> void: _matrix("instanced")
func test_editable_history() -> void: _matrix("editable")

func test_showcase_subtree_history() -> void:
	for mode in ["root", "local", "instanced", "editable"]:
		var edited_root := EditorInterface.get_edited_scene_root()
		var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
		var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
		var fixture := _seed("local")
		var peer: Node
		if mode in ["instanced", "editable"]:
			var source := PackedScene.new()
			assert_eq(source.pack(fixture), OK)
			var path := "user://showcase_source_%s.tscn" % mode
			assert_eq(ResourceSaver.save(source, path), OK)
			fixture.free()
			source = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
			fixture = source.instantiate()
			peer = source.instantiate()
			peer.name = "ShowcasePeer"
			edited_root.add_child(peer)
			peer.owner = edited_root
		edited_root.add_child(fixture)
		fixture.owner = edited_root
		if mode not in ["instanced", "editable"]: _own(fixture, edited_root)
		if mode == "editable": edited_root.set_editable_instance(fixture, true)
		var parent := edited_root if mode == "root" else fixture
		var version := history.get_version()
		var global_version := global_history.get_version()
		var errors := _logger.errors.size()
		var baseline := _snapshot(parent)
		var params := {"op": "showcase", "parent_path": str(parent.get_path()), "name": "ReviewShowcase"}
		assert_has_key(_call("animation_presets", params.merged({"dry_run": true})), "data")
		assert_true(_same(_snapshot(parent), baseline), mode + " showcase dry unchanged")
		assert_has_key(_call("animation_presets", params.merged({"parent_path": "/Missing"}, true)).get("error", {}), "code")
		assert_eq(history.get_version(), version, mode + " showcase dry/error history")
		assert_has_key(_call("animation_presets", params), "data")
		var generated := _snapshot(parent)
		assert_eq(history.get_version(), version + 1, mode + " showcase one scene action")
		assert_eq(global_history.get_version(), global_version, mode + " showcase no global action")
		assert_has_key(_call("animation_presets", params).get("error", {}), "code", mode + " duplicate rejects")
		assert_eq(history.get_version(), version + 1, mode + " duplicate no history")
		assert_true(history.undo())
		assert_true(_same(_snapshot(parent), baseline), mode + " showcase undo exact")
		assert_eq(edited_root.is_editable_instance(fixture), mode == "editable", mode + " showcase permission undo")
		_persist(parent, baseline, "showcase_" + mode + "_undo")
		assert_true(history.redo())
		assert_true(_same(_snapshot(parent), generated), mode + " showcase redo owners/properties")
		_persist(parent, generated, "showcase_" + mode + "_redo")
		if peer != null:
			assert_false(peer.has_node("ReviewShowcase"), mode + " showcase peer untouched")
			peer.free()
		assert_eq(_logger.errors.size(), errors, mode + " showcase no engine errors " + str(_logger.errors.slice(errors)))
		parent.get_node("ReviewShowcase").free()
		fixture.free()
