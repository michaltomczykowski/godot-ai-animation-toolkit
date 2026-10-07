@tool
extends RefCounted

## A synchronous evaluation copy of unsaved scene state. No author-owned node
## is ever added to the sandbox or used as an animation/modifier write target.
const Errors := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
var viewport: SubViewport
var scene: Node
var source: Node
var nodes: Dictionary = {}
var resources: Dictionary = {}
var excluded_tracks: Array = []
var problem := ""

static func copy_hierarchy(node: Node) -> Node:
	return node.duplicate(0)

func open(root: Node) -> Dictionary:
	source = root
	# Refuse scripted resources before any native duplicate(true) can construct
	# their scripts. Node scripts themselves are omitted by duplicate(0).
	_check_node_resources(root, {})
	if not problem.is_empty(): return _fail(problem)
	scene = copy_hierarchy(root)
	if scene == null: return _fail("could not copy the edited hierarchy")
	_map(root, scene)
	_isolate(root)
	if not problem.is_empty(): return _fail(problem)
	_remap(root)
	if not problem.is_empty(): return _fail(problem)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_tree().root.add_child(viewport)
	viewport.add_child(scene)
	# Native retarget entry may refresh child inputs. Restore all authored poses
	# and transforms after entry, without reinstantiating the saved PackedScene.
	restore_inputs()
	return {"ok": true}

func _check_node_resources(node: Node, seen: Dictionary) -> void:
	for entry in node.get_property_list():
		var key := str(entry.name)
		if not int(entry.usage) & PROPERTY_USAGE_STORAGE or int(entry.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE or key in ["script", "owner"]: continue
		_check_resource_scripts(node.get(key), seen)
	for child in node.get_children(): _check_node_resources(child, seen)

func _check_resource_scripts(value: Variant, seen: Dictionary) -> void:
	if value is Resource:
		if value is Script or seen.has(value): return
		seen[value] = true
		if value.get_script() != null:
			problem = "scripted resource %s cannot be isolated" % value.get_class()
			return
		for entry in value.get_property_list():
			if int(entry.usage) & PROPERTY_USAGE_STORAGE and str(entry.name) != "script": _check_resource_scripts(value.get(entry.name), seen)
	elif value is Array:
		for entry in value: _check_resource_scripts(entry, seen)
	elif value is Dictionary:
		for key in value: _check_resource_scripts(value[key], seen)

func _map(original: Node, copy: Node) -> void:
	nodes[original] = copy
	copy.process_mode = Node.PROCESS_MODE_DISABLED
	if copy.get_script() != null: copy.set_script(null)
	for key in copy.get_meta_list(): copy.remove_meta(key)
	if copy is AnimationMixer:
		copy.active = false
		copy.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if copy is Skeleton3D:
		copy.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	for child in original.get_children():
		var counterpart := copy.get_node_or_null(NodePath(str(child.name)))
		if counterpart != null: _map(child, counterpart)

func _resource(value: Resource) -> Resource:
	if value == null: return null
	if value is Script: return null
	if resources.has(value): return resources[value]
	if value.get_script() != null:
		problem = "scripted resource %s cannot be isolated" % value.resource_path
		return null
	var copy := value.duplicate(true)
	if copy == null:
		problem = "resource %s could not be isolated" % value.get_class()
		return null
	resources[value] = copy
	return copy

func _isolate(original: Node) -> void:
	var copy: Node = nodes[original]
	var native_properties := {}
	for entry in copy.get_property_list(): native_properties[str(entry.name)] = true
	if original is AnimationMixer:
		for name in copy.get_animation_library_list(): copy.remove_animation_library(name)
		for name in original.get_animation_library_list():
			var library: AnimationLibrary = original.get_animation_library(name).duplicate(true)
			if library != null: copy.add_animation_library(name, library)
	for entry in original.get_property_list():
		var key := str(entry.name)
		if not int(entry.usage) & PROPERTY_USAGE_STORAGE or key in ["script", "owner", "libraries"] or not native_properties.has(key): continue
		var value: Variant = original.get(key)
		if value is AnimationNodeStateMachinePlayback:
			copy.set(key, AnimationNodeStateMachinePlayback.new())
			continue
		if value is Resource or value is Array or value is Dictionary:
			copy.set(key, _value(value))
	for child in original.get_children():
		if nodes.has(child): _isolate(child)

func _value(value: Variant) -> Variant:
	if value is Resource: return _resource(value)
	if value is Array:
		var result: Array = value.duplicate()
		for i in result.size(): result[i] = _value(result[i])
		return result
	if value is Dictionary:
		var result: Dictionary = value.duplicate()
		for key in result: result[key] = _value(result[key])
		return result
	return value

func _path(original: Node, copy: Node, path: NodePath) -> NodePath:
	if path.is_empty(): return path
	var names := NodePath(path.get_concatenated_names())
	var target := original.get_node_or_null(names)
	if target == null:
		problem = "unresolved NodePath '%s' on %s" % [path, original.get_path()]
		return path
	if not nodes.has(target):
		problem = "external dependency '%s' on %s" % [path, original.get_path()]
		return path
	var remapped := str(copy.get_path_to(nodes[target]))
	var subnames := path.get_concatenated_subnames()
	return NodePath(remapped + (":" + subnames if not subnames.is_empty() else ""))

func _remap(original: Node) -> void:
	var copy: Node = nodes[original]
	var native_properties := {}
	for entry in copy.get_property_list(): native_properties[str(entry.name)] = true
	for entry in original.get_property_list():
		var key := str(entry.name)
		if not int(entry.usage) & PROPERTY_USAGE_STORAGE or key in ["script", "owner", "root_motion_track"] or not native_properties.has(key): continue
		var value: Variant = original.get(key)
		if value is NodePath or value is Array or value is Dictionary: copy.set(key, _paths(original, copy, copy.get(key)))
	if original is AnimationMixer:
		var origin := original.get_node_or_null(original.root_node)
		if origin != null: copy.root_motion_track = _path(origin, nodes[origin], original.root_motion_track)
	if original is AnimationPlayer:
		var origin := original.get_node_or_null(original.root_node)
		if origin == null:
			problem = "unresolved animation root on %s" % original.get_path()
		else:
			for library_name in copy.get_animation_library_list():
				var library: AnimationLibrary = copy.get_animation_library(library_name)
				for name in library.get_animation_list():
					var animation := library.get_animation(name)
					if animation.get_script() != null:
						problem = "scripted animation '%s' cannot be replayed" % name
						return
					# Rooted libraries can be shared by multiple players. Give each
					# player its own animations before rewriting track paths.
					animation = animation.duplicate(true)
					library.remove_animation(name)
					library.add_animation(name, animation)
					for i in range(animation.get_track_count() - 1, -1, -1):
						if animation.track_get_type(i) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION]:
							excluded_tracks.append({"player": str(original.get_path()), "animation": str(name), "track": i})
							animation.remove_track(i)
							continue
						if not animation.track_is_enabled(i):
							animation.remove_track(i)
							continue
						var invalid := _track_problem(origin, animation, i)
						if not invalid.is_empty():
							problem = "animation '%s' track %d: %s" % [name, i, invalid]
							return
						animation.track_set_path(i, _path(origin, nodes[origin], animation.track_get_path(i)))
	for child in original.get_children():
		if nodes.has(child): _remap(child)

func _track_problem(origin: Node, animation: Animation, index: int) -> String:
	var path := animation.track_get_path(index)
	var target := origin.get_node_or_null(NodePath(path.get_concatenated_names()))
	if target == null or not nodes.has(target): return "unresolved/external target " + str(path)
	var type := animation.track_get_type(index)
	if type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
		if not target is Node3D: return "3D transform target is not Node3D"
		if path.get_subname_count() > 0:
			if not target is Skeleton3D or path.get_subname_count() != 1 or target.find_bone(path.get_subname(0)) < 0: return "unknown bone " + str(path)
	elif type in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER]:
		if path.get_subname_count() != 1: return "nested/custom property cannot be reproduced: " + str(path)
		var known := false
		for entry in nodes[target].get_property_list():
			if str(entry.name) == str(path.get_subname(0)) and not int(entry.usage) & PROPERTY_USAGE_READ_ONLY: known = true
		if not known: return "property unavailable on native copy: " + str(path)
	elif type == Animation.TYPE_BLEND_SHAPE:
		if not target is MeshInstance3D or target.mesh == null or path.get_subname_count() != 1: return "invalid blend shape target"
		var name := str(path.get_subname(0)).trim_prefix("blend_shapes/")
		if target.find_blend_shape_by_name(name) < 0: return "unknown blend shape " + name
	else: return "unsupported track type " + str(type)
	if animation.track_get_key_count(index) == 0: return "enabled track has no keys"
	for i in animation.track_get_key_count(index):
		var value: Variant = animation.track_get_key_value(index, i)
		if type == Animation.TYPE_ROTATION_3D and (not value is Quaternion or not value.is_finite() or not value.is_normalized()): return "rotation key must be a finite normalized quaternion"
		if type in [Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D] and (not value is Vector3 or not value.is_finite()): return "transform key must be a finite Vector3"
		if value is float and not is_finite(value): return "key must be finite"
	return ""

func _paths(original: Node, copy: Node, value: Variant) -> Variant:
	if value is NodePath: return _path(original, copy, value)
	if value is Array:
		var result: Array = value.duplicate()
		for i in result.size(): result[i] = _paths(original, copy, result[i])
		return result
	if value is Dictionary:
		var result: Dictionary = value.duplicate()
		for key in result: result[key] = _paths(original, copy, result[key])
		return result
	return value

func restore_inputs() -> void:
	for original in nodes:
		var copy: Node = nodes[original]
		if original is Node3D and copy is Node3D: copy.transform = original.transform
		if original is Skeleton3D:
			for i in original.get_bone_count(): copy.set_bone_pose(i, original.get_bone_pose(i))

func get_copy(original: Node) -> Node:
	return nodes.get(original)

func close() -> void:
	if is_instance_valid(viewport): viewport.free()
	elif is_instance_valid(scene): scene.free()
	viewport = null
	scene = null
	nodes.clear()
	resources.clear()

func _fail(message: String) -> Dictionary:
	close()
	return Errors.make(Errors.OPERATION_UNAVAILABLE, "Bake evaluation sandbox: " + message)

func _notification(what: int) -> void:
	# GDScript cannot dispatch another script method during RefCounted teardown.
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(viewport): viewport.free()
		elif is_instance_valid(scene): scene.free()
