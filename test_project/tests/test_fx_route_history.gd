@tool
extends McpTestSuite

const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const FIXTURE := preload("res://repair_fx_fixture.tscn")
const CASES := {
	"shake": {"target_path": "Camera2D", "seed": 7},
	"zoom_punch": {"target_path": "Camera2D"},
	"hit_flash": {"target_path": "Flash"},
	"damage_bar": {"target_path": "DamageBar", "to": 30.0},
	"typewriter": {"target_path": "TypeLabel"},
	"progress_fill": {"target_path": "FillBar", "to": 100.0},
	"counter": {"target_path": "ScoreLabel", "to": 100.0},
	"dialog_pop": {"target_path": "DialogPanel"},
	"transition": {"target_path": "FadeOverlay", "mode": "wipe_left"},
	"wave": {"target_paths": ["Card1", "Card2", "Card3"]},
	"spring": {"target_path": "SpringTarget", "offset": {"x": 0, "y": -60}},
	"pendulum": {"target_path": "PendulumTarget"},
	"path_follow": {"target_path": "Drone"},
	"flipbook": {"target_path": "Sprite2D", "frames": 4, "fps": 4},
	"audio_cue": {"target_path": "CuePlayer", "stream": "res://tests/fixtures/cue.wav"},
	"sprite_frames": {"texture": "res://tests/fixtures/sheet.png", "hframes": 4, "vframes": 1, "play": false},
}
var _undo: EditorUndoRedoManager
var _dispatcher

func suite_name() -> String:
	return "fx_route_history"

func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")

func suite_teardown() -> void:
	pass

func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "fx-history",
		"command": "custom_tool:animation_fx", "params": params})

func _canon(value: Variant) -> Variant:
	if value is Resource:
		return {"resource": value.resource_path, "class": value.get_class()}
	if value is Dictionary:
		var out := {}
		for key in value:
			out[str(key)] = _canon(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_canon(item))
		return out
	return value

func _same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.00001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not _same(a[index], b[index]): return false
		return true
	return a == b

func _snapshot(fixture: Node) -> Dictionary:
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var clips := {}
	for name in player.get_animation_list():
		clips[str(name)] = _canon(SpecIO.from_animation(player.get_animation(name)))
	var props := {}
	for child in fixture.get_children():
		var values := {}
		for property in child.get_property_list():
			if str(property.name) in ["position", "scale", "rotation", "modulate", "pivot_offset", "text", "value", "frame", "visible_characters"]:
				values[str(property.name)] = child.get(property.name)
		props[str(child.name)] = values
	var sprite := fixture.get_node("SheetSprite") as AnimatedSprite2D
	var frames := {}
	if sprite.sprite_frames != null:
		for name in sprite.sprite_frames.get_animation_names():
			var textures: Array = []
			for index in sprite.sprite_frames.get_frame_count(name):
				var texture := sprite.sprite_frames.get_frame_texture(name, index)
				textures.append({"size": texture.get_size(), "duration": sprite.sprite_frames.get_frame_duration(name, index)})
			frames[str(name)] = {"fps": sprite.sprite_frames.get_animation_speed(name), "loop": sprite.sprite_frames.get_animation_loop(name), "frames": textures}
	return {"clips": clips, "props": props, "frames": frames,
		# With no resource, Godot can retain an unusable selection string.
		# Neither null case has a playable selected clip.
		"animation": str(sprite.animation) if sprite.sprite_frames != null else "", "playing": sprite.is_playing()}

func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children(): _own(child, owner_node)

func _persist(root_node: Node, fixture: Node, expected: Dictionary, label: String) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(root_node), OK, label + " packs")
	var path := "user://fx_history_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK, label + " saves")
	var reopened := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved := reopened.get_node_or_null(NodePath(str(fixture.name)))
	assert_true(saved != null, label + " fixture reopens")
	if saved != null:
		assert_true(_same(_snapshot(saved), expected), label + " saved state matches")
	reopened.free()

func _matrix(mode: String) -> void:
	var root_node := EditorInterface.get_edited_scene_root()
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root_node))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	for op in CASES:
		var fixture := FIXTURE.instantiate()
		fixture.name = "FxHistory"
		root_node.add_child(fixture)
		fixture.owner = root_node
		var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
		var original_library := AnimationLibrary.new()
		var sentinel := Animation.new()
		sentinel.length = 2.0
		original_library.add_animation("unrelated", sentinel)
		if mode == "overwrite": original_library.add_animation("generated", sentinel.duplicate())
		if mode != "missing_library": player.add_animation_library("", original_library)
		if op == "sprite_frames" and mode == "overwrite":
			var prior := SpriteFrames.new()
			prior.add_animation("prior")
			prior.add_frame("prior", load("res://tests/fixtures/sheet.png"))
			prior.set_animation_speed("prior", 7.0)
			var sprite := fixture.get_node("SheetSprite") as AnimatedSprite2D
			sprite.sprite_frames = prior
			sprite.animation = "prior"
		var peer: Node
		if mode == "instanced":
			var source := PackedScene.new()
			source.pack(fixture)
			ResourceSaver.save(source, "user://fx_history_source.tscn")
			root_node.remove_child(fixture)
			fixture.free()
			source = ResourceLoader.load("user://fx_history_source.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
			fixture = source.instantiate()
			peer = source.instantiate()
			root_node.add_child(fixture)
			root_node.add_child(peer)
			fixture.owner = root_node
			peer.owner = root_node
			player = fixture.get_node("AnimationPlayer")
			original_library = player.get_animation_library("")
		else:
			fixture.scene_file_path = ""
			_own(fixture, root_node)
		var baseline := _snapshot(fixture)
		var peer_before := _snapshot(peer) if peer != null else {}
		var version := history.get_version()
		var global_version := global_history.get_version()
		var params: Dictionary = CASES[op].duplicate(true)
		params.merge({"op": op, "player_path": str(player.get_path()), "animation_name": "generated", "overwrite": mode == "overwrite"})
		if op == "path_follow": params.path_node = str(fixture.get_node("PatrolPath").get_path())
		if op == "sprite_frames": params.sprite_path = str(fixture.get_node("SheetSprite").get_path())
		var dry := _call(params.merged({"dry_run": true}))
		assert_has_key(dry, "data", op + " dry route")
		assert_true(_same(_snapshot(fixture), baseline), op + " dry state unchanged")
		assert_eq(history.get_version(), version, op + " dry history unchanged")
		var invalid := _call(params.merged({"player_path": "/Missing", "sprite_path": "/Missing"}, true))
		assert_has_key(invalid, "error", op + " invalid route rejects")
		assert_eq(history.get_version(), version, op + " error history unchanged")
		assert_true(_same(_snapshot(fixture), baseline), op + " error state unchanged")
		var made := _call(params)
		assert_has_key(made, "data", op + " write route " + str(made))
		var generated := _snapshot(fixture)
		assert_false(_same(generated, baseline), op + " produces an effect")
		assert_eq(global_history.get_version(), global_version, op + " no global action")
		assert_eq(history.get_version(), version + 1, op + " one scene action")
		assert_true(history.undo(), op + " scene undo")
		if not _same(_snapshot(fixture), baseline):
			print("FX_HISTORY_DIFF=" + JSON.stringify({"op": op, "mode": mode, "before": baseline, "undo": _snapshot(fixture)}))
		assert_true(_same(_snapshot(fixture), baseline), op + " exact undo baseline")
		if mode == "missing_library": assert_false(player.has_animation_library(""), op + " undo removes new library")
		else: assert_true(player.get_animation_library("") == original_library, op + " undo restores library identity")
		if peer != null:
			assert_false(root_node.is_editable_instance(fixture), op + " undo restores instance editability")
			assert_true(_same(_snapshot(peer), peer_before), op + " peer unchanged")
		_persist(root_node, fixture, baseline, op + "_" + mode + "_undo")
		assert_true(history.redo(), op + " scene redo")
		assert_true(_same(_snapshot(fixture), generated), op + " exact redo result")
		_persist(root_node, fixture, generated, op + "_" + mode + "_redo")
		if peer != null:
			assert_true(_same(_snapshot(peer), peer_before), op + " redo peer unchanged")
			root_node.remove_child(peer)
			peer.free()
		root_node.remove_child(fixture)
		fixture.free()
	print("FX_HISTORY_MATRIX_COMPLETED=" + mode)

func test_registry_has_a_history_case_for_every_fx_operation() -> void:
	var names: Array = []
	for descriptor in Ops.op_descriptors("animation_fx"): names.append(str(descriptor.name))
	names.sort()
	var cases := CASES.keys()
	cases.sort()
	assert_eq(names, cases, "every advertised FX operation has a route/history case")

func test_new_clip_scene_history() -> void: _matrix("new")
func test_overwritten_clip_scene_history() -> void: _matrix("overwrite")
func test_missing_library_scene_history() -> void: _matrix("missing_library")
func test_instanced_player_scene_history() -> void: _matrix("instanced")
