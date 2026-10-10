extends SceneTree
const Native := preload("res://tools/character_quality_native.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var rows: Array = []
	for row: Dictionary in manifest.cases:
		var view := Native.load_case(row, root)
		var hands := {}
		for side in ["l", "r"]:
			var index: int = view.indices["hand_" + side]
			var descendants: Array = []
			var pending: Array = [index]
			while not pending.is_empty():
				var bone: int = pending.pop_front()
				var parent: int = view.rig.get_bone_parent(bone)
				var transform: Transform3D = view.rig.get_bone_global_rest(bone)
				descendants.append({"name": view.rig.get_bone_name(bone), "parent": view.rig.get_bone_name(parent) if parent >= 0 else "",
					"origin": Native.values(transform.origin), "basis": [Native.values(transform.basis.x), Native.values(transform.basis.y), Native.values(transform.basis.z)]})
				for child in view.rig.get_bone_children(bone): pending.append(child)
			hands[side] = descendants
		rows.append({"id": row.id, "hands": hands})
		view.scene.free()
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify({"rows": rows}, "\t"))
	quit()
