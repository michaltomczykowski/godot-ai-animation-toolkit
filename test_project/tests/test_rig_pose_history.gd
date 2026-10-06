@tool
extends McpTestSuite

const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Checks := preload("res://tests/test_preset_library_history.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const DIR := "res://animation_toolkit/rig_history_contracts/"
var _undo: EditorUndoRedoManager
var _dispatcher
var _checks := Checks.new()
var _logger: Capture.ErrorCapture
var _files: Array[String] = []

func suite_name() -> String: return "rig_pose_history"
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
	return _dispatcher.call("_dispatch", {"request_id": "rig-pose-history", "command": "custom_tool:animation_rig", "params": params})
func _same(a: Variant, b: Variant) -> bool:
	if a is Transform2D and b is Transform2D: return a.is_equal_approx(b)
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
	return _checks._same(a, b)
func _snapshot(node: Node, top: bool = true, origin: Node = null) -> Dictionary:
	if origin == null: origin = node
	var result := {"type": node.get_class(), "children": {}}
	if not top: result.owner = "" if node.owner == null else str(origin.get_path_to(node.owner)) if origin == node.owner or origin.is_ancestor_of(node.owner) else "[scene]"
	if node is Node3D: result.transform = node.transform
	if node is Node2D: result.transform = node.transform
	if node is Bone2D:
		result.rest = node.rest
		result.length = node.get_length()
		result.auto = node.get_autocalculate_length_and_angle()
	if node is Skeleton3D:
		var bones: Array = []
		for i in node.get_bone_count():
			var meta := {}
			for key in node.get_bone_meta_list(i): meta[str(key)] = node.get_bone_meta(i, key)
			bones.append({"name": node.get_bone_name(i), "parent": node.get_bone_parent(i), "rest": node.get_bone_rest(i), "pose": node.get_bone_pose(i), "enabled": node.is_bone_enabled(i), "meta": meta})
		result.bones = bones
	for child in node.get_children(): result.children[str(child.name)] = _snapshot(child, false, origin)
	return result

func _seed(kind: String) -> Node:
	var fixture := Node.new()
	fixture.name = "RigPoseHistory"
	if kind == "3d":
		var skeleton := Skeleton3D.new()
		skeleton.name = "Skeleton"
		fixture.add_child(skeleton)
		for i in 3:
			skeleton.add_bone(["arm_L", "arm_R", "untouched"][i])
			var rest := Transform3D(Basis(Vector3.BACK, [0.2, -0.1, 0.35][i]), Vector3(i + 1, 2, 0))
			skeleton.set_bone_rest(i, rest)
			skeleton.set_bone_pose_position(i, rest.origin + Vector3(0.1, 0.2, 0))
			skeleton.set_bone_pose_rotation(i, Quaternion(Vector3.BACK, [0.5, -0.4, 0.7][i]))
			skeleton.set_bone_pose_scale(i, Vector3(1.2, 0.8, 1.1))
			skeleton.set_bone_meta(i, &"authored", "keep")
			skeleton.set_bone_enabled(i, i != 2)
	else:
		var skeleton := Skeleton2D.new()
		skeleton.name = "Skeleton"
		fixture.add_child(skeleton)
		for i in 3:
			var bone := Bone2D.new()
			bone.name = ["arm_L", "arm_R", "untouched"][i]
			bone.set_autocalculate_length_and_angle(false)
			bone.set_length(10.0 + i)
			bone.rest = Transform2D([0.2, -0.1, 0.35][i], Vector2(i + 1, 2))
			bone.position = bone.rest.origin + Vector2(0.1, 0.2)
			bone.rotation = [0.5, -0.4, 0.7][i]
			bone.scale = Vector2(1.2, 0.8)
			skeleton.add_child(bone)
	_checks._own(fixture, fixture)
	return fixture

func _pose(bone: String = "arm_L") -> Dictionary:
	return {"rest_relative": true, "bones": {bone: {"rotation": {"kind": "quaternion", "z": sin(0.3), "w": cos(0.3)}, "position": {"kind": "vector3", "x": 0.4, "y": -0.3}, "scale": {"kind": "vector3", "x": 1.6, "y": 0.6, "z": 1.3}}}}

func _persist(fixture: Node, expected: Dictionary, label: String) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(EditorInterface.get_edited_scene_root()), OK, label + " pack")
	var path := "user://rig_pose_history_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK, label + " save")
	var reopened := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved := reopened.get_node(str(fixture.name))
	assert_true(_same(_snapshot(saved), expected), label + " persisted exact state")
	reopened.free()

func _case(kind: String, mode: String, variant: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var fixture := _seed(kind)
	var peer: Node
	var source_path := "user://rig_pose_source_%s_%s_%s.tscn" % [kind, mode, variant]
	if mode != "local":
		var packed := PackedScene.new()
		assert_eq(packed.pack(fixture), OK)
		assert_eq(ResourceSaver.save(packed, source_path), OK)
		fixture.free()
		packed = ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		fixture = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		peer = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		peer.name = "RigPosePeer"
		root.add_child(peer)
		peer.owner = root
	root.add_child(fixture)
	fixture.owner = root
	if mode == "local": _checks._own(fixture, root)
	if mode == "editable": root.set_editable_instance(fixture, true)
	var baseline := _snapshot(fixture)
	var peer_before := _snapshot(peer) if peer != null else {}
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var errors := _logger.errors.size()
	var skeleton := fixture.get_node("Skeleton")
	var params := {"op": "pose_apply", "skeleton_path": str(skeleton.get_path()), "pose": _pose(), "blend": 0.5 if variant in ["blend", "reset_blend"] else 1.0, "reset_first": variant in ["reset", "reset_blend"], "mirror": variant == "mirror"}
	var label := "%s_%s_%s" % [kind, mode, variant]
	var dry_reply := _call(params.merged({"dry_run": true}))
	assert_has_key(dry_reply, "data", label + " dry " + str(dry_reply))
	assert_true(_same(_snapshot(fixture), baseline), label + " dry unchanged")
	assert_has_key(_call(params.merged({"pose": _pose("ghost")}, true)).get("error", {}), "code", label + " absent pose typed refusal")
	assert_eq(history.get_version(), version, label + " dry/rejected history")
	assert_true(_same(_snapshot(fixture), baseline), label + " rejected unchanged")
	var reply := _call(params)
	assert_has_key(reply, "data", label + " write " + str(reply))
	assert_eq(reply.get("data", {}).get("undoable"), true)
	var generated := _snapshot(fixture)
	assert_false(_same(generated, baseline), label + " effect")
	_check_expected(skeleton, variant, label)
	assert_eq(history.get_version(), version + 1, label + " one scene action")
	assert_eq(global_history.get_version(), global_version, label + " zero global actions")
	assert_true(history.undo(), label + " undo")
	assert_true(_same(_snapshot(fixture), baseline), label + " exact undo")
	assert_eq(root.is_editable_instance(fixture), mode == "editable", label + " permissions undo")
	_persist(fixture, baseline, label + "_undo")
	assert_true(history.redo(), label + " redo")
	assert_true(_same(_snapshot(fixture), generated), label + " exact redo")
	_persist(fixture, generated, label + "_redo")
	if peer != null:
		assert_true(_same(_snapshot(peer), peer_before), label + " peer unchanged")
		var pristine := (ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		assert_true(_same(_snapshot(pristine), baseline), label + " source unchanged")
		pristine.free()
		peer.free()
	assert_eq(_logger.errors.size(), errors, label + " zero engine errors " + str(_logger.errors.slice(errors)))
	fixture.free()

func _check_expected(skeleton: Node, variant: String, label: String) -> void:
	# Independent authored expectations; no PoseMath conversions or handler snapshots.
	var index := 1 if variant == "mirror" else 0
	var angle := -0.7 if variant == "mirror" else 0.8 if variant == "apply" or variant == "reset" else 0.65
	var position := Vector3(1.4, 1.7, 0) if index == 0 else Vector3(1.6, 1.7, 0)
	var scale := Vector3(1.6, 0.6, 1.3)
	if variant == "blend":
		position = Vector3(1.25, 1.95, 0)
		scale = Vector3(1.4, 0.7, 1.2)
	if variant == "reset_blend":
		angle = 0.5
		position = Vector3(1.2, 1.85, 0)
		scale = Vector3(1.3, 0.8, 1.15)
	if skeleton is Skeleton3D:
		assert_true(skeleton.get_bone_pose_rotation(index).angle_to(Quaternion(Vector3.BACK, angle)) < 0.001, label + " authored rotation")
		assert_true(skeleton.get_bone_pose_position(index).is_equal_approx(position), label + " authored position")
		assert_true(skeleton.get_bone_pose_scale(index).is_equal_approx(scale), label + " authored scale")
		assert_true(skeleton.get_bone_pose(2).is_equal_approx(skeleton.get_bone_rest(2)) if variant in ["reset", "reset_blend"] else skeleton.get_bone_pose_position(2).is_equal_approx(Vector3(3.1, 2.2, 0)), label + " untouched/reset bone")
	else:
		var bone: Bone2D = skeleton.get_bone(index)
		assert_true(is_equal_approx(bone.rotation, angle), label + " authored rotation")
		assert_true(bone.position.is_equal_approx(Vector2(position.x, position.y)), label + " authored position")
		assert_true(bone.scale.is_equal_approx(Vector2(scale.x, scale.y)), label + " authored scale")
		var untouched: Bone2D = skeleton.get_bone(2)
		assert_true(untouched.transform.is_equal_approx(untouched.rest) if variant in ["reset", "reset_blend"] else untouched.position.is_equal_approx(Vector2(3.1, 2.2)), label + " untouched/reset bone")

func _matrix(mode: String) -> void:
	for kind in ["3d", "2d"]:
		for variant in ["apply", "blend", "reset", "reset_blend", "mirror"]: _case(kind, mode, variant)
func test_local_pose_history() -> void: _matrix("local")
func test_locked_pose_history() -> void: _matrix("locked")
func test_editable_pose_history() -> void: _matrix("editable")

func test_registry_contract_categories() -> void:
	var names: Array = Ops.op_names("animation_rig")
	names.sort()
	var expected := ["pose_apply", "pose_blend", "pose_save", "pose_list", "rig_get", "rig_chain", "pose_to_clip", "walk_cycle", "idle_breathing", "blink", "jumping_jack", "squat", "punch", "bake_pose_sequence"]
	expected.sort()
	assert_eq(names, expected, "all rig contracts classified; clip matrix is next")
	names = Ops.op_names("animation_rig_modifiers")
	names.sort()
	expected = ["ik_setup", "spring_setup", "look_at_setup", "twist_setup", "retarget_setup"]
	expected.sort()
	assert_eq(names, expected, "all modifier contracts classified; modifier matrix is next")

func _file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	_files.append(path)
func test_pose_file_and_shape_contracts() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var fixture := _seed("3d")
	root.add_child(fixture)
	_checks._own(fixture, root)
	var baseline := _snapshot(fixture)
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var errors := _logger.errors.size()
	var path := DIR + "saved.json"
	_file(path, "sentinel")
	var params := {"op": "pose_save", "skeleton_path": str(fixture.get_node("Skeleton").get_path()), "path": path, "overwrite": false}
	for dry in [true, false]:
		assert_has_key(_call(params.merged({"dry_run": dry})).get("error", {}), "code", "overwrite refusal matches dry")
		assert_eq(FileAccess.get_file_as_string(path), "sentinel")
	var saved := _call(params.merged({"overwrite": true}, true))
	assert_has_key(saved, "data")
	assert_eq(saved.get("data", {}).get("undoable"), false)
	var bytes := FileAccess.get_file_as_bytes(path)
	assert_has_key(_call(params.merged({"overwrite": true, "dry_run": true}, true)), "data")
	assert_eq(FileAccess.get_file_as_bytes(path), bytes)
	var blended := _call({"op": "pose_blend", "from_pose": _pose(), "to_pose": _pose(), "path": DIR + "blend.json", "factor": 0.25})
	_files.append(DIR + "blend.json")
	assert_has_key(blended, "data")
	assert_eq(blended.get("data", {}).get("undoable"), false)
	assert_has_key(_call({"op": "pose_list", "pose_dir": DIR}), "data")
	assert_has_key(_call({"op": "rig_get", "skeleton_path": params.skeleton_path}), "data")
	_file(DIR + "broken.json", "{broken")
	assert_has_key(_call({"op": "pose_apply", "skeleton_path": params.skeleton_path, "path": DIR + "broken.json"}).get("error", {}), "code", "bad JSON typed")
	for pose in [{"bones": []}, {"bones": {"arm_L": 4}}, {"bones": {"arm_L": {"rotation": 4}}}, {"bones": {"arm_L": {"position": {"kind": "vector2"}}}}, {"bones": {"arm_L": {"scale": {"kind": "vector3", "x": 0}}}}, {"bones": {"arm_L": {"rotation": {"kind": "quaternion", "w": 0}}}}, {"bones": {"arm_L": {}}, "rest_relative": false}]:
		assert_has_key(_call({"op": "pose_apply", "skeleton_path": params.skeleton_path, "pose": pose}).get("error", {}), "code", "invalid pose " + str(pose))
	for field in ["blend", "factor"]:
		var invalid := {"op": "pose_apply" if field == "blend" else "pose_blend", "skeleton_path": params.skeleton_path, "pose": _pose(), "from_pose": _pose(), "to_pose": _pose(), field: NAN}
		assert_has_key(_call(invalid).get("error", {}), "code", "nonfinite " + field)
	assert_true(_same(_snapshot(fixture), baseline), "file/read/rejected scene unchanged")
	assert_eq(history.get_version(), version, "file/read/rejected scene history unchanged")
	assert_eq(global_history.get_version(), global_version, "file/read/rejected global history unchanged")
	assert_eq(_logger.errors.size(), errors, "malformed poses produce no engine errors " + str(_logger.errors.slice(errors)))
	fixture.free()
