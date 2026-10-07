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
						animation.track_set_path(i, _path(origin, nodes[origin], animation.track_get_path(i)))
	for child in original.get_children():
		if nodes.has(child): _remap(child)

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
