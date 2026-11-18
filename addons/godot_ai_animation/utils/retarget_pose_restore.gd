@tool
extends Node

## RetargetModifier3D clears cached child poses while loading/reparenting.
## Store the current authored inputs at scene-pack time, then restore them
## once after the engine's child-cache initialization. No per-frame writes.
var _loaded_poses: Dictionary = {}

func _get_property_list() -> Array[Dictionary]:
	return [{"name": "authored_child_poses", "type": TYPE_DICTIONARY, "usage": PROPERTY_USAGE_STORAGE}]

func _get(property: StringName) -> Variant:
	if property != &"authored_child_poses": return null
	var parent := get_parent()
	if parent == null: return _loaded_poses
	var poses := {}
	for child in parent.get_children():
		if child is Skeleton3D:
			var bones := {}
			for i in child.get_bone_count(): bones[child.get_bone_name(i)] = child.get_bone_pose(i)
			poses[str(child.name)] = bones
	return poses

func _set(property: StringName, value: Variant) -> bool:
	if property != &"authored_child_poses": return false
	_loaded_poses = value
	return true

func _ready() -> void:
	# Queue after the parent's deferred child-cache refresh, including its
	# notification after this child's ready notification.
	_queue_restore.call_deferred()

func _queue_restore() -> void: _restore.call_deferred()

func _restore() -> void:
	var parent := get_parent() as RetargetModifier3D
	if parent == null or parent.active:
		_loaded_poses.clear()
		return
	for name in _loaded_poses:
		var child := parent.get_node_or_null(NodePath(name)) as Skeleton3D
		if child == null: continue
		for bone_name in _loaded_poses[name]:
			var index := child.find_bone(bone_name)
			if index >= 0: child.set_bone_pose(index, _loaded_poses[name][bone_name])
	_loaded_poses.clear()
