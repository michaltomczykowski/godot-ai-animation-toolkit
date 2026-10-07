@tool
extends McpTestSuite

## Public-route writes; independent processes consume the saved manifest.
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Pose := preload("res://tests/test_rig_pose_history.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const Codec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const OPERATIONS := ["ik_setup", "look_at_setup", "twist_setup", "spring_setup", "retarget_setup"]
const MANIFEST := "user://rig_modifier_history.json"
var _undo: EditorUndoRedoManager
var _dispatcher
var _pose := Pose.new()
var _logger: Capture.ErrorCapture
var _rows: Array = []

func suite_name() -> String: return "rig_modifier_history"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
	_rows.clear()
	_manifest()
func suite_teardown() -> void: OS.remove_logger(_logger)
func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "modifier-history", "command": "custom_tool:animation_rig_modifiers", "params": params})
func _manifest() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": 1, "cases": _rows}))
	file.close()
func _freeze(value: Variant) -> Variant:
	if value is Resource:
		var result := {"class": value.get_class(), "properties": {}}
		for entry in value.get_property_list():
			var key := str(entry.name)
			if int(entry.usage) & PROPERTY_USAGE_STORAGE and key not in ["script", "resource_path"]:
				result.properties[key] = _freeze(value.get(key))
		return result
	if value is Array:
		var result: Array = []
		for entry in value: result.append(_freeze(entry))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _freeze(value[key])
		return result
	return value
func _snapshot(node: Node, origin: Node = null) -> Dictionary:
	if origin == null: origin = node
	var result := _pose._snapshot(node, node == origin, origin)
	result.order = []
	result.metadata = {}
	for key in node.get_meta_list():
		if not str(key).begins_with("_"): result.metadata[str(key)] = _freeze(node.get_meta(key))
	result.editable = {}
	result.settings = {}
	if node is SkeletonModifier3D:
		for entry in node.get_property_list():
			var key := str(entry.name)
			# Spring joint bone names/indices are engine-generated read-only caches;
			# off-tree PackedScene instances rebuild them when entering the tree.
			var generated_bone := key.contains("/joints/") and (key.ends_with("/bone") or key.ends_with("/bone_name"))
			if int(entry.usage) & PROPERTY_USAGE_STORAGE and key not in ["script", "owner"] and not generated_bone: result.settings[key] = _freeze(node.get(key))
	if node is Path3D: result.curve = _freeze(node.curve)
	if node is SpringBoneCollision3D:
		for entry in node.get_property_list():
			if int(entry.usage) & PROPERTY_USAGE_STORAGE and str(entry.name) not in ["script", "owner"]: result.settings[str(entry.name)] = _freeze(node.get(entry.name))
	for child in node.get_children():
		result.order.append(str(child.name))
		if not child.scene_file_path.is_empty(): result.editable[str(child.name)] = node.is_editable_instance(child)
		result.children[str(child.name)] = _snapshot(child, origin)
	return result
func _identities(node: Node, result: Dictionary = {}) -> Dictionary:
	result[str(node.get_path())] = node.get_instance_id()
	for child in node.get_children(): _identities(child, result)
	return result
func _skeleton(name: String) -> Skeleton3D:
	var rig := Skeleton3D.new()
	rig.name = name
	rig.position = Vector3(0.2, 0.1, -0.3)
	rig.rotation = Vector3(0.05, -0.15, 0.08)
	for i in 5:
		rig.add_bone(["hips", "spine", "chest", "head", "untouched"][i])
		if i in [1, 2, 3]: rig.set_bone_parent(i, i - 1)
		var rest := Transform3D(Basis.from_euler(Vector3(0.02 * i, 0, 0.05 * i)), Vector3(0, 0.45 if i > 0 else 0.3, 0))
		rig.set_bone_rest(i, rest)
		rig.set_bone_pose_position(i, rest.origin)
		rig.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, 0.03))
		rig.set_bone_meta(i, &"authored", "preserve_%d" % i)
		rig.set_bone_enabled(i, i != 4)
	var unrelated := BoneTwistDisperser3D.new()
	unrelated.name = "Unrelated"
	unrelated.active = false
	rig.add_child(unrelated)
	return rig
func _seed(dummy: bool = false) -> Node3D:
	var wrapper := Node3D.new()
	if dummy:
		wrapper.free()
		wrapper = (load("res://models/human_dummy/HumanCharacterDummy_M.fbx") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		wrapper.scene_file_path = ""
	wrapper.name = "Rig"
	wrapper.position = Vector3(0.8, 0, -0.6)
	wrapper.rotation.y = 0.2
	wrapper.set_meta("authored", {"keep": [1, 2, 3]})
	if not dummy: wrapper.add_child(_skeleton("Source"))
	var path := Path3D.new()
	path.name = "SharedPath"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0.2, 0.5, 0.3))
	wrapper.add_child(path)
	_pose._checks._own(wrapper, wrapper)
	return wrapper
func _fixture(label: String, layout: String) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var container := Node3D.new()
	container.name = "ModifierHistory"
	root.add_child(container)
	container.owner = root
	var original := _seed(label.ends_with("_dummy"))
	var path := "user://modifier_source_%s.tscn" % label
	var packed := PackedScene.new()
	assert_eq(packed.pack(original), OK, label + " source pack")
	assert_eq(ResourceSaver.save(packed, path), OK, label + " source save")
	var wrapper: Node3D = original
	packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if layout != "local":
		original.free()
		wrapper = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var inner_path := path
	var inner_bytes := FileAccess.get_file_as_bytes(inner_path)
	if layout.begins_with("nested_"):
		var outer := Node3D.new()
		outer.name = "Outer"
		outer.add_child(wrapper)
		wrapper.owner = outer
		outer.set_editable_instance(wrapper, layout.ends_with("1"))
		var outer_packed := PackedScene.new()
		assert_eq(outer_packed.pack(outer), OK, label + " outer source pack")
		path = "user://modifier_outer_%s.tscn" % label
		assert_eq(ResourceSaver.save(outer_packed, path), OK, label + " outer source save")
		outer.free()
		packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		outer = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		container.add_child(outer)
		outer.owner = root
		container.set_editable_instance(outer, layout.substr(7, 1) == "1")
		wrapper = outer.get_node("Rig")
	else:
		container.add_child(wrapper)
		wrapper.owner = root
		if layout == "local": _pose._checks._own(wrapper, root)
		if layout == "editable": container.set_editable_instance(wrapper, true)
	var peer := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	peer.name = "Peer"
	container.add_child(peer)
	peer.owner = root
	var targets := Node3D.new()
	targets.name = "Caller"
	targets.position = Vector3(-0.4, 0.2, 0.1)
	targets.rotation.y = -0.3
	container.add_child(targets)
	for name in ["Target", "Pole", "Origin", "Center"]:
		var node := Marker3D.new()
		node.name = name
		node.position = Vector3(0.3, 1.2, 0.4)
		node.set_meta("caller_owned", true)
		targets.add_child(node)
	for branch_name in ["A", "B"]:
		var branch := Node3D.new()
		branch.name = branch_name
		branch.position = Vector3(1.5, -0.3, 0.4)
		branch.rotation = Vector3(0.1, 0.2, 0.3)
		targets.add_child(branch)
		var collider := SpringBoneCollisionSphere3D.new()
		collider.name = "Collider"
		collider.position = Vector3(0.2, 0.7, -0.1)
		collider.radius = 0.08
		branch.add_child(collider)
	_pose._checks._own(targets, root)
	var destination := _skeleton("Receiver")
	if label.ends_with("_dummy"):
		destination.free()
		destination = wrapper.find_children("*", "Skeleton3D", true, false)[0].duplicate() as Skeleton3D
		destination.name = "Receiver"
	destination.position = Vector3(-1, 0.2, 0.5)
	destination.rotation = Vector3(0.1, 0.3, -0.1)
	root.add_child(destination)
	_pose._checks._own(destination, root)
	var sentinel := Node3D.new()
	sentinel.name = "MH_LastSibling"
	root.add_child(sentinel)
	sentinel.owner = root
	return {"container": container, "wrapper": wrapper, "source": wrapper.find_children("*", "Skeleton3D", true, false)[0], "peer": peer, "peer_rig": peer.get_node("Rig") if layout.begins_with("nested_") else peer, "path": path, "bytes": FileAccess.get_file_as_bytes(path), "inner_path": inner_path, "inner_bytes": inner_bytes, "receiver": destination, "caller": targets}
func _resolve_values(value: Variant, fixture: Dictionary) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _resolve_values(value[key], fixture)
		return result
	if value is Array:
		var result: Array = []
		for entry in value: result.append(_resolve_values(entry, fixture))
		return result
	if value is String:
		if value.begins_with("@caller/"): return str(fixture.caller.get_node(value.substr(8)).get_path())
		if value.begins_with("@source/"): return str(fixture.source.get_node(value.substr(8)).get_path())
		if value == "@source": return str(fixture.source.get_path())
	return value
func _existing_retarget(fixture: Dictionary) -> void:
	var target: Skeleton3D = fixture.receiver
	var poses: Array = []
	for i in target.get_bone_count(): poses.append(target.get_bone_pose(i))
	var modifier := RetargetModifier3D.new()
	modifier.name = "ExistingRetarget"
	modifier.active = false
	modifier.profile = SkeletonProfile.new()
	modifier.profile.set_bone_size(1)
	modifier.profile.set_bone_name(0, "hips")
	fixture.source.add_child(modifier)
	modifier.owner = EditorInterface.get_edited_scene_root()
	target.reparent(modifier, true)
	var second := _skeleton("OtherReceiver")
	modifier.add_child(second)
	_pose._checks._own(second, EditorInterface.get_edited_scene_root())
	for i in poses.size(): target.set_bone_pose(i, poses[i])
func _params(op: String, fixture: Dictionary) -> Dictionary:
	var source: Skeleton3D = fixture.source
	var params := {"op": op, "skeleton_path": str(source.get_path()), "name": "Configured", "active": false}
	match op:
		"ik_setup": params.merge({"kind": "two_bone", "chain": ["hips", "spine", "chest"], "target_name": "MH_Target", "pole_name": "MH_Pole"})
		"look_at_setup": params.merge({"bone": "chest", "target_path": str(fixture.caller.get_node("Target").get_path()), "origin_from": "external_node", "origin_node": str(fixture.caller.get_node("Origin").get_path())})
		"twist_setup": params.merge({"spine_chain": ["hips", "spine", "chest", "head"], "disperse": {"mode": "weighted", "weight_position": 0.35}})
		"spring_setup": params.springs = [{"root_bone": "spine", "end_bone": "head", "collisions": [str(fixture.caller.get_node("A/Collider").get_path())], "center_from": "world_origin", "enable_all_child_collisions": false, "stiffness": 0.7, "drag": 0.3, "gravity": 0.1, "radius": 0.02}]
		"retarget_setup": params.merge({"target_path": str(fixture.receiver.get_path()), "profile": "auto"})
	return params
func _persist(label: String, expected: Dictionary) -> String:
	var root := EditorInterface.get_edited_scene_root()
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, label + " pack")
	var path := "user://modifier_history_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK, label + " save")
	var saved := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var actual := _snapshot(saved)
	assert_true(_pose._same(actual, expected), label + " persisted exact state " + str(_pose._checks._differences(actual, expected)))
	saved.free()
	return path
func _case(op: String, layout: String, variant: String = "base", overrides: Dictionary = {}) -> void:
	var label := "%s_%s_%s" % [layout, op, variant]
	var root := EditorInterface.get_edited_scene_root()
	var previous := root.get_children()
	var fixture := _fixture(label, layout)
	if variant == "target_instance":
		var target: Skeleton3D = fixture.receiver
		var packed := PackedScene.new()
		_pose._checks._own(target, target)
		assert_eq(packed.pack(target), OK, label + " target pack")
		var target_path := "user://modifier_target_instance.tscn"
		assert_eq(ResourceSaver.save(packed, target_path), OK, label + " target save")
		var index := target.get_index()
		target.free()
		target = (ResourceLoader.load(target_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		root.add_child(target)
		root.move_child(target, index)
		target.owner = root
		fixture.receiver = target
	if variant == "different_rests":
		for i in fixture.receiver.get_bone_count():
			var rest: Transform3D = fixture.receiver.get_bone_rest(i)
			rest.origin *= 1.4
			rest.basis = rest.basis * Basis(Vector3.UP, 0.2)
			fixture.receiver.set_bone_rest(i, rest)
			fixture.receiver.set_bone_pose(i, rest)
	if variant.begins_with("existing"): _existing_retarget(fixture)
	var params: Dictionary = _resolve_values(_params(op, fixture).merged(overrides, true), fixture)
	if variant == "dummy":
		if op == "ik_setup": params.chain = ["B-upperArm.L", "B-forearm.L", "B-hand.L"]
		if op == "look_at_setup": params.bone = "B-head"
		if op == "twist_setup":
			params.spine_chain = ["B-hips", "B-spine", "B-chest"]
			params.disperse = {"root_bone": "B-hips", "end_bone": "B-chest", "mode": "even"}
		if op == "spring_setup":
			params.springs[0].root_bone = "B-forearm.L"
			params.springs[0].end_bone = "B-hand.L"
	var baseline := _snapshot(root)
	var identities := _identities(root, {})
	var peer_before := _snapshot(fixture.peer)
	var shared: Resource = fixture.wrapper.get_node("SharedPath").curve
	if layout != "local": assert_true(shared == fixture.peer_rig.get_node("SharedPath").curve, label + " source resource shared before")
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var errors := _logger.errors.size()
	var orphans := Node.get_orphan_node_ids()
	var refusal := layout == "locked" and op == "retarget_setup"
	var dry := _call(params.merged({"dry_run": true}, true))
	assert_has_key(dry.get("error", {}) if refusal else dry, "code" if refusal else "data", label + " dry response")
	assert_true(_pose._same(_snapshot(root), baseline), label + " dry unchanged")
	assert_eq(Node.get_orphan_node_ids(), orphans, label + " dry no leak")
	assert_eq(history.get_version(), version, label + " dry no action")
	var result := _call(params)
	if refusal:
		assert_has_key(result.get("error", {}), "code", label + " typed refusal")
		assert_true(_pose._same(_snapshot(root), baseline), label + " refusal unchanged")
		assert_eq(Node.get_orphan_node_ids(), orphans, label + " refusal no leak")
		assert_eq(history.get_version(), version, label + " refusal no action")
	else:
		assert_has_key(result, "data", label + " commit " + str(result))
		# Assertions accumulate; never undo an unrelated previous action after
		# a refused request, especially after its fixture has been freed.
		if not result.has("data"):
			for child in root.get_children():
				if not previous.has(child): child.free()
			return
		var data: Dictionary = result.get("data", {})
		for key in ["modifier_path", "target_path", "pole_path", "path_path", "moved_path", "collisions_moved"]:
			if data.has(key): assert_eq(dry.get("data", {}).get(key), data[key], label + " predicted " + key)
		var modifier := Codec.resolve_scene_path(str(data.get("modifier_path", "")), root)
		assert_true(modifier is SkeletonModifier3D, label + " valid modifier")
		assert_eq(history.get_version(), version + 1, label + " one scene action")
		var generated := _snapshot(root)
		var do_path := _persist(label + "_do", generated)
		var modifier_rel := str(root.get_path_to(modifier)) if modifier != null else ""
		var source_rel := str(root.get_path_to(fixture.source))
		var receiver_rel := str(root.get_path_to(fixture.receiver))
		assert_true(history.undo(), label + " undo")
		assert_true(_pose._same(_snapshot(root), baseline), label + " exact undo " + str(_pose._checks._differences(_snapshot(root), baseline)))
		assert_eq(_identities(root, {}), identities, label + " identities undo")
		var undo_path := _persist(label + "_undo", baseline)
		assert_true(history.redo(), label + " redo")
		assert_true(Codec.resolve_scene_path(str(data.get("modifier_path", "")), root) == modifier, label + " modifier identity redo")
		assert_true(_pose._same(_snapshot(root), generated), label + " exact redo")
		var redo_path := _persist(label + "_redo", generated)
		_rows.append({"id": label, "op": op, "layout": layout, "variant": variant, "params": params, "source": source_rel, "modifier": modifier_rel, "receiver": receiver_rel, "peer": str(root.get_path_to(fixture.peer_rig.find_children("*", "Skeleton3D", true, false)[0])), "states": {"do": do_path, "undo": undo_path, "redo": redo_path}})
		_manifest()
	assert_eq(global_history.get_version(), global_version, label + " no global action")
	assert_true(_pose._same(_snapshot(fixture.peer), peer_before), label + " peer unchanged")
	assert_eq(FileAccess.get_file_as_bytes(fixture.path), fixture.bytes, label + " immutable source bytes")
	assert_eq(FileAccess.get_file_as_bytes(fixture.inner_path), fixture.inner_bytes, label + " immutable inner source bytes")
	assert_true(fixture.wrapper.get_node("SharedPath").curve == shared, label + " shared resource identity")
	var pristine := (ResourceLoader.load(fixture.path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	assert_true(_pose._same(_snapshot(pristine), peer_before), label + " freshly loaded source unchanged")
	pristine.free()
	assert_eq(_logger.errors.size(), errors, label + " engine errors " + str(_logger.errors.slice(errors)))
	for child in root.get_children():
		if not previous.has(child): child.free()
func test_local_history() -> void:
	for op in OPERATIONS: _case(op, "local")
func test_locked_history() -> void:
	for op in OPERATIONS: _case(op, "locked")
func test_editable_history() -> void:
	for op in OPERATIONS: _case(op, "editable")
func test_nested_history() -> void:
	for layout in ["nested_00", "nested_01", "nested_10", "nested_11"]:
		for op in ["ik_setup", "spring_setup"]: _case(op, layout)
func test_ik_variants() -> void:
	for kind in ["two_bone", "ccdik", "fabrik", "spline"]:
		for supplied in [false, true]:
			var settings := {"kind": kind}
			if supplied:
				settings.target_path = "@caller/Target"
				if kind == "spline": settings.target_path = "@source/../SharedPath"
				if kind == "two_bone": settings.pole_path = "@caller/Pole"
			_case("ik_setup", "local", "%s_%s" % [kind, "supplied" if supplied else "generated"], settings)
	for supplied in [false, true]:
		_case("ik_setup", "local", "mixed_%s" % supplied, {"target_path": "@caller/Target"} if supplied else {"pole_path": "@caller/Pole"})
	_case("ik_setup", "local", "virtual", {"chain": ["hips", "spine"], "use_virtual_end": true, "end_bone_length": 0.25})
func test_look_at_variants() -> void:
	for origin in ["self", "bone", "external_node", "skeleton"]:
		var settings := {"origin_from": "external_node" if origin == "skeleton" else origin, "origin_bone": "spine"}
		if origin == "skeleton": settings.origin_node = "@source"
		_case("look_at_setup", "local", "origin_" + origin, settings)
	for axis in ["+x", "-x", "+y", "-y", "+z", "-z"]:
		_case("look_at_setup", "local", "axis_" + axis.replace("+", "p").replace("-", "n"), {"forward_axis": axis, "primary_axis": "z" if axis.ends_with("y") else "y", "use_secondary_rotation": true})
	for enabled in [false, true]: _case("look_at_setup", "local", "secondary_%s" % enabled, {"use_secondary_rotation": enabled})
	_case("look_at_setup", "local", "generated", {"target_path": "", "target_name": "MH_Target"})
	_case("look_at_setup", "local", "limited", {"use_angle_limitation": true, "primary_limit_angle": 30.0, "secondary_limit_angle": 20.0, "use_secondary_rotation": true})
	_case("look_at_setup", "local", "relative_timed", {"relative": true, "duration": 0.25, "use_secondary_rotation": true})
func test_twist_variants() -> void:
	_case("twist_setup", "local", "even", {"disperse": {"mode": "even"}})
	for weight in [0.0, 0.5, 1.0]: _case("twist_setup", "local", "weighted_%s" % weight, {"disperse": {"mode": "weighted", "weight_position": weight}})
	for extended in [false, true]: _case("twist_setup", "local", "extended_%s" % extended, {"disperse": {"mode": "even", "extend_end_bone": extended}})
	_case("twist_setup", "local", "reference", {"disperse": {"mode": "even", "twist_from_rest": false, "twist_from": {"kind": "quaternion", "w": 1.0}}})
	for weight in [0.0, 0.5, 1.0]: _case("twist_setup", "local", "influence_%s" % weight, {"influence": weight, "mutable_bone_axes": true})
func test_spring_variants() -> void:
	for selection in ["automatic", "listed", "excluded"]:
		var spring := {"root_bone": "spine", "end_bone": "head", "center_from": "world_origin", "enable_all_child_collisions": selection != "listed", "collisions": ["@caller/A/Collider", "@caller/B/Collider"]}
		if selection == "excluded": spring.exclude_collisions = ["@caller/B/Collider"]
		_case("spring_setup", "local", "world_origin_" + selection, {"springs": [spring], "mutable_bone_axes": true})
	for center in ["node", "bone"]:
		_case("spring_setup", "local", center + "_no_collision", {"springs": [{"root_bone": "spine", "end_bone": "head", "center_from": center, "center_bone": "hips", "center_node": "@caller/Center"}], "mutable_bone_axes": true})
	_case("spring_setup", "local", "multiple", {"springs": [{"root_bone": "hips", "end_bone": "spine"}, {"root_bone": "chest", "end_bone": "head"}]})
func test_retarget_variants() -> void:
	for field in ["position", "rotation", "scale", "all", "global"]:
		_case("retarget_setup", "local", field, {"position": field in ["position", "all"], "rotation": field in ["rotation", "all", "global"], "scale": field in ["scale", "all"], "use_global_pose": field == "global"})
	for layout in ["local", "editable"]:
		_case("retarget_setup", layout, "existing", {"position": true, "scale": true, "use_global_pose": true, "move_target": false})
	_case("retarget_setup", "local", "different_rests", {"position": true, "scale": true})
	_case("retarget_setup", "local", "target_instance")

func test_predictable_refusals() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var fixture := _fixture("refusals", "local")
	var baseline := _snapshot(root)
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var orphans := Node.get_orphan_node_ids()
	var errors := _logger.errors.size()
	var cases := [
		_params("ik_setup", fixture).merged({"kind": "jacobian"}, true),
		_params("look_at_setup", fixture).merged({"forward_axis": "+y", "primary_axis": "y"}, true),
		_params("look_at_setup", fixture).merged({"origin_from": "invalid"}, true),
		_params("retarget_setup", fixture).merged({"move_target": false}, true),
		_params("retarget_setup", fixture).merged({"target_path": str(fixture.source.get_path())}, true),
		_params("retarget_setup", fixture).merged({"position": false, "rotation": false, "scale": false}, true),
		_params("twist_setup", fixture).merged({"disperse": {"mode": "custom"}}, true),
		_params("spring_setup", fixture).merged({"springs": [{"root_bone": "head"}]}, true),
	]
	for center in ["node", "bone"]:
		for selection in ["automatic", "listed", "excluded"]:
			var spring := {"root_bone": "spine", "end_bone": "head", "center_from": center, "center_bone": "hips", "center_node": str(fixture.caller.get_node("Center").get_path()), "enable_all_child_collisions": selection != "listed", "collisions": [str(fixture.caller.get_node("A/Collider").get_path())]}
			if selection == "excluded": spring.exclude_collisions = [str(fixture.caller.get_node("B/Collider").get_path())]
			cases.append(_params("spring_setup", fixture).merged({"springs": [spring]}, true))
	for i in cases.size():
		for dry in [false, true]:
			var result := _call(cases[i].merged({"dry_run": dry}, true))
			assert_has_key(result.get("error", {}), "code", "typed refusal %d dry=%s" % [i, dry])
			if i == 0 or i >= 8: assert_eq(result.get("error", {}).get("code"), "OPERATION_UNAVAILABLE", "unsupported native combination unavailable")
			assert_true(_pose._same(_snapshot(root), baseline), "refusal scene unchanged")
			assert_eq(history.get_version(), version, "refusal scene history unchanged")
			assert_eq(global_history.get_version(), global_version, "refusal global history unchanged")
			assert_eq(Node.get_orphan_node_ids(), orphans, "refusal no allocation")
	assert_eq(_logger.errors.size(), errors, "refusal no engine errors")
	fixture.container.free()
	fixture.receiver.free()
	root.get_node("MH_LastSibling").free()
func test_dummy_history() -> void:
	for op in OPERATIONS: _case(op, "local", "dummy")
func test_registry_coverage() -> void:
	var names: Array = Ops.op_names("animation_rig_modifiers")
	names.sort()
	var expected := OPERATIONS.duplicate()
	expected.sort()
	assert_eq(names, expected, "all advertised modifiers covered")

func _stack_case(operations: Array, label: String, weight: float) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var previous := root.get_children()
	var fixture := _fixture(label, "local")
	var baseline := _snapshot(root)
	var identities := _identities(root, {})
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var errors := _logger.errors.size()
	var stack: Array = []
	var created: Array = []
	for i in operations.size():
		var op: String = operations[i]
		var params := _params(op, fixture)
		params.name = "Stage%d" % i
		if op == "look_at_setup":
			var parent_first := not label.begins_with("stack_1_")
			var parent_stage: bool = (i == 0) == parent_first
			params.bone = "chest" if parent_stage else "head"
			params.target_path = str(fixture.caller.get_node("Target" if parent_stage else "Pole").get_path())
			params.use_secondary_rotation = true
		var before := _snapshot(root)
		var orphans := Node.get_orphan_node_ids()
		var dry := _call(params.merged({"dry_run": true}, true))
		assert_has_key(dry, "data", label + " dry stage")
		assert_true(_pose._same(_snapshot(root), before), label + " dry unchanged")
		assert_eq(Node.get_orphan_node_ids(), orphans, label + " dry no allocation")
		var result := _call(params)
		assert_has_key(result, "data", label + " commit " + str(result))
		if not result.has("data"): return
		var modifier := Codec.resolve_scene_path(result.data.modifier_path, root)
		created.append(modifier)
		assert_eq(history.get_version(), version + i + 1, label + " one action per stage")
		assert_eq(dry.data.modifier_path, result.data.modifier_path, label + " predicted path")
		stack.append({"op": op, "params": params, "modifier": str(root.get_path_to(modifier))})
	var generated := _snapshot(root)
	var do_path := _persist(label + "_do", generated)
	for i in operations.size(): assert_true(history.undo(), label + " undo stage")
	assert_true(_pose._same(_snapshot(root), baseline), label + " exact stack undo")
	assert_eq(_identities(root, {}), identities, label + " stack identity undo")
	var undo_path := _persist(label + "_undo", baseline)
	for i in operations.size(): assert_true(history.redo(), label + " redo stage")
	assert_true(_pose._same(_snapshot(root), generated), label + " exact stack redo")
	for i in stack.size(): assert_true(root.get_node(stack[i].modifier) == created[i], label + " stage identity redo")
	var redo_path := _persist(label + "_redo", generated)
	_rows.append({"id": label, "op": "stack", "variant": label, "layout": "local", "stack": stack, "last_influence": weight, "source": str(root.get_path_to(fixture.source)), "peer": str(root.get_path_to(fixture.peer.find_children("*", "Skeleton3D", true, false)[0])), "states": {"do": do_path, "undo": undo_path, "redo": redo_path}})
	_manifest()
	assert_eq(global_history.get_version(), global_version, label + " stack no global action")
	assert_eq(_logger.errors.size(), errors, label + " no stack engine errors")
	for child in root.get_children():
		if not previous.has(child): child.free()

func test_ordered_stack_history() -> void:
	var orders := [["look_at_setup", "look_at_setup"], ["look_at_setup", "look_at_setup"], ["ik_setup", "look_at_setup", "twist_setup"], ["look_at_setup", "twist_setup", "ik_setup"], ["ik_setup", "spring_setup"], ["spring_setup", "ik_setup"]]
	for i in orders.size():
		for weight in [0.5, 1.0]: _stack_case(orders[i], "stack_%d_%s" % [i, weight], weight)

func _spring_trace(source: Skeleton3D, spring: SpringBoneSimulator3D, input: Array, count: int, fps: int) -> Array:
	var samples: Array = []
	var capture := func():
		var poses: Array = []
		for i in source.get_bone_count(): poses.append(source.get_bone_pose(i))
		samples.append(poses)
	spring.modification_processed.connect(capture)
	for frame in count:
		for i in input.size(): source.set_bone_pose(i, input[i])
		source.set_bone_pose_rotation(0, input[0].basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, 0.2 * sin(float(frame) / fps * TAU)))
		source.advance(1.0 / fps)
		source.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	spring.modification_processed.disconnect(capture)
	return samples

func test_spring_live_redo_restart() -> void:
	var root := EditorInterface.get_edited_scene_root()
	for fps in [30, 60, 120]:
		var previous := root.get_children()
		var fixture := _fixture("live_restart_%d" % fps, "local")
		var source: Skeleton3D = fixture.source
		source.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
		var errors := _logger.errors.size()
		var result := _call(_params("spring_setup", fixture))
		assert_has_key(result, "data", "live spring commit")
		if not result.has("data"): return
		var spring := Codec.resolve_scene_path(result.data.modifier_path, root) as SpringBoneSimulator3D
		spring.active = true
		spring.external_force = Vector3(0.7, 0.2, 0.4)
		var old_input: Array = []
		for i in source.get_bone_count(): old_input.append(source.get_bone_pose(i))
		assert_eq(_spring_trace(source, spring, old_input, fps, fps).size(), fps, "old spring accumulates momentum")
		assert_true(history.undo(), "live spring Undo")
		assert_true(spring.get_parent() == null and is_instance_valid(spring), "history retains detached simulator")
		# A new authored pose and parent position while the spring is detached.
		source.set_bone_pose_rotation(1, Quaternion(Vector3.FORWARD, 0.55))
		source.position += Vector3(0.4, 0.1, -0.2)
		var input: Array = []
		for i in source.get_bone_count(): input.append(source.get_bone_pose(i))
		assert_true(history.redo(), "live spring Redo")
		assert_true(Codec.resolve_scene_path(result.data.modifier_path, root) == spring, "same simulator restored")
		for i in input.size(): assert_true(source.get_bone_pose(i).is_equal_approx(input[i]), "Redo preserves current authored pose")
		spring.active = true
		var restored := _spring_trace(source, spring, input, 8, fps)
		for i in input.size(): source.set_bone_pose(i, input[i])
		spring.reset()
		var explicit_restart := _spring_trace(source, spring, input, 8, fps)
		assert_eq(restored.size(), 8, "Redo samples present")
		assert_eq(explicit_restart.size(), 8, "explicit restart samples present")
		for frame in 8:
			for i in input.size(): assert_true(restored[frame][i].is_equal_approx(explicit_restart[frame][i]), "Redo restarts current-pose simulation fps=%d frame=%d bone=%d" % [fps, frame, i])
		assert_eq(_logger.errors.size(), errors, "live spring no engine errors")
		for child in root.get_children():
			if not previous.has(child): child.free()
