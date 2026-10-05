@tool
extends McpTestSuite

## Every advertised edit through the public Godot AI dispatcher. Fixtures are
## seeded without history and each instance source has its own immutable file.
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Checks := preload("res://tests/test_fx_route_history.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const FIXTURE := preload("res://repair_edit_fixture.tscn")
const CASES := {
	"retime": {"factor": 0.5}, "reverse": {}, "mirror": {"axis": "x"},
	"trim": {"from": 0.2, "to": 0.8}, "amplitude": {"factor": 0.5},
	"resample": {"fps": 30, "interpolation": "linear"},
	"layer": {"source_animation": "run", "layer_mode": "add", "weight": 0.4},
	"offset": {"delta": 0.2, "wrap": false}, "loop": {"loop_mode": "pingpong"},
	"key_edit": {"action": "add", "track_path": "Character:position", "time": 0.5, "value": {"x": 15, "y": 0}},
	"overlap": {"track_path": "Character:position", "delay": 0.1, "wrap": false},
	"retarget": {"from_path": "Character", "to_path": "OtherCharacter"},
	"ease_range": {"from": 0.0, "to": 1.0, "transition": 2.0},
	"set_interp": {"interpolation": "nearest"},
	"split_at": {"time": 0.5, "head_name": "walk_head"},
	"merge": {"sources": [{"animation_name": "walk"}, {"animation_name": "run"}], "new_name": "walk_run"},
	"cleanup": {}, "smooth": {"strength": 0.5, "passes": 1},
	"reduce": {"value_tolerance": 0.01},
	"add_noise": {"amount": 2.0, "frequency": 2.0, "seed": 42},
}
var _undo: EditorUndoRedoManager
var _dispatcher
var _checks := Checks.new()
var _logger: Capture.ErrorCapture

func suite_name() -> String: return "edit_route_history"

func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)

func suite_teardown() -> void: OS.remove_logger(_logger)

func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "edit-history", "command": "custom_tool:animation_edit", "params": params})

func _clip(anim: Animation) -> Dictionary:
	# Read engine properties independently of SpecIO so metadata loss is visible.
	var tracks: Array = []
	for index in anim.get_track_count():
		var keys: Array = []
		for key in anim.track_get_key_count(index):
			keys.append([anim.track_get_key_time(index, key), anim.track_get_key_value(index, key), anim.track_get_key_transition(index, key)])
		var track := {"type": anim.track_get_type(index), "path": str(anim.track_get_path(index)), "enabled": anim.track_is_enabled(index),
			"interp": anim.track_get_interpolation_type(index), "wrap": anim.track_get_interpolation_loop_wrap(index), "keys": keys}
		if anim.track_get_type(index) == Animation.TYPE_VALUE: track.update = anim.value_track_get_update_mode(index)
		tracks.append(track)
	var markers := {}
	for name in anim.get_marker_names(): markers[str(name)] = [anim.get_marker_time(name), anim.get_marker_color(name)]
	return {"length": anim.length, "loop": anim.loop_mode, "tracks": tracks, "markers": markers}

func _clips(player: AnimationPlayer) -> Dictionary:
	var out := {}
	for name in player.get_animation_list(): out[str(name)] = _clip(player.get_animation(name))
	return out

func _snapshot(fixture: Node) -> Dictionary:
	return {"clips": _clips(fixture.get_node("AnimationPlayer")), "other": _clips(fixture.get_node("OtherPlayer"))}

func _own(node: Node, owner_node: Node) -> void:
	if node != owner_node: node.owner = owner_node
	for child in node.get_children(): _own(child, owner_node)

func _persist(edited_root: Node, expected: Dictionary, label: String) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(edited_root), OK, label + " packs")
	var path := "user://edit_history_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK, label + " saves")
	var loaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert_true(loaded != null, label + " loads")
	if loaded == null: return
	var reopened := loaded.instantiate()
	assert_true(_checks._same(_snapshot(reopened.get_node("EditHistory")), expected), label + " saved state matches")
	reopened.free()

func _seed(op: String, variant: String) -> Node:
	var fixture := FIXTURE.instantiate()
	fixture.scene_file_path = ""
	fixture.name = "EditHistory"
	_own(fixture, fixture)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var lib := player.get_animation_library("").duplicate(true) as AnimationLibrary
	player.remove_animation_library("")
	player.add_animation_library("", lib)
	# A real reduction must remove keys; preparing it must not add an undo action.
	if op in ["reduce", "add_noise"]:
		var walk := lib.get_animation("walk")
		for i in range(1, 30): walk.track_insert_key(0, float(i) / 30.0, Vector2(float(i) * 100.0 / 30.0, 0))
	var other := AnimationPlayer.new()
	other.name = "OtherPlayer"
	fixture.add_child(other)
	other.owner = fixture
	other.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	other.add_animation_library("", lib.duplicate(true))
	if variant == "overwrite":
		var prior := Animation.new()
		prior.length = 0.8
		var index := prior.add_track(Animation.TYPE_VALUE)
		prior.track_set_path(index, NodePath("Character:position"))
		prior.track_insert_key(index, 0.0, Vector2(777, 0))
		prior.track_insert_key(index, 0.8, Vector2(888, 0))
		lib.add_animation("walk_head" if op == "split_at" else "walk_run", prior)
	return fixture

func _case(op: String, mode: String, variant: String) -> void:
	var edited_root := EditorInterface.get_edited_scene_root()
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var label := "%s_%s_%s" % [mode, op, variant]
	var fixture := _seed(op, variant)
	var peer: Node
	var source: PackedScene
	var source_path := "user://edit_source_%s.tscn" % label
	if mode != "local":
		source = PackedScene.new()
		assert_eq(source.pack(fixture), OK, label + " source packs")
		assert_eq(ResourceSaver.save(source, source_path), OK, label + " source saves")
		fixture.free()
		source = ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		fixture = source.instantiate()
		peer = source.instantiate()
		peer.name = "EditPeer"
		edited_root.add_child(peer)
		peer.owner = edited_root
	else: fixture.scene_file_path = ""
	edited_root.add_child(fixture)
	fixture.owner = edited_root
	if mode == "local": _own(fixture, edited_root)
	if mode == "editable": edited_root.set_editable_instance(fixture, true)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var original_library := player.get_animation_library("")
	var originals := {}
	for name in original_library.get_animation_list(): originals[str(name)] = original_library.get_animation(name)
	var baseline := _snapshot(fixture)
	var peer_before := _snapshot(peer) if peer != null else {}
	var version := history.get_version()
	var global_version := global_history.get_version()
	var error_count := _logger.errors.size()
	var params: Dictionary = CASES[op].duplicate(true)
	params.merge({"op": op, "player_path": str(player.get_path()), "animation_name": "idle" if op == "cleanup" else ("jump" if op == "smooth" else "walk"), "overwrite": variant == "overwrite"})
	if variant == "cross":
		var cross := str(fixture.get_node("OtherPlayer").get_path())
		if op == "merge": params.sources[1].player_path = cross
		else: params.source_player_path = cross
	var dry := _call(params.merged({"dry_run": true}))
	assert_has_key(dry, "data", label + " dry route " + str(dry))
	assert_true(_checks._same(_snapshot(fixture), baseline), label + " dry unchanged")
	assert_eq(history.get_version(), version, label + " dry scene history")
	assert_true(player.get_animation_library("") == original_library, label + " dry library identity")
	var invalid := _call(params.merged({"player_path": "/Missing"}, true))
	assert_has_key(invalid, "error", label + " rejected route")
	assert_has_key(invalid.get("error", {}), "code", label + " typed rejection")
	assert_true(_checks._same(_snapshot(fixture), baseline), label + " rejected unchanged")
	assert_eq(history.get_version(), version, label + " rejected scene history")
	assert_eq(global_history.get_version(), global_version, label + " dry/rejected global history")
	assert_eq(edited_root.is_editable_instance(fixture), mode == "editable", label + " dry/rejected editability")
	var made := _call(params)
	assert_has_key(made, "data", label + " write route " + str(made))
	var generated := _snapshot(fixture)
	assert_false(_checks._same(generated, baseline), label + " effect")
	assert_true(_checks._same(generated.other, baseline.other), label + " cross-player inputs unchanged")
	var changed_names: Array = [str(params.animation_name)]
	if op == "merge": changed_names = ["walk_run"]
	if op == "split_at": changed_names.append("walk_head")
	for name in baseline.clips:
		if name not in changed_names: assert_true(_checks._same(generated.clips[name], baseline.clips[name]), label + " unrelated " + name)
	assert_eq(history.get_version(), version + 1, label + " one scene action")
	assert_eq(global_history.get_version(), global_version, label + " no global action")
	assert_true(history.undo(), label + " undo")
	assert_true(_checks._same(_snapshot(fixture), baseline), label + " exact undo")
	assert_true(player.get_animation_library("") == original_library, label + " library identity restored")
	for name in originals: assert_true(original_library.get_animation(name) == originals[name], label + " clip identity restored " + name)
	assert_eq(edited_root.is_editable_instance(fixture), mode == "editable", label + " undo editability")
	_persist(edited_root, baseline, label + "_undo")
	assert_true(history.redo(), label + " redo")
	assert_true(_checks._same(_snapshot(fixture), generated), label + " exact redo")
	_persist(edited_root, generated, label + "_redo")
	if peer != null:
		assert_true(_checks._same(_snapshot(peer), peer_before), label + " peer unchanged")
		var pristine := (ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		assert_true(_checks._same(_snapshot(pristine), baseline), label + " source file unchanged")
		pristine.free()
		assert_true(player.get_animation_library("") != peer.get_node("AnimationPlayer").get_animation_library(""), label + " scene library isolated")
		peer.free()
	assert_eq(_logger.errors.size(), error_count, label + " no engine errors: " + str(_logger.errors.slice(error_count)))
	fixture.free()

func _matrix(mode: String) -> void:
	for op in CASES: _case(op, mode, "base")
	for op in ["split_at", "merge"]: _case(op, mode, "overwrite")
	for op in ["merge", "layer"]: _case(op, mode, "cross")
	print("EDIT_HISTORY_MATRIX_COMPLETED=" + mode)

func test_registry_has_a_history_case_for_every_edit_operation() -> void:
	var names: Array = []
	for descriptor in Ops.op_descriptors("animation_edit"): names.append(str(descriptor.name))
	names.sort()
	var cases := CASES.keys()
	cases.sort()
	assert_eq(names, cases, "every advertised edit has a route/history case")

func test_local_scene_history() -> void: _matrix("local")
func test_instanced_scene_history() -> void: _matrix("instanced")
func test_editable_instance_scene_history() -> void: _matrix("editable")
