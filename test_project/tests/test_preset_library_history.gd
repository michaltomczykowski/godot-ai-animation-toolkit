@tool
extends McpTestSuite

## Public dispatcher coverage, independent engine snapshots and persisted history.
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const History := preload("res://tests/test_edit_route_history.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const HistoryTrace := preload("res://tests/operation_history_trace.gd")
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

func _persist(fixture: Node, expected: Dictionary, label: String, op: String = "") -> Dictionary:
	var packed := PackedScene.new()
	var pack_result := packed.pack(EditorInterface.get_edited_scene_root())
	assert_eq(pack_result, OK, label + " pack")
	var path := "user://preset_library_history_%s.tscn" % label
	var save_result := ResourceSaver.save(packed, path)
	assert_eq(save_result, OK, label + " save")
	var reopened := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved := reopened.get_node_or_null(str(EditorInterface.get_edited_scene_root().get_path_to(fixture)))
	assert_true(saved != null, label + " reopened node")
	var actual := _snapshot(saved) if saved != null else {}
	if saved != null: assert_true(_same(actual, expected), label + " persisted exact state " + str(_differences(actual, expected)))
	var found := saved != null
	var native := _native_intended(saved, op) if saved != null and label.ends_with("_redo") else []
	reopened.free()
	return {"path": path, "sha256": FileAccess.get_sha256(path), "pack_result": pack_result, "save_result": save_result, "fixture_found": found, "snapshot": actual, "native": native}

func _differences(a: Variant, b: Variant, path: String = "") -> Array:
	var out: Array = []
	if a is Dictionary and b is Dictionary:
		for key in b:
			if not a.has(key): out.append(path + "/" + str(key) + " missing")
			else: out.append_array(_differences(a[key], b[key], path + "/" + str(key)))
	elif not _same(a, b): out.append({"path": path, "actual": a, "expected": b})
	return out

func _case(op: String, mode: String) -> void:
	var assertions_before := _assertion_count
	var failed_before := _failed
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
	var original_ids := {}
	for name in originals: original_ids[str(name)] = originals[name].get_instance_id()
	var evidence := {"original_library_id":original_library.get_instance_id() if original_library != null else 0,"original_clip_ids":original_ids,"suite":"preset_library_history", "test":"test_" + mode + "_history", "mode":mode, "variant":op, "family":family, "op":str(params.op), "request":params.duplicate(true), "before":baseline, "scene":edited_root.scene_file_path, "failed_before":failed_before, "errors_before":errors, "recipe_path":LIBRARY, "recipe_sha256_before":FileAccess.get_sha256(LIBRARY), "versions":{"before":version,"global_before":global_version}, "peer_before":peer_before, "source_path":source_path, "source_sha256_before":FileAccess.get_sha256(source_path) if peer != null else ""}
	var dry := _call(family, params.merged({"dry_run": true}))
	evidence.dry = dry.duplicate(true)
	evidence.after_dry = _snapshot(fixture)
	evidence.versions.dry = history.get_version()
	evidence.versions.global_dry = global_history.get_version()
	assert_has_key(dry, "data", label + " dry " + str(dry))
	assert_eq(dry.get("data", {}).get("undoable"), false, label + " dry undo flag")
	assert_true(_same(_snapshot(fixture), baseline), label + " dry properties")
	assert_eq(history.get_version(), version, label + " dry history")
	var invalid := _call(family, params.merged({"player_path": "/Missing"}, true))
	evidence.invalid_request = params.merged({"player_path":"/Missing"},true)
	evidence.invalid = invalid.duplicate(true)
	evidence.after_error = _snapshot(fixture)
	evidence.versions.error = history.get_version()
	evidence.versions.global_error = global_history.get_version()
	assert_has_key(invalid.get("error", {}), "code", label + " typed error " + str(invalid))
	assert_true(_same(_snapshot(fixture), baseline), label + " rejected properties")
	assert_eq(history.get_version(), version, label + " rejected history")
	assert_eq(edited_root.is_editable_instance(fixture), mode == "editable", label + " dry/rejected permissions")
	var made := _call(family, params)
	evidence.write = made.duplicate(true)
	assert_has_key(made, "data", label + " write " + str(made))
	assert_eq(made.get("data", {}).get("undoable"), true, label + " write undo flag")
	var generated := _snapshot(fixture)
	evidence.generated = generated
	evidence.versions.write = history.get_version()
	evidence.versions.global_write = global_history.get_version()
	assert_false(_same(generated, baseline), label + " effect")
	assert_true(_same(generated.children.OtherPlayer, baseline.children.OtherPlayer), label + " other player")
	if originals.has("unrelated"): assert_true(_same(generated.children.AnimationPlayer.clips.unrelated, baseline.children.AnimationPlayer.clips.unrelated), label + " unrelated clip")
	assert_eq(history.get_version(), version + 1, label + " one scene action")
	assert_eq(global_history.get_version(), global_version, label + " zero global actions")
	var undo_success := history.undo()
	evidence.undo_success = undo_success
	evidence.undone = _snapshot(fixture)
	evidence.undo_library_id = player.get_animation_library("").get_instance_id() if player.has_animation_library("") else 0
	evidence.undo_clip_ids = {}
	for name in originals: evidence.undo_clip_ids[str(name)] = player.get_animation(name).get_instance_id() if player.has_animation(name) else 0
	assert_true(undo_success, label + " undo")
	assert_true(_same(_snapshot(fixture), baseline), label + " exact undo")
	assert_eq(player.has_animation_library(""), original_library != null, label + " library existence")
	if original_library != null:
		assert_true(player.get_animation_library("") == original_library, label + " library identity")
		for name in originals: assert_true(original_library.get_animation(name) == originals[name], label + " clip identity " + name)
	assert_eq(edited_root.is_editable_instance(fixture), mode == "editable", label + " restored permissions")
	evidence.persist_undo = _persist(fixture, baseline, label + "_undo",op)
	var redo_success := history.redo()
	evidence.redo_success = redo_success
	evidence.redone = _snapshot(fixture)
	assert_true(redo_success, label + " redo")
	assert_true(_same(_snapshot(fixture), generated), label + " exact redo")
	evidence.persist_redo = _persist(fixture, generated, label + "_redo",op)
	assert_eq(FileAccess.get_file_as_bytes(LIBRARY), library_bytes, label + " apply preserves recipe file")
	if peer != null:
		assert_true(_same(_snapshot(peer), peer_before), label + " peer isolated")
		var pristine := (ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var source_expected: Dictionary = baseline.duplicate(true)
		source_expected.owner = ""
		assert_true(_same(_snapshot(pristine), source_expected), label + " source isolated")
		evidence.pristine = _snapshot(pristine)
		pristine.free()
		assert_true(player.get_animation_library("") != peer.get_node("AnimationPlayer").get_animation_library(""), label + " library isolation")
		evidence.peer_after = _snapshot(peer)
		peer.free()
	evidence.source_sha256_after = FileAccess.get_sha256(source_path) if evidence.source_sha256_before != "" else ""
	evidence.recipe_sha256_after = FileAccess.get_sha256(LIBRARY)
	evidence.errors_after = _logger.errors.size()
	evidence.errors = _logger.errors.slice(errors)
	assert_eq(_logger.errors.size(), errors, label + " no engine errors: " + str(_logger.errors.slice(errors)))
	evidence.failed_after = _failed
	evidence.assertion_count = _assertion_count - assertions_before
	HistoryTrace.emit_preset_library(evidence,family)
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
		var assertions_before := _assertion_count
		var failed_before := _failed
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
		var evidence := {"suite":"preset_library_history","test":"test_showcase_subtree_history","mode":mode,"variant":"showcase","family":"animation_presets","op":"showcase","request":params.duplicate(true),"before":baseline,"scene":edited_root.scene_file_path,"failed_before":failed_before,"errors_before":errors,"recipe_path":LIBRARY,"recipe_sha256_before":FileAccess.get_sha256(LIBRARY),"versions":{"before":version,"global_before":global_version},"peer_before":_snapshot(peer) if peer != null else {},"source_path":"user://showcase_source_%s.tscn" % mode,"source_sha256_before":FileAccess.get_sha256("user://showcase_source_%s.tscn" % mode) if peer != null else ""}
		var dry := _call("animation_presets",params.merged({"dry_run":true}))
		evidence.dry=dry.duplicate(true)
		evidence.after_dry=_snapshot(parent)
		evidence.versions.dry=history.get_version()
		evidence.versions.global_dry=global_history.get_version()
		assert_has_key(dry,"data")
		assert_true(_same(_snapshot(parent), baseline), mode + " showcase dry unchanged")
		evidence.invalid_request=params.merged({"parent_path":"/Missing"},true)
		var invalid := _call("animation_presets",evidence.invalid_request)
		evidence.invalid=invalid.duplicate(true)
		evidence.after_error=_snapshot(parent)
		evidence.versions.error=history.get_version()
		evidence.versions.global_error=global_history.get_version()
		assert_has_key(invalid.get("error",{}),"code")
		assert_eq(history.get_version(), version, mode + " showcase dry/error history")
		var made := _call("animation_presets",params)
		evidence.write=made.duplicate(true)
		assert_has_key(made,"data")
		var generated := _snapshot(parent)
		evidence.generated=generated
		evidence.versions.write=history.get_version()
		evidence.versions.global_write=global_history.get_version()
		assert_eq(history.get_version(), version + 1, mode + " showcase one scene action")
		assert_eq(global_history.get_version(), global_version, mode + " showcase no global action")
		assert_has_key(_call("animation_presets", params).get("error", {}), "code", mode + " duplicate rejects")
		assert_eq(history.get_version(), version + 1, mode + " duplicate no history")
		evidence.undo_success=history.undo()
		evidence.undone=_snapshot(parent)
		assert_true(evidence.undo_success)
		assert_true(_same(_snapshot(parent), baseline), mode + " showcase undo exact")
		assert_eq(edited_root.is_editable_instance(fixture), mode == "editable", mode + " showcase permission undo")
		evidence.persist_undo=_persist(parent,baseline,"showcase_"+mode+"_undo","showcase")
		evidence.redo_success=history.redo()
		evidence.redone=_snapshot(parent)
		assert_true(evidence.redo_success)
		assert_true(_same(_snapshot(parent), generated), mode + " showcase redo owners/properties")
		evidence.persist_redo=_persist(parent,generated,"showcase_"+mode+"_redo","showcase")
		if peer != null:
			assert_false(peer.has_node("ReviewShowcase"), mode + " showcase peer untouched")
			evidence.peer_after=_snapshot(peer)
			peer.free()
		assert_eq(_logger.errors.size(), errors, mode + " showcase no engine errors " + str(_logger.errors.slice(errors)))
		parent.get_node("ReviewShowcase").free()
		evidence.source_sha256_after=FileAccess.get_sha256(evidence.source_path) if evidence.source_sha256_before != "" else ""
		evidence.recipe_sha256_after=FileAccess.get_sha256(LIBRARY)
		assert_eq(evidence.recipe_sha256_after,evidence.recipe_sha256_before,"Showcase preserves recipe file")
		evidence.errors_after=_logger.errors.size()
		evidence.errors=_logger.errors.slice(errors)
		evidence.failed_after=_failed
		evidence.assertion_count=_assertion_count-assertions_before
		HistoryTrace.emit_preset_library(evidence,"animation_presets")
		fixture.free()

func _native_intended(saved: Node, op: String) -> Array:
	var expectations: Array = []
	match op:
		"pulse": expectations = [[0.5,"Target3D","scale",Vector3(1.4,1.4,1.4)]]
		"bounce", "template_preset": expectations = [[0.35,"Widget","scale",Vector2(2.4,2.4)]]
		"orbit": expectations = [[0.25,"Target3D","position",Vector3(2,3,6)]]
		"sweep": expectations = [[0.25,"Widget","rotation",PI/2]]
		"drift": expectations = [[0.5,"Target3D","position",Vector3(4,3,4)]]
		"spin": expectations = [[0.25,"Target3D","quaternion",Quaternion(Vector3.UP,PI/2)]]
		"float": expectations = [[0.5,"Target3D","position",Vector3(2,4,4)],[0.5,"Target3D","scale",Vector3(1.25,1.25,1.25)]]
		"stagger": expectations = [[0.5,"Widget","modulate:a",0.75],[0.5,"OtherWidget","modulate:a",0.51]]
		"template_fx": expectations = [[0.5,"Widget","modulate",Color(1,0,0,1)]]
		"spec_apply": expectations = [[0.5,"Widget","position:x",20.0]]
		"showcase": expectations = [[0.14,"ReviewShowcase/BounceButton","scale",Vector2(1.15,1.15),"ReviewShowcase/AnimBounce","bounce"],[0.75,"ReviewShowcase/OrbitDot","position",Vector2(900,210),"ReviewShowcase/AnimOrbit","orbit"],[0.5,"ReviewShowcase/SweepPivot","rotation",PI/2,"ReviewShowcase/AnimSweep","sweep"],[1.0,"ReviewShowcase/DriftLine","position:x",860.0,"ReviewShowcase/AnimDrift","drift"],[0.6,"ReviewShowcase/PulseLabel","modulate:a",1.0,"ReviewShowcase/AnimPulse","pulse"],[1.2,"ReviewShowcase/World3D/FloatCube","position:y",0.35,"ReviewShowcase/AnimFloat","float"],[0.75,"ReviewShowcase/World3D/SpinCube","quaternion",Quaternion(Vector3.UP,PI/2),"ReviewShowcase/AnimSpin","spin"]]
	var results: Array = []
	for expected: Array in expectations:
		var host := Node.new()
		var clone := saved.duplicate()
		for mixer in clone.find_children("*","AnimationMixer",true,false): mixer.active = false
		EditorInterface.get_edited_scene_root().get_tree().root.add_child(host)
		host.add_child(clone)
		var player := clone.get_node(str(expected[4]) if expected.size()>4 else "AnimationPlayer") as AnimationPlayer
		var clip_name := str(expected[5]) if expected.size()>5 else "generated"
		var clip := player.get_animation(clip_name)
		var tracks: Array = []
		for index in clip.get_track_count():
			tracks.append({"path":str(clip.track_get_path(index)),"type":clip.track_get_type(index)})
			assert_eq(clip.track_get_type(index),Animation.TYPE_VALUE,op + " actual intended value-track type")
		player.active = true
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.play(clip_name)
		player.advance(float(expected[0]))
		var actual: Variant = clone.get_node(expected[1]).get_indexed(NodePath(expected[2]))
		assert_true(_same(actual,expected[3]),op + " independent native intended value " + str(actual))
		results.append({"time":expected[0],"node":expected[1],"property":expected[2],"actual":actual,"expected":expected[3],"tracks":tracks,"clock":"native_manual_mixer"})
		player.stop()
		host.free()
	return results
