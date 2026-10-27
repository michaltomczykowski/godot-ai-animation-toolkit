extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://models/x_bot/X Bot.fbx")
	if packed == null:
		print("XBOT_ERROR=load_failed")
		quit(1)
		return
	var root := packed.instantiate()
	get_root().add_child(root)
	_visit(root, "")
	quit()


func _visit(node: Node, prefix: String) -> void:
	print("XBOT_NODE=%s%s:%s" % [prefix, node.name, node.get_class()])
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		print("XBOT_SKELETON=%s bones=%d transform=%s" % [
			str(skeleton.get_path()), skeleton.get_bone_count(), str(skeleton.global_transform)])
		for index in skeleton.get_bone_count():
			print("XBOT_BONE=%d:%s parent=%d rest=%s" % [
				index, skeleton.get_bone_name(index), skeleton.get_bone_parent(index),
				str(skeleton.get_bone_global_rest(index).origin)])
	for child in node.get_children():
		_visit(child, prefix + "  ")
