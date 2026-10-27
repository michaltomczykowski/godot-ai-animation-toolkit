@tool
extends McpTestSuite

const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const Builders := preload("res://addons/godot_ai_animation/spec/graph_builders.gd")
const FxSuite := preload("res://tests/test_fx_route_history.gd")
const GraphSuite := preload("res://tests/test_graph_route_history.gd")
const DUMMY := preload("res://models/human_dummy/HumanCharacterDummy_F.fbx")
var _undo: EditorUndoRedoManager
var _dispatcher
var _logger: GraphSuite.ErrorCapture
var _compare := FxSuite.new()

func suite_name() -> String: return "character_route_history"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = GraphSuite.ErrorCapture.new()
	OS.add_logger(_logger)
func suite_teardown() -> void: OS.remove_logger(_logger)
func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "character-history",
		"command": "custom_tool:animation_motion", "params": params})

func _fixture(seed: bool, missing: bool) -> Node3D:
	var fixture := Node3D.new()
	fixture.name = "CharacterHistory"
	var dummy := DUMMY.instantiate()
	dummy.name = "Dummy"
	fixture.add_child(dummy)
	dummy.owner = fixture
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	fixture.add_child(player)
	player.owner = fixture
	if not missing:
		var library := AnimationLibrary.new()
		for name in ["idle", "walk", "run", "untouched"]:
			var clip := Animation.new()
			clip.length = 0.75
			var track := clip.add_track(Animation.TYPE_POSITION_3D)
			clip.track_set_path(track, NodePath("Dummy:position"))
			clip.track_insert_key(track, 0.0, Vector3.ZERO)
			library.add_animation(name, clip)
		player.add_animation_library("", library)
	if seed:
		var tree := AnimationTree.new()
		tree.name = "AnimationTree"
		fixture.add_child(tree)
		tree.owner = fixture
		var graph := AnimationNodeAnimation.new()
		graph.animation = &"idle"
		tree.tree_root = graph
		tree.anim_player = NodePath("../AnimationPlayer")
		tree.root_motion_track = NodePath("Dummy:position")
		player.root_motion_track = tree.root_motion_track
		tree.root_motion_local = false
		player.root_motion_local = false
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		tree.active = true
	return fixture

func _snapshot(fixture: Node) -> Dictionary:
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var clips := {}
	for name in player.get_animation_list(): clips[str(name)] = _compare._canon(SpecIO.from_animation(player.get_animation(name)))
	var tree := fixture.get_node_or_null("AnimationTree") as AnimationTree
	var graph := {"exists": false}
	if tree != null:
		var parameters := {}
		for prop in tree.get_property_list():
			var path := str(prop.name)
			if path.begins_with("parameters/") and not tree.get(path) is Resource: parameters[path] = tree.get(path)
		graph = {"exists": true, "root": Builders.graph_dump(tree.tree_root), "player": str(tree.anim_player),
			"active": tree.active, "track": str(tree.root_motion_track), "local": tree.root_motion_local, "parameters": parameters}
	return {"clips": clips, "libraries": player.get_animation_library_list(), "track": str(player.root_motion_track),
		"local": player.root_motion_local, "graph": graph}

func _persist(edited: Node, fixture: Node, expected: Dictionary, label: String) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(edited), OK, label + " pack")
	var path := "user://character_history_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK, label + " save")
	var saved := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	assert_true(_compare._same(_snapshot(saved.get_node(str(fixture.name))), expected), label + " persisted state")
	saved.free()

func _case(mode: String, root_motion: bool = true) -> void:
	_logger.errors.clear()
	var edited := EditorInterface.get_edited_scene_root()
	var fixture := _fixture(mode in ["replace", "instanced", "instanced_editable"], mode == "missing_library")
	var peer: Node
	var source: PackedScene
	if mode.begins_with("instanced"):
		source = PackedScene.new()
		var path := "user://character_source_%s.tscn" % mode
		assert_eq(source.pack(fixture), OK)
		assert_eq(ResourceSaver.save(source, path), OK)
		fixture.free()
		source = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		fixture = source.instantiate()
		peer = source.instantiate()
		peer.name = "CharacterPeer"
		edited.add_child(peer)
		peer.owner = edited
	edited.add_child(fixture)
	fixture.owner = edited
	if mode == "instanced_editable": edited.set_editable_instance(fixture, true)
	if peer == null:
		for child in fixture.get_children(): child.owner = edited
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var old_library := player.get_animation_library("") if player.has_animation_library("") else null
	var old_tree := fixture.get_node_or_null("AnimationTree") as AnimationTree
	var old_root: AnimationRootNode = old_tree.tree_root if old_tree != null else null
	var baseline := _snapshot(fixture)
	var peer_before := _snapshot(peer) if peer != null else {}
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var params := {"op": "character_setup", "player_path": str(player.get_path()),
		"skeleton_path": str(fixture.get_node("Dummy/Skeleton3D").get_path()),
		"tree_path": str(fixture.get_path()) + "/AnimationTree", "include_jump": true,
		"include_turn": true, "active": true, "root_motion": root_motion}
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_has_key(_call(params.merged({"dry_run": true})), "data", mode + " dry")
	assert_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans, mode + " dry orphan count")
	assert_true(_compare._same(_snapshot(fixture), baseline), mode + " dry state")
	assert_eq(history.get_version(), version, mode + " dry history")
	assert_is_error(_call(params.merged({"tree_path": "/Missing/AnimationTree"}, true)), "NODE_NOT_FOUND")
	assert_true(_compare._same(_snapshot(fixture), baseline), mode + " rejected state")
	assert_eq(history.get_version(), version, mode + " rejected history")
	var result := _call(params)
	assert_has_key(result, "data", mode + " write " + str(result))
	var generated := _snapshot(fixture)
	assert_ne(generated, baseline, mode + " effect")
	assert_eq(history.get_version(), version + 1, mode + " one scene action")
	assert_eq(global_history.get_version(), global_version, mode + " global history")
	assert_eq(generated.track, ".:position" if root_motion else "", mode + " root extraction")
	assert_eq(generated.graph.track, generated.track, mode + " mixer ownership")
	for clip in ["idle", "walk", "run", "jump", "turn_left"]: assert_true(player.has_animation(clip), mode + " clip " + clip)
	assert_true(history.undo(), mode + " undo")
	assert_true(_compare._same(_snapshot(fixture), baseline), mode + " exact undo")
	if old_library != null: assert_true(player.get_animation_library("") == old_library, mode + " library identity")
	if old_tree != null: assert_true(old_tree.tree_root == old_root, mode + " root identity")
	if peer != null: assert_eq(edited.is_editable_instance(fixture), mode == "instanced_editable", mode + " permissions undo")
	var label := mode + ("_root" if root_motion else "_in_place")
	_persist(edited, fixture, baseline, label + "_undo")
	assert_true(history.redo(), mode + " redo")
	assert_true(_compare._same(_snapshot(fixture), generated), mode + " exact redo")
	_persist(edited, fixture, generated, label + "_redo")
	if peer != null:
		assert_true(_compare._same(_snapshot(peer), peer_before), mode + " peer isolated")
		var original := source.instantiate()
		assert_true(_compare._same(_snapshot(original), baseline), mode + " source isolated")
		original.free()
		peer.free()
	fixture.free()
	assert_eq(_logger.errors, [], mode + " engine errors")

func test_new_setup_history() -> void: _case("new")
func test_replaced_setup_history() -> void: _case("replace")
func test_missing_library_setup_history() -> void: _case("missing_library")
func test_instanced_setup_history() -> void: _case("instanced")
func test_instanced_new_setup_history() -> void: _case("instanced_new")
func test_editable_instance_keeps_source_library_isolated() -> void: _case("instanced_editable")
func test_root_motion_false_clears_existing_extraction() -> void: _case("replace", false)
