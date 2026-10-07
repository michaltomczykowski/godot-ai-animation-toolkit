@tool
extends McpTestSuite

const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const PoseChecks := preload("res://tests/test_rig_pose_history.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const Codec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
var _undo: EditorUndoRedoManager
var _dispatcher
var _pose := PoseChecks.new()
var _logger: Capture.ErrorCapture

func suite_name() -> String: return "rig_modifier_allocation"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
func suite_teardown() -> void: OS.remove_logger(_logger)
func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "modifier-allocation", "command": "custom_tool:animation_rig_modifiers", "params": params})
func _snapshot(node: Node, top: bool = true, origin: Node = null) -> Dictionary:
	if origin == null: origin = node
	var state := _pose._snapshot(node, top, origin)
	state.settings = {}
	if node is SkeletonModifier3D:
		for prop in node.get_property_list():
			if int(prop.usage) & PROPERTY_USAGE_STORAGE and str(prop.name) not in ["script", "owner"]:
				state.settings[str(prop.name)] = node.get(prop.name)
	for child in node.get_children(): state.children[str(child.name)] = _snapshot(child, false, origin)
	return state
func _skeleton(name: String) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = name
	for i in 3:
		skeleton.add_bone(["hips", "spine", "chest"][i])
		if i > 0: skeleton.set_bone_parent(i, i - 1)
		var rest := Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
		skeleton.set_bone_rest(i, rest)
		skeleton.set_bone_pose_position(i, rest.origin)
	return skeleton
func _fixture(existing_retarget: bool = false) -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	var fixture := Node3D.new()
	fixture.name = "ModifierAllocation"
	fixture.position = Vector3(1.5, 0, -2)
	root.add_child(fixture)
	var source := _skeleton("Source")
	fixture.add_child(source)
	var target := _skeleton("Destination")
	fixture.add_child(target)
	var targets := Node3D.new()
	targets.name = "Targets"
	fixture.add_child(targets)
	for name in ["ExistingTarget", "ExistingPole", "Origin", "Center"]:
		var marker := Marker3D.new()
		marker.name = name
		marker.position = Vector3(0.3, 1.5, 0.6)
		targets.add_child(marker)
	var path := Path3D.new()
	path.name = "ExistingPath"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 1, 0))
	targets.add_child(path)
	var collider := SpringBoneCollisionSphere3D.new()
	collider.name = "Collider"
	collider.position = Vector3(2, 1, 3)
	targets.add_child(collider)
	var wrong := Node.new()
	wrong.name = "WrongType"
	targets.add_child(wrong)
	# Force the modifier's requested name to collide without changing the caller node.
	var reserved := Node.new()
	reserved.name = "Modifier"
	source.add_child(reserved)
	if existing_retarget:
		var modifier := RetargetModifier3D.new()
		modifier.name = "ExistingRetarget"
		modifier.active = false
		source.add_child(modifier)
		target.reparent(modifier)
	_pose._checks._own(fixture, root)
	return fixture
func _base(op: String, fixture: Node) -> Dictionary:
	return {"op": op, "name": "Modifier", "skeleton_path": str(fixture.get_node("Source").get_path()), "active": false}
func _leaks(before: Array, label: String) -> void:
	var after := Node.get_orphan_node_ids()
	if after != before: print("MODIFIER_BASELINE_LEAK=" + label + " count=" + str(after.size() - before.size()))
	assert_eq(after, before, label + " exact orphan IDs")
	# Baseline failures must not contaminate the next case. Only reclaim nodes
	# newly leaked by this test call; detached history nodes in before survive.
	for id in after:
		if not before.has(id):
			var candidate = instance_from_id(id)
			if is_instance_valid(candidate) and candidate is Node: candidate.free()
func _probe(params: Dictionary, fixture: Node, refusal: bool, label: String) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var before := _snapshot(root)
	var scene_history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var scene_version := scene_history.get_version()
	var global_version := global_history.get_version()
	var caller_ids := []
	for child in fixture.get_node("Targets").get_children(): caller_ids.append(child.get_instance_id())
	var errors := _logger.errors.size()
	var orphans := Node.get_orphan_node_ids()
	var result := _call(params)
	if refusal: assert_has_key(result.get("error", {}), "code", label + " typed refusal")
	else:
		assert_has_key(result, "data", label + " dry success")
		assert_eq(result.get("data", {}).get("dry_run"), true, label + " reports dry")
		assert_eq(result.get("data", {}).get("undoable"), false, label + " no action claimed")
	_leaks(orphans, label)
	assert_true(_pose._same(_snapshot(root), before), label + " complete scene unchanged")
	assert_eq(scene_history.get_version(), scene_version, label + " zero scene actions")
	assert_eq(global_history.get_version(), global_version, label + " zero global actions")
	for id in caller_ids: assert_true(is_instance_id_valid(id), label + " caller node survives")
	assert_eq(_logger.errors.size(), errors, label + " zero engine errors " + str(_logger.errors.slice(errors)))
	return result
func _success(params: Dictionary, fixture: Node, label: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var baseline := _snapshot(root)
	var existing := root.get_children()
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var errors := _logger.errors.size()
	var dry := _probe(params.merged({"dry_run": true}), fixture, false, label)
	var result := _call(params)
	assert_has_key(result, "data", label + " commit")
	for field in ["modifier_path", "target_path", "pole_path", "path_path", "moved_path", "collisions_moved"]:
		if result.get("data", {}).has(field): assert_eq(dry.get("data", {}).get(field), result.data[field], label + " predicted " + field)
	var modifier := Codec.resolve_scene_path(str(result.get("data", {}).get("modifier_path", "")), root)
	assert_true(modifier is SkeletonModifier3D, label + " committed modifier resolves")
	assert_eq(history.get_version(), version + 1, label + " one scene action")
	assert_eq(global_history.get_version(), global_version, label + " zero global actions on commit")
	var generated := _snapshot(root)
	assert_true(history.undo(), label + " undo")
	assert_true(is_instance_valid(modifier), label + " history retains modifier")
	assert_true(_pose._same(_snapshot(root), baseline), label + " undo restores scene")
	assert_true(history.redo(), label + " redo")
	assert_true(Codec.resolve_scene_path(str(result.get("data", {}).get("modifier_path", "")), root) == modifier, label + " exact identity on redo")
	assert_true(_pose._same(_snapshot(root), generated), label + " redo restores scene")
	assert_eq(_logger.errors.size(), errors, label + " no engine errors through commit/undo/redo " + str(_logger.errors.slice(errors)))
	for child in root.get_children():
		if not existing.has(child): child.free()
	fixture.free()
func test_ik_allocation() -> void:
	for kind in ["two_bone", "ccdik", "fabrik", "spline"]:
		for supplied in [false, true]:
			var fixture := _fixture()
			var params := _base("ik_setup", fixture).merged({"kind": kind, "chain": ["hips", "spine", "chest"]})
			if supplied:
				params.target_path = str(fixture.get_node("Targets/ExistingPath" if kind == "spline" else "Targets/ExistingTarget").get_path())
				if kind == "two_bone": params.pole_path = str(fixture.get_node("Targets/ExistingPole").get_path())
			_success(params, fixture, "IK %s supplied=%s" % [kind, supplied])
func test_look_at_allocation_and_refusal() -> void:
	for supplied in [false, true]:
		var fixture := _fixture()
		var params := _base("look_at_setup", fixture).merged({"bone": "chest"})
		if supplied: params.target_path = str(fixture.get_node("Targets/ExistingTarget").get_path())
		for invalid in [{"origin_from": "invalid"}, {"origin_bone": "missing"}, {"origin_node": "/Missing"}, {"primary_axis": "invalid"}]:
			for dry in [false, true]: _probe(params.merged(invalid).merged({"dry_run": dry}), fixture, true, "look refusal " + str(invalid) + " dry=" + str(dry))
		_success(params, fixture, "look supplied=" + str(supplied))
func test_twist_allocation_and_refusal() -> void:
	var fixture := _fixture()
	var params := _base("twist_setup", fixture).merged({"spine_chain": ["hips", "spine", "chest"]})
	for invalid in [{"mode": "even", "weight_position": 0.5}, {"damping": 0.5}, {"twist_from_rest": false, "twist_from": {"kind": "invalid"}}, {"twist_from_rest": false, "twist_from": 0.5}, {"twist_from_rest": false, "twist_from": {"kind": "quaternion", "w": 0.0}}, {"twist_from_rest": false, "twist_from": {"kind": "quaternion", "w": 2.0}}]:
		for dry in [false, true]: _probe(params.merged({"disperse": invalid, "dry_run": dry}), fixture, true, "twist refusal " + str(invalid) + " dry=" + str(dry))
	_success(params, fixture, "twist")
func test_spring_allocation_and_refusal() -> void:
	for supplied in [false, true]:
		var fixture := _fixture()
		var spring := {"root_bone": "hips", "end_bone": "chest"}
		if supplied: spring.merge({"collisions": [str(fixture.get_node("Targets/Collider").get_path())], "center_from": "world_origin", "enable_all_child_collisions": false})
		var params := _base("spring_setup", fixture).merged({"springs": [spring]})
		for invalid in [{"rotation_axis": "invalid"}, {"center_from": "invalid"}, {"collisions": ["/Missing"]}]:
			for dry in [false, true]: _probe(params.merged({"springs": [spring.merged(invalid, true)], "dry_run": dry}, true), fixture, true, "spring refusal " + str(invalid) + " dry=" + str(dry))
		_success(params, fixture, "spring supplied=" + str(supplied))
func test_retarget_allocation_and_refusal() -> void:
	for existing in [false, true]:
		var fixture := _fixture(existing)
		var target := fixture.get_node("Source/ExistingRetarget/Destination" if existing else "Destination")
		# Retarget's documented target layout is a direct skeleton, not a wrapper.
		if not existing:
			target.reparent(EditorInterface.get_edited_scene_root())
			target.owner = EditorInterface.get_edited_scene_root()
		var params := _base("retarget_setup", fixture).merged({"target_path": str(target.get_path()), "profile": "auto"})
		for invalid in [{"position": false, "rotation": false, "scale": false}, {"target_path": "/Missing"}]:
			for dry in [false, true]: _probe(params.merged(invalid, true).merged({"dry_run": dry}), fixture, true, "retarget refusal " + str(invalid) + " dry=" + str(dry))
		_success(params, fixture, "retarget existing=" + str(existing))
		if is_instance_valid(target): target.free()

func test_spring_center_and_collision_contracts() -> void:
	var fixture := _fixture()
	var params := _base("spring_setup", fixture)
	var wrong_path := str(fixture.get_node("Targets/WrongType").get_path())
	for invalid in [{"center_from": "node"}, {"center_from": "NODE"}, {"center_from": "node", "center_node": wrong_path}, {"center_from": "bone"}, {"center_from": "BONE"}, {"center_from": "bone", "center_bone": "missing"}, {"collisions": [wrong_path]}, {"exclude_collisions": [wrong_path]}, {"collisions": "invalid"}, {"exclude_collisions": {}}]:
		var spring := {"root_bone": "hips", "end_bone": "chest"}.merged(invalid)
		for dry in [false, true]: _probe(params.merged({"springs": [spring], "dry_run": dry}), fixture, true, "spring center/collision refusal " + str(invalid) + " dry=" + str(dry))
	for dry in [false, true]: _probe(params.merged({"springs": "invalid", "dry_run": dry}), fixture, true, "spring array refusal dry=" + str(dry))
	# PackedScene preserves engine-generated '@' names whereas duplicate()
	# sanitizes them. Two instances of an in-memory packed subtree reproduce a
	# real name collision without assigning an invalid name through its setter.
	var template := Node3D.new()
	template.name = "ColliderSubtree"
	template.add_child(SpringBoneCollisionSphere3D.new())
	template.add_child(SpringBoneCollisionSphere3D.new())
	_pose._checks._own(template, template)
	var packed := PackedScene.new()
	assert_eq(packed.pack(template), OK, "engine-name subtree pack")
	template.free()
	var group_a := packed.instantiate()
	group_a.name = "A"
	fixture.get_node("Targets").add_child(group_a)
	var group_b := packed.instantiate()
	group_b.name = "B"
	fixture.get_node("Targets").add_child(group_b)
	var first := group_a.get_child(1)
	var second := group_b.get_child(1)
	assert_true(str(first.name).contains("@") and first.name == second.name, "late-refusal engine-name fixture")
	_pose._checks._own(fixture, EditorInterface.get_edited_scene_root())
	for dry in [false, true]: _probe(params.merged({"springs": [{"root_bone": "hips", "end_bone": "chest", "collisions": [str(first.get_path()), str(second.get_path())]}], "dry_run": dry}), fixture, true, "spring late generated-name refusal dry=" + str(dry))
	assert_eq(_logger.errors, [], "entire suite captures no engine errors, including fixtures")
	fixture.free()
func test_registry_allocation_coverage() -> void:
	var names := Ops.op_names("animation_rig_modifiers")
	names.sort()
	assert_eq(names, ["ik_setup", "look_at_setup", "retarget_setup", "spring_setup", "twist_setup"], "every advertised modifier has allocation checks")

func test_look_at_external_origin_contract() -> void:
	var fixture := _fixture()
	fixture.get_node("Targets/Origin").position = Vector3(-0.4, 1.2, -0.5)
	fixture.get_node("Targets/ExistingTarget").position = Vector3(0.6, 1.2, 0.8)
	var params := _base("look_at_setup", fixture).merged({"bone": "chest", "origin_from": "external_node", "origin_node": str(fixture.get_node("Targets/Origin").get_path()), "target_path": str(fixture.get_node("Targets/ExistingTarget").get_path()), "duration": 0.0})
	for dry in [false, true]:
		_probe(params.merged({"origin_node": str(fixture.get_node("Targets/WrongType").get_path()), "dry_run": dry}, true), fixture, true, "external origin wrong type dry=" + str(dry))
	var result := _call(params)
	assert_has_key(result, "data", "external origin commit")
	var modifier := Codec.resolve_scene_path(str(result.get("data", {}).get("modifier_path", "")), EditorInterface.get_edited_scene_root()) as LookAtModifier3D
	if modifier != null:
		assert_true(modifier.get_node_or_null(modifier.get_origin_external_node()) == fixture.get_node("Targets/Origin"), "origin path resolves from modifier")
		var packed := PackedScene.new()
		assert_eq(packed.pack(EditorInterface.get_edited_scene_root()), OK, "external origin pack")
		assert_eq(ResourceSaver.save(packed, "user://rig_modifier_external_origin.tscn"), OK, "external origin save")
		var reopened := (ResourceLoader.load("user://rig_modifier_external_origin.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var saved := reopened.get_node("ModifierAllocation/Source/Modifier2") as LookAtModifier3D
		assert_true(saved.get_node_or_null(saved.get_origin_external_node()) == reopened.get_node("ModifierAllocation/Targets/Origin"), "saved origin resolves from modifier")
		reopened.free()
	else: assert_true(false, "external origin modifier exists")
	fixture.free()
	var parent_origin := _fixture()
	var parent_params := _base("look_at_setup", parent_origin).merged({"bone": "chest", "origin_from": "external_node", "origin_node": str(parent_origin.get_node("Source").get_path()), "target_path": str(parent_origin.get_node("Targets/ExistingTarget").get_path())})
	_success(parent_params, parent_origin, "external origin is modifier parent")
