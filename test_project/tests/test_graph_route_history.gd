@tool
extends McpTestSuite

const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const Builders := preload("res://addons/godot_ai_animation/spec/graph_builders.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const FIXTURE := preload("res://repair_graph_fixture.tscn")
const CASES := {
	"state_machine": {"states": [{"name": "idle", "animation": "idle"}, {"name": "walk", "animation": "walk"}], "transitions": [{"from": "idle", "to": "walk", "xfade": 0.1}]},
	"blend_space": {"dimensions": 1, "min": 0, "max": 2, "points": [{"animation": "idle", "position": 0}, {"animation": "walk", "position": 1}, {"animation": "run", "position": 2}]},
	"blend_tree": {"root": {"type": "blend2", "inputs": [{"type": "animation", "animation": "idle"}, {"type": "animation", "animation": "walk"}]}},
	"wire": {},
	"locomotion": {"mode": "blend_space"},
	"one_shot_layer": {"animation": "jump", "base": "idle"},
	"additive_lean": {"animation": "lean", "base": "idle"},
}

class ErrorCapture extends Logger:
	var errors: Array[String] = []
	func _log_error(_function: String, _file: String, _line: int, code: String,
			rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1:
			errors.append(rationale if not rationale.is_empty() else code)

var _undo: EditorUndoRedoManager
var _dispatcher
var _logger: ErrorCapture

func suite_name() -> String: return "graph_route_history"

func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = ErrorCapture.new()
	OS.add_logger(_logger)

func suite_teardown() -> void:
	OS.remove_logger(_logger)

func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "graph-history",
		"command": "custom_tool:animation_graph", "params": params})

func _snapshot(fixture: Node) -> Dictionary:
	var tree := fixture.get_node_or_null("AnimationTree") as AnimationTree
	if tree == null: return {"tree": false}
	var parameters := {}
	for property in tree.get_property_list():
		var path := str(property.name)
		if path.begins_with("parameters/") and not tree.get(path) is Resource:
			parameters[path] = tree.get(path)
	return {"tree": true, "root": Builders.graph_dump(tree.tree_root),
		"player": str(tree.anim_player), "active": tree.active, "parameters": parameters}

func _seed(fixture: Node) -> void:
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	fixture.add_child(tree)
	tree.owner = fixture
	var root := AnimationNodeAnimation.new()
	root.animation = &"idle"
	tree.tree_root = root
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true

func _own(node: Node, edited_root: Node) -> void:
	node.owner = edited_root
	for child in node.get_children(): _own(child, edited_root)

func _persist(edited_root: Node, fixture: Node, expected: Dictionary, label: String) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(edited_root), OK, label + " packs")
	var path := "user://graph_history_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK, label + " saves")
	var saved := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	assert_eq(_snapshot(saved.get_node(str(fixture.name))), expected, label + " saved state matches")
	saved.free()

func _matrix(mode: String) -> void:
	var edited_root := EditorInterface.get_edited_scene_root()
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	for op in CASES:
		_logger.errors.clear()
		var fixture := FIXTURE.instantiate()
		fixture.name = "GraphHistory"
		if mode in ["replace", "instanced"]: _seed(fixture)
		var peer: Node
		if mode.begins_with("instanced"):
			var packed := PackedScene.new()
			var source_path := "user://graph_history_source_%s_%s.tscn" % [op, mode]
			assert_eq(packed.pack(fixture), OK)
			assert_eq(ResourceSaver.save(packed, source_path), OK)
			fixture.free()
			packed = ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
			fixture = packed.instantiate()
			peer = packed.instantiate()
			peer.name = "GraphPeer"
			edited_root.add_child(peer)
			peer.owner = edited_root
		else:
			fixture.scene_file_path = ""
		edited_root.add_child(fixture)
		fixture.owner = edited_root
		if not mode.begins_with("instanced"): _own(fixture, edited_root)
		var baseline := _snapshot(fixture)
		var peer_before := _snapshot(peer) if peer != null else {}
		var old_tree := fixture.get_node_or_null("AnimationTree") as AnimationTree
		var old_root: AnimationRootNode = old_tree.tree_root if old_tree != null else null
		var version := history.get_version()
		var global_version := global_history.get_version()
		var params: Dictionary = CASES[op].duplicate(true)
		params.merge({"op": op, "player_path": str(fixture.get_node("AnimationPlayer").get_path()),
			"tree_path": str(fixture.get_path()) + "/AnimationTree", "active": op != "wire"})
		var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		assert_has_key(_call(params.merged({"dry_run": true})), "data", op + " dry route")
		assert_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans, op + " dry run leaves no orphan tree")
		assert_eq(_snapshot(fixture), baseline, op + " dry state")
		assert_eq(history.get_version(), version, op + " dry history")
		assert_is_error(_call(params.merged({"player_path": "/Missing"}, true)), "NODE_NOT_FOUND", op + " invalid route")
		assert_eq(_snapshot(fixture), baseline, op + " invalid state")
		assert_eq(history.get_version(), version, op + " invalid history")
		var result := _call(params)
		assert_has_key(result, "data", op + " write " + str(result))
		var generated := _snapshot(fixture)
		assert_ne(generated, baseline, op + " effect")
		assert_eq(history.get_version(), version + 1, op + " one scene action")
		assert_eq(global_history.get_version(), global_version, op + " no global action")
		assert_true(history.undo(), op + " undo")
		assert_eq(_snapshot(fixture), baseline, op + " exact undo")
		if old_tree != null: assert_true(old_tree.tree_root == old_root, op + " original root identity")
		if peer != null: assert_false(edited_root.is_editable_instance(fixture), op + " undo instance editability")
		_persist(edited_root, fixture, baseline, op + "_" + mode + "_undo")
		assert_true(history.redo(), op + " redo")
		assert_eq(_snapshot(fixture), generated, op + " exact redo")
		_persist(edited_root, fixture, generated, op + "_" + mode + "_redo")
		if peer != null:
			assert_eq(_snapshot(peer), peer_before, op + " peer unchanged")
			peer.free()
		fixture.free()
		assert_eq(_logger.errors, [], op + " " + mode + " emits no engine errors")

func test_registry_has_a_graph_history_case_for_every_operation() -> void:
	var names: Array = []
	for descriptor in Ops.op_descriptors("animation_graph"): names.append(str(descriptor.name))
	names.sort()
	var cases := CASES.keys()
	cases.append("graph_get")
	cases.sort()
	assert_eq(names, cases)

func test_new_graph_scene_history() -> void: _matrix("new")
func test_replaced_graph_scene_history() -> void: _matrix("replace")
func test_instanced_graph_scene_history() -> void: _matrix("instanced")
func test_instanced_new_graph_scene_history() -> void: _matrix("instanced_new")

func test_graph_get_is_read_only() -> void:
	var edited_root := EditorInterface.get_edited_scene_root()
	var fixture := FIXTURE.instantiate()
	fixture.name = "GraphReadOnly"
	_seed(fixture)
	edited_root.add_child(fixture)
	fixture.owner = edited_root
	var before := _snapshot(fixture)
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var version := history.get_version()
	assert_has_key(_call({"op": "graph_get", "tree_path": str(fixture.get_node("AnimationTree").get_path())}), "data")
	assert_is_error(_call({"op": "graph_get", "tree_path": "/Missing"}), "NODE_NOT_FOUND")
	assert_eq(_snapshot(fixture), before)
	assert_eq(history.get_version(), version)
	fixture.free()

func test_wire_parameter_validation_and_history() -> void:
	_logger.errors.clear()
	var edited_root := EditorInterface.get_edited_scene_root()
	var fixture := FIXTURE.instantiate()
	fixture.name = "GraphParameters"
	fixture.scene_file_path = ""
	edited_root.add_child(fixture)
	_own(fixture, edited_root)
	var params: Dictionary = CASES.blend_space.duplicate(true)
	params.merge({"op": "blend_space", "player_path": str(fixture.get_node("AnimationPlayer").get_path()), "active": false})
	assert_has_key(_call(params), "data")
	var tree := fixture.get_node("AnimationTree") as AnimationTree
	var wire := {"op": "wire", "player_path": params.player_path, "parameter_path": "parameters/blend_position", "parameter_value": 1.0, "active": true}
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var baseline := _snapshot(fixture)
	var version := history.get_version()
	var dry := _call(wire.merged({"dry_run": true}))
	assert_has_key(dry, "data")
	assert_eq(dry.data.parameter_set.value, 1.0)
	assert_eq(_snapshot(fixture), baseline)
	assert_eq(history.get_version(), version)
	for invalid in [{"parameter_path": "parameters/missing"}, {"parameter_path": "active"}, {"parameter_value": "wrong"}, {"parameter_value": null}]:
		assert_is_error(_call(wire.merged(invalid, true)), "PROPERTY_NOT_ON_CLASS" if invalid.has("parameter_path") else "WRONG_TYPE")
		assert_eq(_snapshot(fixture), baseline)
		assert_eq(history.get_version(), version)
	assert_has_key(_call(wire), "data")
	assert_eq(tree.get("parameters/blend_position"), 1.0)
	assert_true(tree.active)
	assert_true(history.undo())
	assert_eq(_snapshot(fixture), baseline)
	assert_true(history.redo())
	assert_eq(tree.get("parameters/blend_position"), 1.0)
	assert_true(tree.active)
	fixture.free()
	assert_eq(_logger.errors, [], "parameter write and undo emit no errors")

func test_wire_vector_bool_and_enum_parameters() -> void:
	_logger.errors.clear()
	var edited_root := EditorInterface.get_edited_scene_root()
	var fixture := FIXTURE.instantiate()
	fixture.name = "GraphTypedParameters"
	fixture.scene_file_path = ""
	edited_root.add_child(fixture)
	_own(fixture, edited_root)
	var player_path := str(fixture.get_node("AnimationPlayer").get_path())
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_is_error(_call({"op": "wire", "player_path": player_path, "active": true}), "INVALID_PARAMS")
	assert_false(fixture.has_node("AnimationTree"))
	assert_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans)
	assert_has_key(_call({"op": "blend_space", "player_path": player_path, "dimensions": 2,
		"min": {"x": 0, "y": 0}, "max": {"x": 1, "y": 1},
		"points": [{"animation": "idle", "position": {"x": 0, "y": 0}}, {"animation": "walk", "position": {"x": 1, "y": 0}}]}), "data")
	var tree := fixture.get_node("AnimationTree") as AnimationTree
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var baseline := _snapshot(fixture)
	var wire := {"op": "wire", "player_path": player_path, "parameter_path": "parameters/blend_position", "parameter_value": {"x": 1.0, "y": 0.5}}
	var vector_result := _call(wire)
	assert_has_key(vector_result, "data")
	assert_eq(vector_result.data.parameter_set.value, {"x": 1.0, "y": 0.5})
	assert_eq(tree.get("parameters/blend_position"), Vector2(1.0, 0.5))
	assert_true(history.undo())
	assert_eq(_snapshot(fixture), baseline)
	assert_true(history.redo())
	assert_eq(tree.get("parameters/blend_position"), Vector2(1.0, 0.5))
	var sm: Dictionary = CASES.state_machine.duplicate(true)
	sm.merge({"op": "state_machine", "player_path": player_path})
	# Explicit condition exposes a boolean parameter.
	sm.transitions[0]["condition"] = "walking"
	assert_has_key(_call(sm), "data")
	wire.parameter_path = "parameters/conditions/walking"
	wire.parameter_value = "false"
	assert_is_error(_call(wire), "WRONG_TYPE")
	wire.parameter_value = true
	assert_has_key(_call(wire), "data")
	assert_true(tree.get(wire.parameter_path))
	assert_has_key(_call({"op": "one_shot_layer", "player_path": player_path, "animation": "jump"}), "data")
	wire.parameter_path = "parameters/OneShot/request"
	wire.parameter_value = 1.5
	assert_is_error(_call(wire), "WRONG_TYPE")
	wire.parameter_value = 999
	assert_is_error(_call(wire), "VALUE_OUT_OF_RANGE")
	wire.parameter_value = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	assert_has_key(_call(wire), "data")
	assert_eq(tree.get(wire.parameter_path), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	fixture.free()
	assert_eq(_logger.errors, [], "typed graph parameters emit no errors")
