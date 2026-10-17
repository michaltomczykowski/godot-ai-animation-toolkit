@tool
extends McpTestSuite

const PoseHistory := preload("res://tests/test_rig_pose_history.gd")
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
var _checks := PoseHistory.new()
var _undo: EditorUndoRedoManager
var _dispatcher
var _logger: Capture.ErrorCapture
func suite_name() -> String: return "rig_chain_history"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
func suite_teardown() -> void: OS.remove_logger(_logger)
func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "rig-chain-history", "command": "custom_tool:animation_rig", "params": params})
func _persist(fixture: Node, expected: Dictionary, label: String) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(EditorInterface.get_edited_scene_root()), OK)
	var path := "user://rig_chain_history_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK)
	var reopened := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	assert_true(_checks._same(_checks._snapshot(reopened.get_node(str(fixture.name))), expected), label + " saved state")
	reopened.free()

func _case(kind: String, mode: String, variant: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var fixture := _checks._seed(kind)
	fixture.name = "RigChainHistory"
	if variant == "subtree":
		var branch: Node = Node3D.new() if kind == "3d" else Node2D.new()
		branch.name = "Branch"
		fixture.add_child(branch)
		var child: Node = Node3D.new() if kind == "3d" else Node2D.new()
		child.name = "Leaf"
		branch.add_child(child)
		if child is Node3D:
			child.transform = Transform3D(Basis(Vector3.BACK, 0.3).scaled(Vector3(1.4, 0.8, 1.2)), Vector3(1, 2, 3))
		else:
			child.transform = Transform2D(0.3, Vector2(1.4, 0.8), 0.1, Vector2(1, 2))
		_checks._checks._own(fixture, fixture)
	var peer: Node
	var source_path := "user://rig_chain_source_%s_%s_%s.tscn" % [kind, mode, variant]
	if mode != "local":
		var packed := PackedScene.new()
		assert_eq(packed.pack(fixture), OK)
		assert_eq(ResourceSaver.save(packed, source_path), OK)
		fixture.free()
		packed = ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		fixture = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		peer = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		peer.name = "RigChainPeer"
		root.add_child(peer)
		peer.owner = root
	root.add_child(fixture)
	fixture.owner = root
	if mode == "local": _checks._checks._own(fixture, root)
	if mode == "editable": root.set_editable_instance(fixture, true)
	var baseline := _checks._snapshot(fixture)
	var peer_before := _checks._snapshot(peer) if peer != null else {}
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var errors := _logger.errors.size()
	var params := {"op": "rig_chain", "kind": kind, "name": "Generated", "skeleton_path": str(fixture.get_path()) + ("/Skeleton" if variant == "append" else "/Generated"), "bones": [{"name": "tool", "parent": "arm_L" if variant == "append" else "", "position": [0.5, 1.0, 0.0], "rotation": [0.0, 0.0, 30.0], "scale": [1.4, 0.8, 1.2], "length": 15.0}]}
	if variant == "subtree": params = {"op": "rig_chain", "node_path": str(fixture.get_node("Branch").get_path()), "name": "Generated"}
	var label := "%s_%s_%s" % [kind, mode, variant]
	var nodes_before := Node.get_orphan_node_ids()
	var planned := _call(params.merged({"dry_run": true}))
	assert_has_key(planned, "data", label + " dry")
	assert_eq(Node.get_orphan_node_ids(), nodes_before, label + " dry has no leaked nodes")
	assert_true(_checks._same(_checks._snapshot(fixture), baseline), label + " dry unchanged")
	var bad := params.merged({"node_path": "/Missing"}, true)
	assert_has_key(_call(bad).get("error", {}), "code", label + " typed rejection")
	assert_eq(history.get_version(), version, label + " dry/rejected history")
	var made := _call(params)
	assert_has_key(made, "data", label + " write " + str(made))
	assert_eq(planned.get("data", {}).get("skeleton_path"), made.get("data", {}).get("skeleton_path"), label + " planned path matches commit")
	assert_eq(history.get_version(), version + 1, label + " one scene action")
	assert_eq(global_history.get_version(), global_version, label + " no global action")
	var generated := _checks._snapshot(fixture)
	assert_false(_checks._same(generated, baseline), label + " effect")
	var skeleton := fixture.get_node("Branch/Generated" if variant == "subtree" else "Skeleton" if variant == "append" else "Generated")
	if skeleton is Skeleton3D:
		var index: int = skeleton.find_bone("Leaf" if variant == "subtree" else "tool")
		var expected: Transform3D = fixture.get_node("Branch/Leaf").transform if variant == "subtree" else Transform3D(Basis.from_euler(Vector3(0, 0, PI / 6)).scaled(Vector3(1.4, 0.8, 1.2)), Vector3(0.5, 1, 0))
		assert_true(skeleton.get_bone_rest(index).is_equal_approx(expected), label + " complete authored rest")
		assert_eq(skeleton.get_bone_parent(index), 0 if variant != "create" else -1, label + " parent")
	else:
		var bone := skeleton.get_node("Branch/Leaf" if variant == "subtree" else "arm_L/tool" if variant == "append" else "tool") as Bone2D
		assert_true(bone != null, label + " parent node")
		if bone != null:
			var expected: Transform2D = fixture.get_node("Branch/Leaf").transform if variant == "subtree" else Transform2D(PI / 6, Vector2(1.4, 0.8), 0, Vector2(0.5, 1))
			assert_true(bone.rest.is_equal_approx(expected), label + " complete authored rest")
			assert_true(bone.transform.is_equal_approx(expected), label + " initialized pose")
	assert_true(history.undo(), label + " undo")
	assert_true(_checks._same(_checks._snapshot(fixture), baseline), label + " exact undo")
	assert_eq(root.is_editable_instance(fixture), mode == "editable", label + " permissions undo")
	_persist(fixture, baseline, label + "_undo")
	assert_true(history.redo(), label + " redo")
	assert_true(_checks._same(_checks._snapshot(fixture), generated), label + " exact redo")
	_persist(fixture, generated, label + "_redo")
	if peer != null:
		assert_true(_checks._same(_checks._snapshot(peer), peer_before), label + " peer unchanged")
		var pristine := (ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		assert_true(_checks._same(_checks._snapshot(pristine), baseline), label + " source unchanged")
		pristine.free()
		peer.free()
	assert_eq(_logger.errors.size(), errors, label + " zero engine errors " + str(_logger.errors.slice(errors)))
	fixture.free()
func _matrix(mode: String) -> void:
	for kind in ["3d", "2d"]:
		for variant in ["create", "append", "subtree"]: _case(kind, mode, variant)
func test_local_chain_history() -> void: _matrix("local")
func test_locked_chain_history() -> void: _matrix("locked")
func test_editable_chain_history() -> void: _matrix("editable")

func test_chain_rejections_have_no_effect() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var fixture := _checks._seed("2d")
	root.add_child(fixture)
	_checks._checks._own(fixture, root)
	var baseline := _checks._snapshot(fixture)
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var version := history.get_version()
	var errors := _logger.errors.size()
	var params := {"op": "rig_chain", "skeleton_path": str(fixture.get_node("Skeleton").get_path()), "bones": [{"name": "valid"}]}
	for spec in [42, [{"name": "arm.L"}], [{"name": "bad", "position": ["wrong", 1]}], [{"name": "bad", "rotation": NAN}], [{"name": "bad", "scale": [1, 0]}], [{"name": "bad", "length": -1}], [{"name": "bad", "parent": "missing"}]]:
		for dry in [true, false]:
			assert_has_key(_call(params.merged({"bones": spec, "dry_run": dry}, true)).get("error", {}), "code", "typed chain refusal " + str(spec))
	var orphans := Node.get_orphan_node_ids()
	for name in ["", "bad.name", "Skeleton"]:
		for dry in [true, false]:
			var rejected := _call(params.merged({"skeleton_path": str(fixture.get_path()) + "/New", "name": name, "dry_run": dry}, true))
			assert_has_key(rejected.get("error", {}), "code", "typed skeleton name refusal " + name)
	assert_eq(Node.get_orphan_node_ids(), orphans, "rejected names allocate no nodes")
	assert_eq(history.get_version(), version)
	assert_true(_checks._same(_checks._snapshot(fixture), baseline))
	assert_eq(_logger.errors.size(), errors)
	fixture.free()
